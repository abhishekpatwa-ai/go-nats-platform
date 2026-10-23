# ---- Stage 1: compile TypeScript to JavaScript (Node only at build time) ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json tsconfig.json ./
RUN npm install
COPY src ./src
RUN npm run build

# ---- Stage 2: serve static files with nginx (non-root, port 8080) ----
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public/ /usr/share/nginx/html/
COPY --from=build /app/dist/ /usr/share/nginx/html/
EXPOSE 8080
