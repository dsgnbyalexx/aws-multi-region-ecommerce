import { Router } from 'express';
import { HttpError } from '../errors.js';
import { parseId, validateOrder } from '../validation.js';
import { logger } from '../logger.js';

export function ordersRouter({ pool }) {
  const router = Router();

  // Place an order. Everything happens in ONE database transaction: either the
  // order is saved AND stock is reduced, or nothing changes at all.
  router.post('/', async (req, res) => {
    const result = validateOrder(req.body);
    if (!result.ok) throw new HttpError(400, 'invalid order', result.errors);
    const { customerEmail, items } = result.value;
    const ids = items.map((i) => i.productId);

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // FOR UPDATE locks these product rows until COMMIT, so two customers
      // cannot buy the last item at the same time. Locking in id order
      // prevents deadlocks between concurrent orders.
      const { rows: products } = await client.query(
        `SELECT id, name, price_cents, stock FROM products
          WHERE id = ANY($1::int[]) ORDER BY id FOR UPDATE`,
        [ids],
      );

      const byId = new Map(products.map((p) => [p.id, p]));
      const missing = ids.filter((id) => !byId.has(id));
      if (missing.length > 0) throw new HttpError(404, 'unknown product', { productIds: missing });

      const shortages = items
        .filter((i) => byId.get(i.productId).stock < i.quantity)
        .map((i) => ({ productId: i.productId, requested: i.quantity, available: byId.get(i.productId).stock }));
      if (shortages.length > 0) throw new HttpError(409, 'insufficient stock', shortages);

      const totalCents = items.reduce((sum, i) => sum + byId.get(i.productId).price_cents * i.quantity, 0);

      const { rows: [order] } = await client.query(
        `INSERT INTO orders (customer_email, total_cents) VALUES ($1, $2)
         RETURNING id, status, created_at AS "createdAt"`,
        [customerEmail, totalCents],
      );

      for (const i of items) {
        await client.query('UPDATE products SET stock = stock - $1 WHERE id = $2', [i.quantity, i.productId]);
        await client.query(
          `INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
           VALUES ($1, $2, $3, $4)`,
          [order.id, i.productId, i.quantity, byId.get(i.productId).price_cents],
        );
      }

      await client.query('COMMIT');
      logger.info('order placed', { orderId: order.id, totalCents, itemCount: items.length });

      res.status(201).json({
        order: {
          id: order.id,
          status: order.status,
          customerEmail,
          totalCents,
          createdAt: order.createdAt,
          items: items.map((i) => ({
            productId: i.productId,
            name: byId.get(i.productId).name,
            quantity: i.quantity,
            unitPriceCents: byId.get(i.productId).price_cents,
          })),
        },
      });
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  });

  router.get('/:id', async (req, res) => {
    const id = parseId(req.params.id);
    if (id === null) throw new HttpError(400, 'order id must be a positive integer');

    const { rows: [order] } = await pool.query(
      `SELECT id, status, customer_email AS "customerEmail", total_cents AS "totalCents",
              created_at AS "createdAt"
         FROM orders WHERE id = $1`,
      [id],
    );
    if (!order) throw new HttpError(404, 'order not found');

    const { rows: items } = await pool.query(
      `SELECT oi.product_id AS "productId", p.name, oi.quantity,
              oi.unit_price_cents AS "unitPriceCents"
         FROM order_items oi JOIN products p ON p.id = oi.product_id
        WHERE oi.order_id = $1 ORDER BY oi.product_id`,
      [id],
    );
    res.json({ order: { ...order, items } });
  });

  return router;
}
