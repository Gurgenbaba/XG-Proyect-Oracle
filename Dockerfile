FROM php:7.4-apache

# ------------------------------------------------------------
# Install system packages + PHP extensions
# ------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      git unzip \
      libjpeg-dev libpng-dev libfreetype6-dev \
      libzip-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" gd mysqli opcache zip; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Enable needed Apache modules
# ------------------------------------------------------------
RUN set -eux; \
    a2enmod rewrite expires headers

# Allow .htaccess overrides
RUN set -eux; \
    sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf

# Suppress ServerName warning
RUN set -eux; \
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername

# ------------------------------------------------------------
# Install Composer
# ------------------------------------------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# ------------------------------------------------------------
# App directory
# ------------------------------------------------------------
WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html

# ------------------------------------------------------------
# Install PHP dependencies
# ------------------------------------------------------------
RUN set -eux; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || true; \
    mkdir -p storage/logs storage/backups; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug+rwX storage || true

# ------------------------------------------------------------
# Runtime start script (Railway + MPM HARD FIX)
# ------------------------------------------------------------
RUN set -eux; \
    cat > /usr/local/bin/railway-apache-start <<'SH'
#!/usr/bin/env sh
set -e

PORT="${PORT:-80}"

echo "== Runtime MPM hard reset =="

# Disable all MPMs safely
a2dismod mpm_event  >/dev/null 2>&1 || true
a2dismod mpm_worker >/dev/null 2>&1 || true
a2dismod mpm_prefork >/dev/null 2>&1 || true

# Brutally remove any leftover enabled MPM symlinks
rm -f /etc/apache2/mods-enabled/mpm_*.load /etc/apache2/mods-enabled/mpm_*.conf || true

# Enable ONLY prefork (required for mod_php)
a2enmod mpm_prefork >/dev/null 2>&1

echo "== Enabled MPM modules =="
ls -la /etc/apache2/mods-enabled/mpm_*.load || true

# Bind Apache to Railway port
sed -ri "s/^Listen\s+[0-9]+/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

echo "== Port configuration =="
grep -n '^Listen' /etc/apache2/ports.conf || true
grep -n '<VirtualHost' /etc/apache2/sites-available/000-default.conf || true

exec apache2-foreground
SH

RUN chmod +x /usr/local/bin/railway-apache-start

EXPOSE 80
CMD ["railway-apache-start"]
