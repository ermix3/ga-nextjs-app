# Stage 1: Build
FROM node:18-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Runtime
FROM node:18-alpine

WORKDIR /app
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public

ENV NEXT_PUBLIC_API_URL=https://api.yourdomain.com
ENV NODE_ENV=production

EXPOSE 3000
CMD ["npm", "run", "start"]
