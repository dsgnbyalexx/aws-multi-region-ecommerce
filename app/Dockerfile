# syntax=docker/dockerfile:1

# ---- Stage 1: install production dependencies only ----
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- Stage 2: small runtime image ----
FROM node:24-alpine
ENV NODE_ENV=production
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY migrations ./migrations
COPY public ./public

# The official image ships a non-root "node" user. Running as non-root limits
# the damage if the app is ever compromised.
USER node

EXPOSE 3000

# Lets Docker (and you, via `docker ps`) see whether the app is healthy.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3000/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

# Exec form (JSON array) so Node is PID 1 and receives SIGTERM directly.
CMD ["node", "src/server.js"]
