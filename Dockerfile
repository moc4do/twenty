# Etapa de build
FROM node:20-alpine AS build
WORKDIR /app
RUN apk add --no-cache python3 make g++ git
COPY package.json yarn.lock ./
RUN corepack enable && yarn set version stable && yarn install --frozen-lockfile
COPY . .
# Compile catálogos Lingui (do seu print)
RUN npx nx run twenty-front:lingui:extract && npx nx run twenty-front:lingui:compile
# (se houver alvo de lingui para o server, descomente estas duas linhas)
# RUN npx nx run twenty-server:lingui:extract && npx nx run twenty-server:lingui:compile
# Build da app (ajuste conforme o repo)
RUN yarn build

# Etapa final
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app ./
# inicie como a imagem oficial inicia (ajuste se necessário)
CMD ["yarn","start:prod"]
