# === Build stage ===
FROM node:20-bullseye-slim AS builder

WORKDIR /usr/src/app

# Copy only package manifests first for caching
COPY package*.json ./

# Install production deps only
RUN npm ci --omit=dev --no-audit --no-fund

# Copy rest of source
COPY . .

# If you have a build step (e.g., TypeScript, bundling), do it here:
RUN npm run build --if-present

# Optionally clean up unneeded files (tests, docs, etc)
RUN rm -rf tests docs *.md

# === Runtime stage ===
FROM gcr.io/distroless/nodejs20-debian12:nonroot

WORKDIR /app

# Copy built files + dependencies
COPY --from=builder /usr/src/app /app

# Set environment
ENV NODE_ENV=production

# Expose port (if relevant)
EXPOSE 3000

# Healthcheck — since there is no shell, use JSON form.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://127.0.0.1:3000', ()=>process.exit(0)).on('error', ()=>process.exit(1))"]

# Entrypoint — adjust to your start script / compiled entry file.
ENTRYPOINT ["node", "dist/index.js"]
