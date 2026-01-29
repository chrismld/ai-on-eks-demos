FROM node:18-alpine as builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/out ./public
EXPOSE 3000
CMD ["npx", "http-server", "public", "-p", "3000", "-g"]
