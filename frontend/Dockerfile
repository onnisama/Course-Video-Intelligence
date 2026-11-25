FROM node:24-bookworm-slim AS build

WORKDIR /app/frontend
COPY package.json pnpm-lock.yaml ./
RUN npm install --global pnpm@11.1.1 && pnpm install --frozen-lockfile

COPY index.html tsconfig.json vite.config.ts ./
COPY src ./src
RUN pnpm run build

FROM nginx:1.30.8-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/frontend/dist /usr/share/nginx/html
