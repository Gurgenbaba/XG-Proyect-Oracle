FROM php:7.4-apache

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

# Apache modules + HARD MPM fix: ONLY prefork
RUN set -eux; \
    a2enmod rewrite expires headers; \
    \
    # Disable all MPMs (ignore errors)
    a2dismod mpm_event  || true; \
    a2dismod mpm_worker || true; \
    a2dismod mpm_prefork || true; \
    \
    # Brutal remove leftover symlinks (this is the real fix on Railway sometimes)
    rm -f /etc/apache2/mods-enabled/mpm_event.load  /etc/apache2/mods-enabled/mpm_event.conf  || true; \
    rm -f /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf || true; \
    \
    # Enable prefork only
    a2enmod mpm_prefork; \
    \
    # Sanity check (will fail build if more than one exists)
    ls -la /etc/apache2/mods-enabled/mpm_*.load; \
    test -f /etc/apache2/mods-enabled/mpm_prefork.load; \
    test ! -f /etc/apache2/mods-enabled/mpm_event.load; \
    test ! -f /etc/apache2/mods-enabled/mpm_worker.load

# Allow .htaccess overrides
RUN set -eux; \
    sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf

# Suppress ServerName warning
RUN set -eux; \
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html

RUN set -eux; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || true; \
    mkdir -p storage/logs storage/backups; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug+rwX storage || true

# Railway: bind Apache to $PORT
RUN set -eux; \
    cat > /usr/local/bin/railway-apache-start <<'SH'
#!/usr/bin/env sh
set -e
PORT="${PORT:-80}"

# Update ports.conf + default vhost to listen on $PORT
sed -ri "s/^Listen\s+[0-9]+/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

exec apache2-foreground
SH
RUN chmod +x /usr/local/bin/railway-apache-start

EXPOSE 80
CMD ["railway-apache-start"]
