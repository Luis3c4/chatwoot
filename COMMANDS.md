# Chatwoot Local Setup Commands

## Requisitos previos

- Docker Desktop con integración WSL2 activada
  - Docker Desktop → Settings → Resources → WSL Integration → activar distro → Apply & Restart
- ngrok instalado

---

## Levantar los contenedores

```bash
cd /home/luis/Project/rasa/chatwoot-local
docker compose up -d
```

## Detener los contenedores

```bash
docker compose down
```

## Ver logs

```bash
docker compose logs -f
```

## Ver estado de los contenedores

```bash
docker compose ps
```

---

## Acceder a Chatwoot en local

```
http://localhost:3000
```

---

## Exponer Chatwoot con ngrok

```bash
ngrok http 3000
```

ngrok generará una URL pública tipo `https://xxxx.ngrok-free.app` para usar en webhooks.

---

## Notas

- El archivo `.env` debe existir en esta carpeta antes de levantar los contenedores.
- PostgreSQL corre en `localhost:5432`
- Redis corre en `localhost:6379`
