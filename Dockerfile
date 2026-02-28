# -----------------------------------------------------------------------------
# XG Proyect v3 (PHP 7.4 + Apache) for Railway
# - Webroot: /var/www/html/public
# - Fix: AH00534 "More than one MPM loaded" (hard reset at build + runtime)
# - Bind: Apache listens on Railway $PORT (default 80 locally)
# - Enable: rewrite/headers/expires
# - AllowOverride All for .htaccess
# - Permissions: storage/ + config/ writable for installer
# -----------------------------------------------------------------------------

FROM php:7.4-apache

# --- System deps + PHP extensions commonly needed by XGProyect ---
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
      mbstring \
    ; \
    rm -rf /var/lib/apt/lists/*

# --- Apache modules + BUILD-TIME MPM cleanup (prefork only) ---
RUN set -eux; \
    a2enmod rewrite expires headers; \
    \
    # disable all MPMs (ignore errors), then enable prefork
    a2dismod mpm_event  || true; \
    a2dismod mpm_worker || true; \
    a2dismod mpm_prefork || true; \
    \
    # remove enabled symlinks (sometimes persists in weird layers)
    rm -f /etc/apache2/mods-enabled/mpm_event.load  /etc/apache2/mods-enabled/mpm_event.conf  || true; \
    rm -f /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf || true; \
    rm -f /etc/apache2/mods-enabled/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.conf || true; \
    \
    a2enmod mpm_prefork; \
    \
    # allow .htaccess
    sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf; \
    \
    # suppress ServerName warning
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername

# --- Force DocumentRoot to /public (XGProyect webroot) ---
RUN set -eux; \
    sed -ri 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/public#g' /etc/apache2/sites-available/000-default.conf; \
    # also adjust the <Directory> block if present
    if grep -q "<Directory /var/www/>" /etc/apache2/apache2.conf; then true; fi

# --- Composer (optional; XG uses it) ---
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html

# Install deps (don’t fail build if vendor is optional in this repo)
RUN set -eux; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || true; \
    \
    # writable dirs for install + runtime
    mkdir -p storage/logs storage/backups; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug+rwX storage config database || true

# --- Railway start script: runtime hard reset + PORT bind + vhost + sanity logs ---
RUN set -eux; \
    cat > /usr/local/bin/railway-apache-start <<'SH'
#!/usr/bin/env sh
set -e

PORT="${PORT:-80}"

echo "== Runtime MPM hard reset =="

# Hard-disable all MPMs and remove symlinks
a2dismod mpm_event  >/dev/null 2>&1 || true
a2dismod mpm_worker >/dev/null 2>&1 || true
a2dismod mpm_prefork >/dev/null 2>&1 || true

rm -f /etc/apache2/mods-enabled/mpm_event.load  /etc/apache2/mods-enabled/mpm_event.conf  || true
rm -f /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf || true
rm -f /etc/apache2/mods-enabled/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.conf || true

# Enable ONLY prefork
a2enmod mpm_prefork >/dev/null 2>&1 || true

echo "== Enabled MPM modules =="
ls -la /etc/apache2/mods-enabled/mpm_*.load || true

# Bind apache to $PORT (Railway sets PORT, locally default 80)
echo "== Port configuration =="
sed -ri "s/^Listen\s+[0-9]+/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

# Ensure webroot is /public
sed -ri 's#DocumentRoot\s+.*#DocumentRoot /var/www/html/public#g' /etc/apache2/sites-available/000-default.conf

# Re-apply AllowOverride (safety)
sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf

# Permissions (installer writes stuff)
chown -R www-data:www-data /var/www/html || true
chmod -R ug+rwX /var/www/html/storage /var/www/html/config /var/www/html/database || true

# Print effective config bits
grep -n "^Listen" /etc/apache2/ports.conf || true
grep -n "<VirtualHost" /etc/apache2/sites-available/000-default.conf || true
grep -n "DocumentRoot" /etc/apache2/sites-available/000-default.conf || true

exec apache2-foreground
SH
    chmod +x /usr/local/bin/railway-apache-start

# Expose for local + Railway (Railway will still route to $PORT)
EXPOSE 80 8080

CMD ["railway-apache-start"]
