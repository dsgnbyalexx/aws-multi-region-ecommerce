import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { createPool } from './db.js';
import { logger } from './logger.js';

const MIGRATIONS_DIR = fileURLToPath(new URL('../migrations/', import.meta.url));
// Arbitrary constant. Every app instance uses the same number, so only one
// instance at a time can hold the lock and run migrations.
const MIGRATION_LOCK_ID = 727274;

// Applies each migrations/*.sql file exactly once, in filename order, each in
// its own transaction. Safe to call from several instances starting at once
// (e.g. an Auto Scaling group) because of the advisory lock.
export async function runMigrations(pool) {
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_ID]);
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        name        TEXT PRIMARY KEY,
        applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
      )`);

    const { rows } = await client.query('SELECT name FROM schema_migrations');
    const applied = new Set(rows.map((r) => r.name));
    const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();

    for (const file of files) {
      if (applied.has(file)) continue;
      const sql = await readFile(path.join(MIGRATIONS_DIR, file), 'utf8');
      try {
        await client.query('BEGIN');
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
        await client.query('COMMIT');
        logger.info('migration applied', { file });
      } catch (err) {
        await client.query('ROLLBACK');
        throw new Error(`migration ${file} failed: ${err.message}`, { cause: err });
      }
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK_ID]).catch(() => {});
    client.release();
  }
}

// Allow `npm run migrate` to run this file directly.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const pool = createPool();
  try {
    await runMigrations(pool);
    logger.info('migrations complete');
  } catch (err) {
    logger.error('migrations failed', { error: err.message });
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}
