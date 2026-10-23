// Integration tests against a REAL PostgreSQL database.
// Locally: `docker compose up -d db` first. In CI: a Postgres service container.
// They only create and delete their own rows (SKU prefix "TEST-").
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../../src/app.js';
import { createPool } from '../../src/db.js';
import { runMigrations } from '../../src/migrate.js';

process.env.LOG_LEVEL = 'error';

const pool = createPool();
const app = createApp({ pool });
let products; // { widget, gadget } -> ids

async function cleanup() {
  await pool.query(`DELETE FROM orders WHERE id IN (
    SELECT oi.order_id FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE p.sku LIKE 'TEST-%')`);
  await pool.query(`DELETE FROM products WHERE sku LIKE 'TEST-%'`);
}

async function stockOf(id) {
  const { rows } = await pool.query('SELECT stock FROM products WHERE id = $1', [id]);
  return rows[0].stock;
}

before(async () => {
  try {
    await pool.query('SELECT 1');
  } catch (err) {
    throw new Error(`Cannot reach PostgreSQL (${err.message}). Start it with: docker compose up -d db`, { cause: err });
  }
  await runMigrations(pool);
});

beforeEach(async () => {
  await cleanup();
  const { rows } = await pool.query(
    `INSERT INTO products (sku, name, price_cents, stock) VALUES
       ('TEST-WIDGET', 'Test Widget', 1000, 5),
       ('TEST-GADGET', 'Test Gadget', 250, 3)
     RETURNING id, sku`,
  );
  products = Object.fromEntries(rows.map((r) => [r.sku === 'TEST-WIDGET' ? 'widget' : 'gadget', r.id]));
});

after(async () => {
  await cleanup();
  await pool.end();
});

test('migrations are idempotent (running twice changes nothing)', async () => {
  await runMigrations(pool);
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM schema_migrations');
  assert.equal(rows[0].n, 2);
});

test('GET /ready reports the database as reachable', async () => {
  const res = await request(app).get('/ready');
  assert.equal(res.status, 200);
});

test('GET /api/products lists seeded and test products', async () => {
  const res = await request(app).get('/api/products');
  assert.equal(res.status, 200);
  const skus = res.body.products.map((p) => p.sku);
  assert.ok(skus.includes('MUG-001'), 'seed data present');
  assert.ok(skus.includes('TEST-WIDGET'));
});

test('GET /api/products/:id returns 404 for a missing product', async () => {
  const res = await request(app).get('/api/products/2147483647');
  assert.equal(res.status, 404);
});

test('placing an order saves it, computes the total and reduces stock', async () => {
  const res = await request(app).post('/api/orders').send({
    customerEmail: 'buyer@example.com',
    items: [{ productId: products.widget, quantity: 2 }, { productId: products.gadget, quantity: 1 }],
  });
  assert.equal(res.status, 201);
  assert.equal(res.body.order.totalCents, 2 * 1000 + 250);
  assert.equal(await stockOf(products.widget), 3);
  assert.equal(await stockOf(products.gadget), 2);

  const fetched = await request(app).get(`/api/orders/${res.body.order.id}`);
  assert.equal(fetched.status, 200);
  assert.equal(fetched.body.order.items.length, 2);
  assert.equal(fetched.body.order.totalCents, 2250);
});

test('insufficient stock returns 409 and rolls back the WHOLE order', async () => {
  // Widget has enough stock, gadget does not: neither may change.
  const res = await request(app).post('/api/orders').send({
    customerEmail: 'buyer@example.com',
    items: [{ productId: products.widget, quantity: 1 }, { productId: products.gadget, quantity: 4 }],
  });
  assert.equal(res.status, 409);
  assert.deepEqual(res.body.details, [{ productId: products.gadget, requested: 4, available: 3 }]);
  assert.equal(await stockOf(products.widget), 5);
  assert.equal(await stockOf(products.gadget), 3);
});

test('ordering an unknown product returns 404 and changes nothing', async () => {
  const res = await request(app).post('/api/orders').send({
    customerEmail: 'buyer@example.com',
    items: [{ productId: products.widget, quantity: 1 }, { productId: 2147483647, quantity: 1 }],
  });
  assert.equal(res.status, 404);
  assert.equal(await stockOf(products.widget), 5);
});

test('concurrent orders never oversell the last items', async () => {
  // Gadget has 3 in stock. Fire 6 simultaneous single-item orders.
  const attempts = await Promise.all(
    Array.from({ length: 6 }, () =>
      request(app).post('/api/orders').send({
        customerEmail: 'rush@example.com',
        items: [{ productId: products.gadget, quantity: 1 }],
      }),
    ),
  );
  const statuses = attempts.map((r) => r.status).sort();
  assert.deepEqual(statuses, [201, 201, 201, 409, 409, 409]);
  assert.equal(await stockOf(products.gadget), 0);
});
