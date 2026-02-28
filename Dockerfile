# -----------------------------------------------------------------------------
# XG Proyect v3 (PHP 7.4 + Apache) for Railway
# - Webroot: /var/www/html/public
# - Fix: AH00534 "More than one MPM loaded" (hard reset at build + runtime)
# - Bind: Apache listens on Railway $PORT AND also on 80 for local usage
# - Enable: rewrite/headers/expires
# - AllowOverride All for .htaccess
# - Permissions: storage/ + config/ + database/ writable for installer
# - Adds: vhost Directory block for /public (Require all granted + DirectoryIndex)
# -----------------------------------------------------------------------------

FROM php:7.4-apache

# --- System deps + PHP extensions ---
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      git unzip curl \
      libjpeg-dev libpng-dev libfreetype6-dev \
      libzip-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" gd mysqli opcache zip; \
    rm -rf /var/lib/apt/lists/*

# --- Apache modules + BUILD-TIME MPM cleanup (prefork only) ---
RUN set -eux; \
    a2enmod rewrite expires headers; \
    \
    # Disable ALL MPMs (ignore errors), then enable prefork
    a2dismod mpm_event  >/dev/null 2>&1 || true; \
    a2dismod mpm_worker >/dev/null 2>&1 || true; \
    a2dismod mpm_prefork >/dev/null 2>&1 || true; \
    \
    # Remove enabled symlinks (sometimes persists in layers)
    rm -f /etc/apache2/mods-enabled/mpm_event.load  /etc/apache2/mods-enabled/mpm_event.conf  || true; \
    rm -f /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf || true; \
    rm -f /etc/apache2/mods-enabled/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.conf || true; \
    \
    a2enmod mpm_prefork; \
    \
    # Global .htaccess allowance (we still add a vhost Directory block below)
    sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf; \
    \
    # Suppress ServerName warning
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername; \
    \
    # Sanity print
    ls -la /etc/apache2/mods-enabled/mpm_*.load || true

# --- Force DocumentRoot to /public + add explicit Directory block ---
RUN set -eux; \
    # DocumentRoot
    sed -ri 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/public#g' /etc/apache2/sites-available/000-default.conf; \
    \
    # Ensure DirectoryIndex has index.php
    if ! grep -qi '^DirectoryIndex' /etc/apache2/mods-available/dir.conf; then \
      echo 'DirectoryIndex index.php index.html' > /etc/apache2/mods-available/dir.conf; \
    else \
      sed -ri 's/^DirectoryIndex.*/DirectoryIndex index.php index.html/g' /etc/apache2/mods-available/dir.conf; \
    fi; \
    a2enmod dir >/dev/null 2>&1 || true; \
    \
    # Add/replace a safe <Directory /var/www/html/public> block inside vhost
    # (This is the most common missing piece when /public is used as webroot)
    if grep -q "<Directory /var/www/html/public>" /etc/apache2/sites-available/000-default.conf; then \
      true; \
    else \
      printf '\n<Directory /var/www/html/public>\n  Options Indexes FollowSymLinks\n  AllowOverride All\n  Require all granted\n</Directory>\n' >> /etc/apache2/sites-available/000-default.conf; \
    fi

# --- Composer (optional) ---
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# --- App copy ---
WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html

# Install deps (don’t fail build if vendor is optional)
RUN set -eux; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || true; \
    \
    mkdir -p storage/logs storage/backups; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug+rwX storage config database || true

# --- Railway start script: runtime hard reset + PORT bind + debug + curl self-test ---
RUN set -eux; \
    cat > /usr/local/bin/railway-apache-start <<'SH'
#!/usr/bin/env sh
set -e

PORT="${PORT:-80}"

echo "== Runtime MPM hard reset =="

# Hard-disable all MPMs and remove symlinks
a2dismod mpm_event   >/dev/null 2>&1 || true
a2dismod mpm_worker  >/dev/null 2>&1 || true
a2dismod mpm_prefork >/dev/null 2>&1 || true

rm -f /etc/apache2/mods-enabled/mpm_event.load  /etc/apache2/mods-enabled/mpm_event.conf  || true
rm -f /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf || true
rm -f /etc/apache2/mods-enabled/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.conf || true

# Enable ONLY prefork
a2enmod mpm_prefork >/dev/null 2>&1 || true

echo "== Enabled MPM modules =="
ls -la /etc/apache2/mods-enabled/mpm_*.load || true

echo "== Port configuration =="
# Write ports.conf deterministically: always listen on 80 (local), plus $PORT (Railway)
# Avoid duplicate when PORT=80
{
  echo "Listen 80"
  if [ "$PORT" != "80" ]; then
    echo "Listen $PORT"
  fi
} > /etc/apache2/ports.conf

# Ensure vhost bound to $PORT (Railway routing uses $PORT)
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

# Ensure webroot is /public (safety)
sed -ri 's#DocumentRoot\s+.*#DocumentRoot /var/www/html/public#g' /etc/apache2/sites-available/000-default.conf

# Re-apply AllowOverride (safety)
sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf

# Permissions (installer writes stuff)
chown -R www-data:www-data /var/www/html || true
chmod -R ug+rwX /var/www/html/storage /var/www/html/config /var/www/html/database || true

echo "== Effective config bits =="
grep -n "^Listen" /etc/apache2/ports.conf || true
grep -n "<VirtualHost" /etc/apache2/sites-available/000-default.conf || true
grep -n "DocumentRoot" /etc/apache2/sites-available/000-default.conf || true

echo "== Apache configtest =="
apache2ctl -t || true

echo "== Quick self-test (curl) =="
# Start apache in background, curl it, then bring it foreground
apache2ctl start
sleep 1
curl -sv "http://127.0.0.1:${PORT}/" -o /dev/null || true
curl -sv "http://127.0.0.1:${PORT}/install/" -o /dev/null || true
apache2ctl stop

echo "== Starting Apache foreground =="
exec apache2-foreground
SH
    chmod +x /usr/local/bin/railway-apache-start

EXPOSE 80 8080
CMD ["railway-apache-start"]
