# Chatwoot Local Setup Commands

## Requisitos previos (Local)

- Repositorio publicado en GitHub
- Acceso a consola AWS EC2 Instance Connect o Systems Manager Session Manager

## Requisitos previos (VPS Ubuntu 22.04)

- Security Group abierto: puertos 22, 80, 443
- IP pública del VPS disponible (dominio opcional por ahora)

---

## SETUP INICIAL - Ejecutar en consola AWS del VPS

### 1. Actualizar sistema e instalar dependencias

```bash
sudo apt update && sudo apt -y upgrade
sudo apt install -y ca-certificates curl gnupg lsb-release ufw nginx git
```

### 2. Instalar Docker Engine + Docker Compose plugin

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 3. Configurar permisos Docker

```bash
sudo usermod -aG docker ubuntu
newgrp docker
docker --version
docker compose version
```

### 4. Clonar repositorio desde GitHub

```bash
mkdir -p /home/ubuntu/apps
cd /home/ubuntu/apps
git clone https://github.com/TU-USUARIO/TU-REPO.git
cd rasa/chatwoot-local
```

### 5. Revisar y editar .env

```bash
cat .env
nano .env
```

Modificar al menos:
- `FRONTEND_URL=http://52.14.138.51`
- `FORCE_SSL=false`

### 6. Levantar base de datos

```bash
docker compose pull
docker compose up -d postgres redis
sleep 10
```

### 7. Preparar base de datos de Chatwoot

```bash
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
```

### 8. Levantar aplicación


cd /home/ubuntu/apps/rasa/chatwoot-local

docker compose down -v
docker compose up -d postgres redis
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
docker compose up -d rails sidekiq
docker compose ps


```bash
docker compose up -d rails sidekiq
docker compose ps
```

---

## CONFIGURAR NGINX COMO REVERSE PROXY

### 9. Crear configuración de Nginx

```bash
sudo tee /etc/nginx/sites-available/chatwoot > /dev/null <<'EOF'
server {
    listen 80;
  server_name 52.14.138.51;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Ssl on;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
        proxy_send_timeout 90s;
    }
}
EOF
```

### 10. Activar sitio en Nginx

```bash
sudo ln -s /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/chatwoot
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

---

## CONFIGURAR FIREWALL

### 11. Permitir tráfico SSH, HTTP, HTTPS

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
sudo ufw status
```

---

## INSTALAR SSL CON CERTBOT (Let's Encrypt)

**Prerequisito:** Tener dominio propio con DNS A apuntando a la IP pública del VPS.

Si solo usas IP pública por ahora, omite esta sección.

### 12. Instalar y configurar Certbot

```bash
sudo snap install core
sudo snap refresh core
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot

sudo certbot --nginx -d tu-dominio.com --redirect -m tu-email@dominio.com --agree-tos -n
sudo systemctl status snap.certbot.renew.timer
```

### 13. Verificar SSL instalado

```bash
curl -I https://tu-dominio.com
```

---

## COMANDOS DE OPERACIÓN DIARIA

### Levantar los contenedores

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose up -d
```

### Detener los contenedores

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose down
```

### Reiniciar los contenedores

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose restart
```

### Ver logs de la aplicación Rails

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose logs -f rails
```

### Ver logs de Sidekiq (background jobs)

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose logs -f sidekiq
```

### Ver estado de los contenedores

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose ps
```

### Actualizar a última versión

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose pull
docker compose down
docker compose up -d rails sidekiq
```

---

## ACCESO A CHATWOOT

### En producción (AWS)

```
http://52.14.138.51
```

### Bases de datos en VPS

- PostgreSQL: `127.0.0.1:5432` (user: postgres)
- Redis: `127.0.0.1:6379`

---

## TROUBLESHOOTING

### Ver todas las bases de datos

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose exec postgres psql -U postgres -l
```

### Acceder a la consola PostgreSQL

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose exec postgres psql -U postgres chatwoot
```

### Ver consumo de recursos

```bash
docker stats
```

### Limpiar volúmenes (cuidado, borra datos)

```bash
cd /home/ubuntu/apps/rasa/chatwoot-local
docker compose down -v
```

---

## NOTAS IMPORTANTES

- El archivo `.env` debe existir antes de `docker compose up`
- Si usas solo IP, deja `FRONTEND_URL` en `http://52.14.138.51` y `FORCE_SSL=false`
- SSL con Certbot requiere dominio (no emite certificado para IP pública)
- Cuando tengas dominio, cambia `FRONTEND_URL` a `https://tu-dominio.com` y luego activa Certbot
- Cambiar `tu-email@dominio.com` por tu email en Certbot
- Cambiar `TU-USUARIO/TU-REPO` por tu repo de GitHub
- Los puertos 3000 (Rails), 5432 (DB), 6379 (Redis) solo están en localhost
- Acceso público solo a través de Nginx en puertos 80/443
