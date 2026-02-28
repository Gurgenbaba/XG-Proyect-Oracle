ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-apache

# ----------------------------------------------------
# Packages + PHP extensions
# ----------------------------------------------------
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        unzip \
        libjpeg-dev \
        libpng-dev \
        libzip-dev \
        libfreetype6-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install gd mysqli opcache zip; \
    a2enmod rewrite expires; \
    rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------
# HARD MPM FIX (Railway-safe):
# - purge any mpm_event/worker LoadModule lines across /etc/apache2
# - wipe mods-enabled mpm files
# - force-create ONLY prefork load file
# ----------------------------------------------------
RUN set -ex; \
    # Remove any LoadModule lines that load event/worker anywhere
    for f in $(grep -RIlE 'LoadModule\s+mpm_(event|worker)_module' /etc/apache2 || true); do \
        sed -i -E '/LoadModule\s+mpm_(event|worker)_module/d' "$f"; \
    done; \
    \
    # Remove all enabled MPM module files (even if they were not symlinks)
    rm -f /etc/apache2/mods-enabled/mpm_*.load /etc/apache2/mods-enabled/mpm_*.conf || true; \
    \
    # Force only prefork to be enabled via a single load file
    printf "LoadModule mpm_prefork_module /usr/lib/apache2/modules/mod_mpm_prefork.so\n" > /etc/apache2/mods-enabled/mpm_prefork.load; \
    \
    # Validate config now (fails build if still broken)
    apache2ctl -t; \
    apache2ctl -M | grep -E 'mpm_(prefork|event|worker)' || true

# ----------------------------------------------------
# Opcache recommended
# ----------------------------------------------------
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# ----------------------------------------------------
# Apache DocumentRoot -> /public
# ----------------------------------------------------
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

RUN set -ex; \
    sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf; \
    sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# ----------------------------------------------------
# Composer
# ----------------------------------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# ----------------------------------------------------
# App copy
# ----------------------------------------------------
COPY --chown=www-data:www-data . /var/www/html

# ----------------------------------------------------
# Dependencies
# ----------------------------------------------------
RUN set -ex; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader; \
    chown -R www-data:www-data /var/www/html

CMD ["apache2-foreground"]
