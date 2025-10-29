# syntax=docker/dockerfile:1
############################################
# Builder stage: fetch repo, deps, build
############################################
FROM node:20-alpine AS builder
ARG PAIRDROP_RELEASE
ARG BUILD_DATE
ARG VERSION

RUN apk add --no-cache curl tar jq

WORKDIR /app

# Fetch PairDrop release (use PAIRDROP_RELEASE if provided, otherwise latest tag)
RUN if [ -z "$PAIRDROP_RELEASE" ]; then \
      PAIRDROP_RELEASE=$(curl -sL "https://api.github.com/repos/schlagmichdoch/PairDrop/tags" | jq -r '.[0].name'); \
    fi && \
    echo "Using release: $PAIRDROP_RELEASE" && \
    curl -L "https://github.com/schlagmichdoch/PairDrop/archive/refs/tags/${PAIRDROP_RELEASE}.tar.gz" -o /tmp/pairdrop.tar.gz && \
    tar xf /tmp/pairdrop.tar.gz --strip-components=1 -C /app && \
    rm /tmp/pairdrop.tar.gz

ENV NODE_ENV=production

# Install production deps
RUN npm ci --only=production

# If the project has a build script, run it (safe no-op if none)
RUN if grep -q "\"build\"" package.json 2>/dev/null; then npm run build; fi

# Create a small JS bootstrap to detect and require the correct entry file at runtime.
# This avoids hardcoding a single index path and prevents errors like "Cannot find module '/app/node'".
RUN cat > /app/run.js <<'RUNJS'\n#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const appDir = __dirname;
let main;
try {
  const pkg = JSON.parse(fs.readFileSync(path.join(appDir, 'package.json'), 'utf8'));
  if (pkg.main) main = pkg.main;
  else if (pkg.scripts && pkg.scripts.start) {
    // try to pull a "node <file>" from the start script
    const m = pkg.scripts.start.match(/node\\s+([^\\s]+)/);
    if (m) main = m[1];
  }
} catch (e) {
  // ignore parse errors
}
const candidates = [main, 'index.js', 'server.js', 'app.js'].filter(Boolean);
let found = null;
for (const c of candidates) {
  const p = path.join(appDir, c);
  if (fs.existsSync(p)) { found = p; break; }
}
if (!found) {
  console.error('No entry file found. Tried:', candidates);
  process.exit(1);
}
require(found);
RUNJS

# Keep files tidy
RUN rm -rf /root/.npm /root/.cache /tmp/*

############################################
# Final stage: small runtime (distroless)
############################################
FROM gcr.io/distroless/nodejs:20
WORKDIR /app

# Copy only the app & production deps from builder
COPY --from=builder /app /app

# Expose the same port as before
EXPOSE 3000

# Use node to run our bootstrap; it will require the proper entry file
CMD ["node", "/app/run.js"]
