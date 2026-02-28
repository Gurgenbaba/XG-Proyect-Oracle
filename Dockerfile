# -----------------------------------------------------------------------------
# XG Proyect v3 (PHP 7.4 + Apache) for Railway
# - Webroot: /var/www/html/public
# - Fix: AH00534 "More than one MPM loaded"
# - Bind Apache to Railway $PORT
# - Alias /public so /public/css/... works
# -----------------------------------------------------------------------------

FROM php:7.4-apache

# ----------------------------
# System deps + PHP extensions
# ----------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      git unzip \
      libjpeg-dev libpng-dev libfreetype6-dev \
      libzip-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
      gd mysqli opcache zip \
    ; \
    rm -rf /var/lib/apt/lists/*

# ----------------------------
# Apache modules + build-time MPM cleanup
# ----------------------------
RUN set -eux; \
    a2enmod rewrite expires headers; \
    \
    a2dismod mpm_event  >/dev/null 2>&1 || true; \
    a2dismod mpm_worker >/dev/null 2>&1 || true; \
    a2dismod mpm_prefork >/dev/null 2>&1 || true; \
    \
    rm -f /etc/apache2/mods-enabled/mpm_*.load  || true; \
    rm -f /etc/apache2/mods-enabled/mpm_*.conf  || true; \
    \
    a2enmod mpm_prefork; \
    \
    sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf; \
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername

# ----------------------------
# Force DocumentRoot -> /public
# ----------------------------
RUN set -eux; \
    sed -ri 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/public#g' \
    /etc/apache2/sites-available/000-default.conf

# ----------------------------
# Composer
# ----------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html

RUN set -eux; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || true; \
    mkdir -p storage/logs storage/backups; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug+rwX storage config database || true

# ----------------------------
# Runtime start script
# ----------------------------
RUN set -eux; \
cat > /usr/local/bin/railway-apache-start <<'EOF'
#!/usr/bin/env sh
set -e

PORT="${PORT:-80}"

echo "== Runtime MPM hard reset =="

a2dismod mpm_event  >/dev/null 2>&1 || true
a2dismod mpm_worker >/dev/null 2>&1 || true
a2dismod mpm_prefork >/dev/null 2>&1 || true

rm -f /etc/apache2/mods-enabled/mpm_*.load || true
rm -f /etc/apache2/mods-enabled/mpm_*.conf || true

a2enmod mpm_prefork >/dev/null 2>&1 || true

echo "== Enabled MPM modules =="
ls -la /etc/apache2/mods-enabled/mpm_*.load || true

echo "== Port configuration =="
sed -ri "s/^Listen\s+[0-9]+/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT}>/" \
    /etc/apache2/sites-available/000-default.conf

# Ensure webroot is /public
sed -ri 's#DocumentRoot\s+.*#DocumentRoot /var/www/html/public#g' \
    /etc/apache2/sites-available/000-default.conf

# IMPORTANT: allow /public URLs
if ! grep -q "^Alias /public " /etc/apache2/sites-available/000-default.conf; then
cat >> /etc/apache2/sites-available/000-default.conf <<'CONF'

Alias /public /var/www/html/public

<Directory /var/www/html/public>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

CONF
fi

sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf

chown -R www-data:www-data /var/www/html || true
chmod -R ug+rwX /var/www/html/storage /var/www/html/config /var/www/html/database || true

grep -n "^Listen" /etc/apache2/ports.conf || true
grep -n "<VirtualHost" /etc/apache2/sites-available/000-default.conf || true
grep -n "DocumentRoot" /etc/apache2/sites-available/000-default.conf || true
grep -n "^Alias /public" /etc/apache2/sites-available/000-default.conf || true

exec apache2-foreground
EOF

RUN chmod +x /usr/local/bin/railway-apache-start

EXPOSE 80 8080

CMD ["railway-apache-start"]
