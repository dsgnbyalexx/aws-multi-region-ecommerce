import { Router } from 'express';
import { HttpError } from '../errors.js';
import { parseId } from '../validation.js';

export function productsRouter({ pool }) {
  const router = Router();

  router.get('/', async (_req, res) => {
    const { rows } = await pool.query(
      `SELECT id, sku, name, description, price_cents AS "priceCents", stock
         FROM products ORDER BY id`,
    );
    res.json({ products: rows });
  });

  router.get('/:id', async (req, res) => {
    const id = parseId(req.params.id);
    if (id === null) throw new HttpError(400, 'product id must be a positive integer');
    const { rows } = await pool.query(
      `SELECT id, sku, name, description, price_cents AS "priceCents", stock
         FROM products WHERE id = $1`,
      [id],
    );
    if (rows.length === 0) throw new HttpError(404, 'product not found');
    res.json({ product: rows[0] });
  });

  return router;
}
