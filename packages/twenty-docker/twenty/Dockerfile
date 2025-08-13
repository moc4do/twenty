# Base image for common dependencies
FROM node:24-alpine AS common-deps

WORKDIR /app

# CI sem watchers e com Yarn não-imutável (opção B)
ENV CI=1 \
    NX_DAEMON=false \
    YARN_ENABLE_IMMUTABLE_INSTALLS=false

# taskset (util-linux) e nproc (coreutils)
RUN apk add --no-cache util-linux coreutils

# Percentual de CPU a usar nos passos pesados (padrão 80%)
ARG CPU_PERCENT=80

# Copy only the necessary files for dependency resolution
COPY ./package.json ./yarn.lock ./.yarnrc.yml ./tsconfig.base.json ./nx.json /app/
COPY ./.yarn/releases /app/.yarn/releases
COPY ./.yarn/patches /app/.yarn/patches

COPY ./.prettierrc /app/
COPY ./packages/twenty-emails/package.json /app/packages/twenty-emails/
COPY ./packages/twenty-server/package.json /app/packages/twenty-server/
COPY ./packages/twenty-server/patches /app/packages/twenty-server/patches
COPY ./packages/twenty-ui/package.json /app/packages/twenty-ui/
COPY ./packages/twenty-shared/package.json /app/packages/twenty-shared/
COPY ./packages/twenty-front/package.json /app/packages/twenty-front/

# Install all dependencies (sem modo imutável) e reset do Nx
# Usa floor: CPUs = floor(nproc * CPU_PERCENT/100), garantindo [1, nproc-1]
RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> yarn install com CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    taskset -c 0-$END /bin/sh -lc 'corepack enable && yarn install && yarn cache clean && npx nx reset'


# Build the back
FROM common-deps AS twenty-server-build

ARG CPU_PERCENT=80

# Copy sourcecode after installing dependences to accelerate subsequents builds
COPY ./packages/twenty-emails /app/packages/twenty-emails
COPY ./packages/twenty-shared /app/packages/twenty-shared
COPY ./packages/twenty-server /app/packages/twenty-server

# Build server em modo produção, limitado a ~80% dos CPUs (floor)
RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> nx build (server) com CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    taskset -c 0-$END npx nx run twenty-server:build --configuration=production --skip-nx-cache

RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> yarn workspaces focus com CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    taskset -c 0-$END yarn workspaces focus --production twenty-emails twenty-shared twenty-server


# Build the front
FROM common-deps AS twenty-front-build

ARG REACT_APP_SERVER_BASE_URL
ARG CPU_PERCENT=80

COPY ./packages/twenty-front /app/packages/twenty-front
COPY ./packages/twenty-ui /app/packages/twenty-ui
COPY ./packages/twenty-shared /app/packages/twenty-shared

# Build front em modo produção, limitado a ~80% dos CPUs (floor)
RUN TOTAL=$(nproc); \
    CPU_USE=$(( TOTAL * ${CPU_PERCENT} / 100 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    [ $CPU_USE -ge $TOTAL ] && CPU_USE=$(( TOTAL - 1 )); \
    [ $CPU_USE -lt 1 ] && CPU_USE=1; \
    END=$((CPU_USE-1)); \
    echo ">> nx build (front) com CPUs 0-$END de $TOTAL"; \
    export UV_THREADPOOL_SIZE=$CPU_USE GOMAXPROCS=$CPU_USE; \
    taskset -c 0-$END npx nx build twenty-front --configuration=production --skip-nx-cache


# Final stage: Run the application
FROM node:24-alpine AS twenty

ENV NODE_ENV=production

# Used to run healthcheck in docker
RUN apk add --no-cache curl jq

RUN npm install -g tsx

RUN apk add --no-cache postgresql-client

COPY ./packages/twenty-docker/twenty/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
WORKDIR /app/packages/twenty-server

ARG REACT_APP_SERVER_BASE_URL
ENV REACT_APP_SERVER_BASE_URL=$REACT_APP_SERVER_BASE_URL

ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

# Copy built applications from previous stages
COPY --chown=1000 --from=twenty-server-build /app /app
COPY --chown=1000 --from=twenty-server-build /app/packages/twenty-server /app/packages/twenty-server
COPY --chown=1000 --from=twenty-front-build /app/packages/twenty-front/build /app/packages/twenty-server/dist/front

# Set metadata and labels
LABEL org.opencontainers.image.source=https://github.com/twentyhq/twenty
LABEL org.opencontainers.image.description="This image provides a consistent e reproducible environment for the backend and frontend."

RUN mkdir -p /app/.local-storage /app/packages/twenty-server/.local-storage && \
    chown -R 1000:1000 /app

# Use non root user with uid 1000
USER 1000

CMD ["node", "dist/src/main"]
ENTRYPOINT ["/app/entrypoint.sh"]
