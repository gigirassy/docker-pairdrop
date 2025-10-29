# syntax=docker/dockerfile:1
############################################
# Builder: fetch repo, install deps, build
############################################
FROM node:20-alpine AS builder
ARG PAIRDROP_RELEASE
ARG BUILD_DATE
ARG VERSION

# Install tools for fetching tags/releases
RUN apk add --no-cache curl tar jq bash

WORKDIR /app

# Fetch PairDrop release (if PAIRDROP_RELEASE is empty, pick latest tag)
# Note: this runs at build-time; if you pass PAIRDROP_RELEASE as a build-arg it will use that.
RUN if [ -z "$PAIRDROP_RELEASE" ]; then \
      PAIRDROP_RELEASE=$(curl -sL "https://api.github.com/repos/schlagmichdoch/PairDrop/tags" | jq -r '.[0].name'); \
    fi && \
    echo "Using release: $PAIRDROP_RELEASE" && \
    curl -L "https://github.com/schlagmichdoch/PairDrop/archive/refs/tags/${PAIRDROP_RELEASE}.tar.gz" -o /tmp/pairdrop.tar.gz && \
    tar xf /tmp/pairdrop.tar.gz --strip-components=1 -C /app && \
    rm /tmp/pairdrop.tar.gz

# Install production dependencies only
ENV NODE_ENV=production
# If the repo contains package-lock.json or npm-shrinkwrap, npm ci will be deterministic
RUN npm ci --only=production

# Optional: run a build if package.json has a build script
# This will run only if "build" appears in package.json scripts
RUN if grep -q "\"build\"" package.json 2>/dev/null; then npm run build; fi

# Make sure only needed files are in /app (clean caches)
RUN rm -rf /root/.npm /root/.cache /tmp/*

############################################
# Final: distroless node runtime (minimal)
############################################
FROM gcr.io/distroless/nodejs:20

# create app dir in final image
WORKDIR /app

# Copy production node_modules and app files from builder
COPY --from=builder /app /app

# The distroless image runs as non-root; expose port same as before
EXPOSE 3000

# Provide an opinionated default command:
# - prefer start script if present, otherwise fallback to main or index.js
# Adjust the final JSON entry below if your app's entry is different.
CMD ["node", "/app/index.js"]
