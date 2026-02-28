FROM php:7.4-apache

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

# Apache setup
RUN set -eux; \
    a2enmod rewrite expires headers dir; \
    a2dismod mpm_event  >/dev/null 2>&1 || true; \
    a2dismod mpm_worker >/dev/null 2>&1 || true; \
    rm -f /etc/apache2/mods-enabled/mpm_event.* || true; \
    rm -f /etc/apache2/mods-enabled/mpm_worker.* || true; \
    a2enmod mpm_prefork; \
    sed -ri 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/public#g' /etc/apache2/sites-available/000-default.conf; \
    sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf; \
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html

RUN set -eux; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || true; \
    mkdir -p storage/logs storage/backups; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug+rwX storage config database || true

# --- Start script (FIXED SYNTAX) ---
RUN set -eux; \
    printf '%s\n' \
'#!/usr/bin/env sh' \
'set -e' \
'' \
'PORT="${PORT:-80}"' \
'' \
'echo "== MPM reset =="'; \
    printf '%s\n' \
'a2dismod mpm_event >/dev/null 2>&1 || true' \
'a2dismod mpm_worker >/dev/null 2>&1 || true' \
'rm -f /etc/apache2/mods-enabled/mpm_event.* || true' \
'rm -f /etc/apache2/mods-enabled/mpm_worker.* || true' \
'a2enmod mpm_prefork >/dev/null 2>&1 || true' \
> /usr/local/bin/railway-apache-start; \
    printf '%s\n' \
'' \
'echo "== Port config =="'; \
    printf '%s\n' \
'echo "Listen 80" > /etc/apache2/ports.conf' \
'if [ "$PORT" != "80" ]; then echo "Listen $PORT" >> /etc/apache2/ports.conf; fi' \
'sed -ri "s/<VirtualHost \\*:[0-9]+>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf' \
>> /usr/local/bin/railway-apache-start; \
    printf '%s\n' \
'' \
'echo "== Starting Apache =="'; \
    printf '%s\n' \
'exec apache2-foreground' \
>> /usr/local/bin/railway-apache-start; \
    chmod +x /usr/local/bin/railway-apache-start

EXPOSE 80 8080
CMD ["railway-apache-start"]
