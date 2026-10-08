# syntax=docker/dockerfile:1
# -------------------------------------------------------------
# Stage 1: Build the Astro application
# -------------------------------------------------------------
FROM node:22-bookworm-slim AS builder

WORKDIR /app

# Install dependencies needed for build
COPY package.json package-lock.json ./
RUN npm ci

# Copy application source code
COPY . .

# Build the Astro SSR standalone server
RUN npm run build

# -------------------------------------------------------------
# Stage 2: Minimal Production Runtime
# -------------------------------------------------------------
FROM node:22-bookworm-slim AS runner

WORKDIR /app

# Install curl for healthcheck, tini for signal handling, and gosu for dropping privileges
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl tini gosu \
    && rm -rf /var/lib/apt/lists/*

# Install production dependencies only
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy built server and client assets from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# Copy entrypoint script
COPY docker/entrypoint-app.sh ./docker/entrypoint-app.sh
RUN chmod +x ./docker/entrypoint-app.sh

# Set production environment variables
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4321 \
    NODE_OPTIONS="--experimental-sqlite"

EXPOSE 4321

# Container healthcheck against /health endpoint
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:4321/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/app/docker/entrypoint-app.sh"]
CMD ["node", "./dist/server/entry.mjs"]
