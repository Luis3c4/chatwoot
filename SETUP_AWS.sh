
#!/bin/bash

# ============================================================================
# SETUP CHATWOOT EN AWS EC2 UBUNTU 22.04
# Copia/pega este script completo en la consola AWS EC2 Instance Connect
# ============================================================================

set -e  # Exit on error

echo "=========================================="
echo "CHATWOOT - Setup en AWS VPS Ubuntu 22.04"
echo "=========================================="

# Variables que debes cambiar
GITHUB_REPO="https://github.com/TU-USUARIO/TU-REPO.git"
DOMAIN="tu-dominio.com"
EMAIL="tu-email@dominio.com"
APPS_DIR="/home/ubuntu/apps"

echo "⚠️  IMPORTANTE: Antes de continuar, reemplaza en este script:"
echo "   - GITHUB_REPO: $GITHUB_REPO"
echo "   - DOMAIN: $DOMAIN"
echo "   - EMAIL: $EMAIL"
echo ""
read -p "¿Continuar? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    exit 1
fi

# ========== PASO 1: ACTUALIZAR SISTEMA ==========
echo ""
echo "[1/11] Actualizando sistema..."
sudo apt update && sudo apt -y upgrade
sudo apt install -y ca-certificates curl gnupg lsb-release ufw nginx git

# ========== PASO 2: INSTALAR DOCKER ==========
echo ""
echo "[2/11] Instalando Docker Engine..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ========== PASO 3: CONFIGURAR PERMISOS ==========
echo ""
echo "[3/11] Configurando permisos de Docker..."
sudo usermod -aG docker ubuntu
newgrp docker

echo "Docker versión: $(docker --version)"
echo "Docker Compose versión: $(docker compose version)"

# ========== PASO 4: CLONAR REPO ==========
echo ""
echo "[4/11] Clonando repositorio desde GitHub..."
mkdir -p "$APPS_DIR"
cd "$APPS_DIR"
git clone "$GITHUB_REPO" || echo "Repo ya existe"
cd rasa/chatwoot-local

echo "Ubicación: $(pwd)"

# ========== PASO 5: VERIFICAR .env ==========
echo ""
echo "[5/11] Verificando .env..."
if [ ! -f .env ]; then
    echo "❌ ERROR: No existe .env"
    exit 1
fi

echo "✅ .env encontrado"
echo ""
echo "IMPORTANTE: Revisa y edita .env después si es necesario:"
echo "  nano .env"
echo ""
echo "Valores críticos a revisar:"
grep "FRONTEND_URL\|FORCE_SSL\|SECRET_KEY_BASE" .env | head -3

# ========== PASO 6: INICIAR BASE DE DATOS ==========
echo ""
echo "[6/11] Descargando imágenes Docker..."
docker compose pull

echo ""
echo "[6/11] Iniciando PostgreSQL y Redis..."
docker compose up -d postgres redis
sleep 10

echo "Esperando a que PostgreSQL esté listo..."
docker compose exec postgres pg_isready -U postgres || sleep 10

# ========== PASO 7: PREPARAR BD ==========
echo ""
echo "[7/11] Preparando base de datos de Chatwoot..."
docker compose run --rm rails bundle exec rails db:chatwoot_prepare

# ========== PASO 8: INICIAR APP ==========
echo ""
echo "[8/11] Iniciando Rails y Sidekiq..."
docker compose up -d rails sidekiq
sleep 5

echo ""
docker compose ps

# ========== PASO 9: CONFIGURAR NGINX ==========
echo ""
echo "[9/11] Configurando Nginx..."
sudo tee /etc/nginx/sites-available/chatwoot > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Ssl on;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        proxy_read_timeout 90s;
        proxy_connect_timeout 90s;
        proxy_send_timeout 90s;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/chatwoot 2>/dev/null || echo "Link ya existe"
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

echo "✅ Nginx configurado"

# ========== PASO 10: FIREWALL ==========
echo ""
echo "[10/11] Configurando firewall..."
sudo ufw allow OpenSSH 2>/dev/null || true
sudo ufw allow 'Nginx Full' 2>/dev/null || true
sudo ufw --force enable

sudo ufw status

# ========== PASO 11: SSL CON CERTBOT ==========
echo ""
echo "[11/11] Instalando SSL con Let's Encrypt..."
echo ""
echo "⚠️  PREREQUISITO: Tu dominio ($DOMAIN) debe estar apuntando"
echo "    a la IP pública de este VPS antes de continuar"
echo ""
read -p "¿El DNS ya está configurado? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    sudo snap install core 2>/dev/null || true
    sudo snap refresh core 2>/dev/null || true
    sudo snap install --classic certbot 2>/dev/null || true
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true

    sudo certbot --nginx -d "$DOMAIN" --redirect -m "$EMAIL" --agree-tos -n

    echo ""
    echo "✅ SSL instalado correctamente"
    sleep 3
    curl -I "https://$DOMAIN" 2>/dev/null | head -1
else
    echo "⏭️  Salta SSL por ahora"
    echo "Ejecuta después:"
    echo "  sudo certbot --nginx -d $DOMAIN -m $EMAIL --agree-tos -n"
fi

# ========== RESUMEN ==========
echo ""
echo "=========================================="
echo "✅ SETUP COMPLETADO"
echo "=========================================="
echo ""
echo "Acceso a Chatwoot:"
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "  🔒 https://$DOMAIN"
else
    echo "  🔗 http://$DOMAIN (despues instalar SSL)"
fi
echo ""
echo "Comandos útiles:"
echo "  Ver estado:  docker compose ps"
echo "  Ver logs:    docker compose logs -f rails"
echo "  Detener:     docker compose down"
echo "  Reiniciar:   docker compose restart"
echo ""
echo "Ubicación: $APPS_DIR/rasa/chatwoot-local"
echo ""
