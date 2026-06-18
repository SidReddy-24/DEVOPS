# Stage 1: Build dependencies
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install

# Copy source code and build
COPY . .

# Stage 2: Final runtime container
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev

COPY --from=builder /app ./

EXPOSE 3000
CMD ["npm", "start"]