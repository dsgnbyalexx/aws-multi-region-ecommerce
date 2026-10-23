# syntax=docker/dockerfile:1

# ---- Stage 1: install production dependencies only ----
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- Stage 2: small runtime image ----
FROM node:24-alpine
ENV NODE_ENV=production

# The app never runs npm/npx/yarn/corepack at runtime (dependencies were
# installed in the build stage). Removing them shrinks the attack surface:
# vulnerability scans found HIGH CVEs only in npm's own bundled packages.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-*

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
