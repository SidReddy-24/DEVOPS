# --- Stage 1: Build & Test Environment ---
FROM node:20-alpine AS builder
WORKDIR /app

# Copy dependency manifests
COPY package*.json ./
RUN npm ci

# Copy source code and build application
COPY . .
RUN npm run build

# --- Stage 2: Production-Ready Minimal Runtime ---
FROM node:20-alpine AS runner
WORKDIR /app

# Set production environment flags
ENV NODE_ENV=production

# Install ONLY production dependencies to save memory
COPY package*.json ./
RUN npm ci --only=production

# Copy built compilation from Stage 1
COPY --from=builder /app/dist ./dist

# CRITICAL SECURITY STEP FOR HEALTHCARE: Run as non-root user
USER node

EXPOSE 3000
CMD ["node", "dist/main.js"]