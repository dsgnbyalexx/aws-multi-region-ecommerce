import pg from 'pg';

// The pg library reads PGHOST, PGPORT, PGDATABASE, PGUSER and PGPASSWORD from
// the environment automatically, so no connection details live in code.
export function createPool() {
  return new pg.Pool({
    max: Number(process.env.PGPOOL_MAX || 10),
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
  });
}
