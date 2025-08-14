# syntax=docker/dockerfile:1.7

############################################
# 1) Dependências comuns (build)
############################################
FROM node:24-bookworm-slim AS common-deps

WORKDIR /app

# Opção B: permitir que o Yarn atualize resoluções durante o build
# e evitar daemon/watchers do Nx
ENV CI=1 \
    NX_DAEMON=false \
    YARN_ENABLE_IMMUTABLE_INSTALLS=false

# Ferramentas para build estável (node-gyp etc) + taskset/nproc
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl jq git \
    build-essential python3 \
    util-linux coreutils \
  && rm -rf /var/lib/apt/lists/*

# Percentual de CPUs a usar nos passos pesados (padrão 80)
ARG CPU_PERCENT=80

# Copiamos apenas o necessário para resolver dependências
COPY ./package.json ./yarn.lock ./.yarnrc.yml ./tsconfig.base.json ./nx.json /app/
COPY ./.yarn/releases /app/.yarn/releases
COPY ./.yarn/patches  /app/.yarn/patches
COPY ./.prettierrc    /app/
COPY ./packages/twenty-emails/package.json /app/packages/twenty-emails/
COPY ./packages/twenty-server/package.json /app/packages/twenty-server/
COPY ./packages/twenty-server/patches      /app/packages/twenty-server/patches
COPY ./packages/twenty-ui/package.json     /app/packages/twenty-ui/
COPY ./packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY ./packages/twenty-front/package.json  /app/packages/twenty-front/

# Instala dependências com caches do BuildKit e limita CPU (~80%, arredondando para baixo)
RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> yarn install usando CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    corepack enable && \
    --mount=type=cache,target=/app/.yarn/cache \
    --mount=type=cache,target=/app/.yarn/unplugged \
    taskset -c 0-$END /bin/sh -lc "yarn install && yarn cache clean && npx nx reset"


############################################
# 2) Build do backend (Nest)
############################################
FROM common-deps AS twenty-server-build

ARG CPU_PERCENT=80

# Código necessário para build do back
COPY ./packages/twenty-emails  /app/packages/twenty-emails
COPY ./packages/twenty-shared  /app/packages/twenty-shared
COPY ./packages/twenty-server  /app/packages/twenty-server

# Build do server com cache e limite de CPU
RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> nx build (server) CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    --mount=type=cache,target=/app/.nx/cache \
    --mount=type=cache,target=/app/node_modules/.cache \
    taskset -c 0-$END npx nx run twenty-server:build --configuration=production --skip-nx-cache

# Foca dependências de produção dos workspaces usados no runtime do server
RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> yarn workspaces focus (prod) CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    --mount=type=cache,target=/app/.yarn/cache \
    --mount=type=cache,target=/app/.yarn/unplugged \
    taskset -c 0-$END yarn workspaces focus --production twenty-emails twenty-shared twenty-server


############################################
# 3) Build do frontend (Vite)
############################################
FROM common-deps AS twenty-front-build

ARG REACT_APP_SERVER_BASE_URL
ARG CPU_PERCENT=80

COPY ./packages/twenty-front   /app/packages/twenty-front
COPY ./packages/twenty-ui      /app/packages/twenty-ui
COPY ./packages/twenty-shared  /app/packages/twenty-shared

# Build do front com cache e limite de CPU
RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> nx build (front) CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    --mount=type=cache,target=/app/.nx/cache \
    --mount=type=cache,target=/app/node_modules/.cache \
    taskset -c 0-$END npx nx build twenty-front --configuration=production --skip-nx-cache


############################################
# 4) Estágio final (runtime)
############################################
FROM node:24-bookworm-slim AS twenty

ENV NODE_ENV=production

# Utilitários de runtime (curl/jq/psql). tsx é opcional, mantive como no seu original.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl jq postgresql-client \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g tsx

# Entrypoint do seu projeto
COPY ./packages/twenty-docker/twenty/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

WORKDIR /app/packages/twenty-server

# Variáveis de build/exec
ARG REACT_APP_SERVER_BASE_URL
ENV REACT_APP_SERVER_BASE_URL=$REACT_APP_SERVER_BASE_URL
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

# === Cópia ENXUTA de artefatos para runtime ===
# node_modules (focados em produção)
COPY --from=twenty-server-build /app/node_modules /app/node_modules
# pacotes base e metadados mínimos
COPY --from=twenty-server-build /app/package.json /app/package.json
COPY --from=twenty-server-build /app/packages/twenty-server/package.json /app/packages/twenty-server/package.json
# dist do backend
COPY --from=twenty-server-build /app/packages/twenty-server/dist /app/packages/twenty-server/dist
# build do front para servir pelo backend
COPY --from=twenty-front-build /app/packages/twenty-front/build /app/packages/twenty-server/dist/front

# Labels
LABEL org.opencontainers.image.source="https://github.com/twentyhq/twenty" \
      org.opencontainers.image.description="Backend + Frontend prontos para produção, com build cacheado e controle de CPU."

# Permissões e diretórios locais
RUN mkdir -p /app/.local-storage /app/packages/twenty-server/.local-storage && \
    chown -R 1000:1000 /app

# Usuário não-root
USER 1000

# Start
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["node", "dist/src/main"]
