# -----------------------------------------------------------------------------
# XG Proyect (PHP 7.4 + Apache) for Railway
# Fixes: "AH00534: More than one MPM loaded."
# Ensures: only mpm_prefork enabled (required for mod_php)
# Adds: AllowOverride All (for .htaccess), ServerName, perms for storage
# Optional: bind Apache to $PORT at runtime (Railway)
# -----------------------------------------------------------------------------

FROM php:7.4-apache

# System deps + PHP extensions
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

# Apache modules + hard MPM fix (ONLY prefork)
RUN set -eux; \
    a2enmod rewrite expires headers; \
    \
    # Disable ALL MPMs first (ignore if not enabled), then enable only prefork
    a2dismod mpm_event  || true; \
    a2dismod mpm_worker || true; \
    a2dismod mpm_prefork || true; \
    a2enmod mpm_prefork; \
    \
    # Extra safety: remove any leftover enabled MPM load/conf files except prefork
    find /etc/apache2/mods-enabled -maxdepth 1 -type l -name 'mpm_*.load' ! -name 'mpm_prefork.load' -delete || true; \
    find /etc/apache2/mods-enabled -maxdepth 1 -type l -name 'mpm_*.conf' ! -name 'mpm_prefork.conf' -delete || true

# Allow .htaccess overrides (XG uses rewrites)
RUN set -eux; \
    sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf

# Suppress ServerName warning (optional)
RUN set -eux; \
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername

# Install Composer (from official image)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# App path
WORKDIR /var/www/html

# Copy project
COPY --chown=www-data:www-data . /var/www/html

# Composer install (prod)
RUN set -eux; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || true; \
    \
    # Ensure writable dirs (XG uses storage/)
    mkdir -p storage/logs storage/backups; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug+rwX storage || true

# Railway: bind Apache to $PORT dynamically at runtime
RUN set -eux; \
    cat > /usr/local/bin/railway-apache-start <<'SH'\n\
#!/usr/bin/env sh\n\
set -e\n\
PORT=\"${PORT:-80}\"\n\
# Update ports.conf + default vhost to listen on $PORT\n\
sed -ri \"s/^Listen\\s+[0-9]+/Listen ${PORT}/\" /etc/apache2/ports.conf\n\
sed -ri \"s/<VirtualHost \\*:[0-9]+>/<VirtualHost *:${PORT}>/\" /etc/apache2/sites-available/000-default.conf\n\
exec apache2-foreground\n\
SH\n\
    chmod +x /usr/local/bin/railway-apache-start

EXPOSE 80

CMD ["railway-apache-start"]
