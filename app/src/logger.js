// Minimal structured (JSON) logger. One JSON object per line is what log
// collectors such as CloudWatch Logs can search and filter on.
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };

function threshold() {
  return LEVELS[(process.env.LOG_LEVEL || 'info').toLowerCase()] ?? LEVELS.info;
}

let sink = (level, line) => (level === 'error' ? process.stderr : process.stdout).write(line + '\n');

// Lets tests capture log lines without hijacking process.stdout.
// Returns the previous sink so it can be restored.
export function setLogSink(fn) {
  const previous = sink;
  sink = fn;
  return previous;
}

function log(level, msg, fields = {}) {
  if (LEVELS[level] < threshold()) return;
  sink(level, JSON.stringify({ time: new Date().toISOString(), level, msg, ...fields }));
}

export const logger = {
  debug: (msg, fields) => log('debug', msg, fields),
  info: (msg, fields) => log('info', msg, fields),
  warn: (msg, fields) => log('warn', msg, fields),
  error: (msg, fields) => log('error', msg, fields),
};
