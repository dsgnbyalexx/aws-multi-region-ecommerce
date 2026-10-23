import { createApp } from './app.js';
import { createPool } from './db.js';
import { runMigrations } from './migrate.js';
import { logger } from './logger.js';

const port = Number(process.env.PORT || 3000);
const pool = createPool();
let shuttingDown = false;

if (process.env.RUN_MIGRATIONS === 'true') {
  await runMigrations(pool);
}

const app = createApp({ pool, isShuttingDown: () => shuttingDown });
const server = app.listen(port, () => logger.info('server started', { port }));

// Graceful shutdown. When a container or instance is being replaced (scale-in,
// blue/green deploy), it receives SIGTERM. We stop reporting "ready", finish
// in-flight requests, close DB connections, then exit.
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info('shutdown started', { signal });

  server.close(async (err) => {
    await pool.end().catch(() => {});
    logger.info('shutdown complete');
    process.exit(err ? 1 : 0);
  });

  // Do not hang forever if a connection refuses to close.
  setTimeout(() => {
    logger.error('forced shutdown after timeout');
    process.exit(1);
  }, 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
