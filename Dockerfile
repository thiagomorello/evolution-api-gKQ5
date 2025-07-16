# === STAGE 1: BUILD ===
FROM node:20-alpine AS builder

# Instala dependências do sistema
RUN apk add --no-cache \
    bash \
    curl \
    dos2unix \
    ffmpeg \
    git \
    openssl

WORKDIR /app

# Copia só o package.json e package-lock.json pra aproveitar cache
COPY package.json package-lock.json ./

# Usa npm ci pra garantir install determinístico
RUN npm ci

# Copia resto do código
COPY tsconfig.json tsup.config.ts runWithProvider.js ./
COPY src ./src
COPY public ./public
COPY prisma ./prisma
COPY manager ./manager
COPY .env.example .env
COPY Docker/scripts ./Docker/scripts

# Ajusta permissão e formata scripts
RUN chmod +x Docker/scripts/*.sh && \
    dos2unix Docker/scripts/*.sh

# Gera DB (se precisar rodar migração ou seed)
RUN Docker/scripts/generate_database.sh

# Build final
RUN npm run build

# === STAGE 2: RUNTIME ===
FROM node:20-alpine AS runtime

# Instala só runtime deps
RUN apk add --no-cache \
    bash \
    ffmpeg \
    tzdata \
    openssl

# Define timezone
ENV TZ=America/Sao_Paulo

WORKDIR /app

# Copia artefatos da build
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/package-lock.json ./package-lock.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/manager ./manager
COPY --from=builder /app/public ./public
COPY --from=builder /app/.env .env
COPY --from=builder /app/Docker/scripts ./Docker/scripts
COPY --from=builder /app/runWithProvider.js ./runWithProvider.js
COPY --from=builder /app/tsup.config.ts ./tsup.config.ts

# Marca que tá rodando no Docker
ENV DOCKER_ENV=true

EXPOSE 8080

# No entrypoint, primeiro deploy DB e depois sobe a API
ENTRYPOINT ["bash", "-lc", "Docker/scripts/deploy_database.sh && npm run start:prod"]
