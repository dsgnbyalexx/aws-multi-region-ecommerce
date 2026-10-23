import express from 'express';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { HttpError } from './errors.js';
import { logger } from './logger.js';
import { productsRouter } from './routes/products.js';
import { ordersRouter } from './routes/orders.js';

const PUBLIC_DIR = fileURLToPath(new URL('../public/', import.meta.url));

// Builds the Express app. The database pool is passed in (not created here) so
// tests can supply a fake one.
export function createApp({ pool, isShuttingDown = () => false }) {
  const app = express();
  app.disable('x-powered-by');

  // Give every request an id and log it as one JSON line when it finishes.
  app.use((req, res, next) => {
    const requestId = req.get('x-request-id') || randomUUID();
    res.set('x-request-id', requestId);
    const start = process.hrtime.bigint();
    // Capture the path now: routers rewrite req.path while handling the request.
    const path = req.originalUrl.split('?')[0];
    res.on('finish', () => {
      logger.info('request', {
        requestId,
        method: req.method,
        path,
        status: res.statusCode,
        durationMs: Number((process.hrtime.bigint() - start) / 1000000n),
      });
    });
    next();
  });

  // Liveness: "is the process running?" Never touches the database, so a slow
  // database does not make the load balancer kill healthy app servers.
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  // Readiness: "can this instance serve real traffic right now?"
  app.get('/ready', async (_req, res) => {
    if (isShuttingDown()) return res.status(503).json({ status: 'shutting_down' });
    try {
      await pool.query('SELECT 1');
      res.json({ status: 'ready', database: 'ok' });
    } catch (err) {
      logger.warn('readiness check failed', { error: err.message });
      res.status(503).json({ status: 'unavailable', database: 'unreachable' });
    }
  });

  app.use(express.json({ limit: '10kb' }));
  app.use('/api/products', productsRouter({ pool }));
  app.use('/api/orders', ordersRouter({ pool }));
  app.use(express.static(PUBLIC_DIR));

  app.use((_req, _res, next) => next(new HttpError(404, 'not found')));

  // Central error handler. Express 5 forwards errors thrown in async routes here.
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err.type === 'entity.parse.failed') {
      return res.status(400).json({ error: 'request body is not valid JSON' });
    }
    if (err.type === 'entity.too.large') {
      return res.status(413).json({ error: 'request body too large' });
    }
    if (err instanceof HttpError) {
      return res.status(err.status).json({ error: err.message, ...(err.details && { details: err.details }) });
    }
    // Unknown errors: log the details, but never leak them to the client.
    logger.error('unhandled error', { error: err.message, stack: err.stack });
    res.status(500).json({ error: 'internal server error' });
  });

  return app;
}
