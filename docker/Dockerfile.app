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

# Install curl for healthcheck and tini for clean PID 1 signal handling
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl tini \
    && rm -rf /var/lib/apt/lists/*

# Install production dependencies only
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy built server and client assets from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# Set production environment variables
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4321

EXPOSE 4321

# Container healthcheck against /health endpoint
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:4321/health || exit 1

# Run as non-root user
USER node

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "./dist/server/entry.mjs"]
