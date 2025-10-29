# -------- builder (alpine, small) --------
FROM node:20-alpine AS builder
WORKDIR /usr/src/app

# install git for cloning
RUN apk add --no-cache git

# clone the PairDrop repo
RUN git clone --depth 1 https://github.com/schlagmichdoch/PairDrop.git .

# install production dependencies
RUN if [ -f package-lock.json ]; then \
      npm ci --omit=dev --no-audit --no-fund; \
    else \
      npm install --omit=dev --no-audit --no-fund; \
    fi \
 && npm cache clean --force

# optional build step (TypeScript, bundler, etc.)
RUN npm run build --if-present

# remove unnecessary files
RUN rm -rf .git tests docs .github *.md || true

# fix permissions so non-root user in distroless can read
RUN chmod -R a+rX /usr/src/app


# -------- runtime (distroless) --------
FROM gcr.io/distroless/nodejs20-debian12:nonroot
WORKDIR /app

# copy app + node_modules from builder (already correct permissions)
COPY --from=builder /usr/src/app /app

ENV NODE_ENV=production
EXPOSE 3000

# ENTRYPOINT — adjust to PairDrop main file
ENTRYPOINT ["server/index.js"]

