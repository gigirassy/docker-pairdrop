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
    curl -sL "https://github.com/schlagmichdoch/PairDrop/archive/refs/tags/${PAIRDROP_RELEASE}.tar.gz" -o /tmp/pairdrop.tar.gz && \
    tar xf /tmp/pairdrop.tar.gz --strip-components=1 -C /app && rm /tmp/pairdrop.tar.gz

ENV NODE_ENV=production

# Install production deps
RUN npm ci --only=production

# If project has a build script, run it
RUN if grep -q "\"build\"" package.json 2>/dev/null; then npm run build; fi

# Strict bootstrap: ignore absolute paths or paths resolving outside /app
RUN cat > /app/run.js <<'RUNJS'
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const appDir = __dirname;

function isInsideApp(resolved) {
  const appResolved = path.resolve(appDir) + path.sep;
  const r = path.resolve(resolved);
  return r === path.resolve(appDir) || r.startsWith(appResolved);
}

let candidateFile = null;
try {
  const pkgPath = path.join(appDir, 'package.json');
  if (fs.existsSync(pkgPath)) {
    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    if (pkg.main) {
      const mainResolved = path.resolve(appDir, pkg.main);
      if (isInsideApp(mainResolved) && fs.existsSync(mainResolved)) candidateFile = mainResolved;
    }
    // Only consider scripts.start if we didn't already find main
    if (!candidateFile && pkg.scripts && pkg.scripts.start) {
      const m = pkg.scripts.start.match(/node\s+([^\s]+)/);
      if (m) {
        const cmdPath = m[1];
        // Ignore absolute paths (like /app/node) or external paths
        if (!path.isAbsolute(cmdPath)) {
          const resolved = path.resolve(appDir, cmdPath);
          if (isInsideApp(resolved) && fs.existsSync(resolved)) candidateFile = resolved;
        }
      }
    }
  }
} catch (e) {
  // ignore parse errors
}

const fallbacks = ['index.js', 'server.js', 'app.js'].map(f => path.join(appDir, f));
let found = candidateFile || fallbacks.find(p => fs.existsSync(p)) || null;

if (!found) {
  console.error('No entry file found. Tried candidate from package.json and:', [candidateFile, ...fallbacks]);
  process.exit(1);
}

require(found);
RUNJS

# remove build caches
RUN rm -rf /root/.npm /root/.cache /tmp/*

############################################
# Final stage: small runtime (distroless)
############################################
FROM gcr.io/distroless/nodejs20-debian12:latest
WORKDIR /app
COPY --from=builder /app /app
EXPOSE 3000
CMD ["node", "/app/run.js"]
