# === Build stage ===
FROM node:20-alpine AS builder
WORKDIR /usr/src/app
COPY package*.json ./

# If package-lock.json is missing, fallback to npm install
RUN if [ -f package-lock.json ]; then npm ci --omit=dev --no-audit --no-fund; else npm install --production --no-audit --no-fund; fi

COPY . .
# If you have a build step:
RUN npm run build --if-present
RUN rm -rf tests docs *.md

# === Runtime stage ===
FROM gcr.io/distroless/nodejs20-debian12:nonroot
WORKDIR /app

# Copy artifact from builder
COPY --from=builder /usr/src/app /app

ENV NODE_ENV=production
EXPOSE 3000

# Healthcheck using “node” (no shell available)  
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://127.0.0.1:3000', ()=>process.exit(0)).on('error', ()=>process.exit(1))"]

USER nonroot
ENTRYPOINT ["node", "dist/index.js"]
