// HTTP-level tests with a FAKE database pool. These prove the API's own
// behaviour (health checks, validation, error handling) without PostgreSQL.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../../src/app.js';
import { setLogSink } from '../../src/logger.js';

process.env.LOG_LEVEL = 'error';
// Several tests trigger errors on purpose; keep their logs out of the test output.
setLogSink(() => {});

const healthyPool = { query: async () => ({ rows: [{ '?column?': 1 }] }) };
const brokenPool = { query: async () => { throw new Error('connection refused'); } };

test('GET /health returns 200 even when the database is down', async () => {
  const res = await request(createApp({ pool: brokenPool })).get('/health');
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { status: 'ok' });
});

test('GET /ready returns 200 when the database answers', async () => {
  const res = await request(createApp({ pool: healthyPool })).get('/ready');
  assert.equal(res.status, 200);
  assert.equal(res.body.database, 'ok');
});

test('GET /ready returns 503 when the database is unreachable', async () => {
  const res = await request(createApp({ pool: brokenPool })).get('/ready');
  assert.equal(res.status, 503);
  assert.equal(res.body.database, 'unreachable');
});

test('GET /ready returns 503 while shutting down', async () => {
  const res = await request(createApp({ pool: healthyPool, isShuttingDown: () => true })).get('/ready');
  assert.equal(res.status, 503);
  assert.equal(res.body.status, 'shutting_down');
});

test('every response carries a request id, and a supplied one is echoed back', async () => {
  const app = createApp({ pool: healthyPool });
  const generated = await request(app).get('/health');
  assert.match(generated.headers['x-request-id'], /^[0-9a-f-]{36}$/);
  const echoed = await request(app).get('/health').set('x-request-id', 'trace-123');
  assert.equal(echoed.headers['x-request-id'], 'trace-123');
});

test('request logs record the full original path, not the router-relative one', async () => {
  const lines = [];
  const previousSink = setLogSink((_level, line) => lines.push(line));
  process.env.LOG_LEVEL = 'info';
  try {
    await request(createApp({ pool: brokenPool })).get('/api/products/abc?x=1');
  } finally {
    setLogSink(previousSink);
    process.env.LOG_LEVEL = 'error';
  }
  const entry = lines.map((l) => JSON.parse(l)).find((e) => e.msg === 'request');
  assert.equal(entry.path, '/api/products/abc');
  assert.equal(entry.status, 400);
});

test('POST /api/orders rejects invalid JSON with 400', async () => {
  const res = await request(createApp({ pool: healthyPool }))
    .post('/api/orders')
    .set('Content-Type', 'application/json')
    .send('{"broken":');
  assert.equal(res.status, 400);
  assert.match(res.body.error, /not valid JSON/);
});

test('POST /api/orders rejects an invalid order before touching the database', async () => {
  let connected = false;
  const pool = { ...healthyPool, connect: async () => { connected = true; } };
  const res = await request(createApp({ pool })).post('/api/orders').send({ customerEmail: 'bad', items: [] });
  assert.equal(res.status, 400);
  assert.ok(res.body.details.length >= 2);
  assert.equal(connected, false);
});

test('GET /api/products/abc returns 400 for a non-numeric id', async () => {
  const res = await request(createApp({ pool: healthyPool })).get('/api/products/abc');
  assert.equal(res.status, 400);
});

test('unexpected errors return a generic 500 without leaking details', async () => {
  const res = await request(createApp({ pool: brokenPool })).get('/api/products');
  assert.equal(res.status, 500);
  assert.deepEqual(res.body, { error: 'internal server error' });
});

test('unknown routes return a JSON 404', async () => {
  const res = await request(createApp({ pool: healthyPool })).get('/does-not-exist');
  assert.equal(res.status, 404);
  assert.deepEqual(res.body, { error: 'not found' });
});

test('the X-Powered-By header is not sent', async () => {
  const res = await request(createApp({ pool: healthyPool })).get('/health');
  assert.equal(res.headers['x-powered-by'], undefined);
});
