ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-apache

# ----------------------------------------------------
# System packages + PHP extensions
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
# HARD FIX: ensure ONLY ONE Apache MPM (prefork)
# ----------------------------------------------------
RUN set -ex; \
    a2dismod mpm_event mpm_worker mpm_prefork || true; \
    rm -f /etc/apache2/mods-enabled/mpm_event.load /etc/apache2/mods-enabled/mpm_event.conf || true; \
    rm -f /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf || true; \
    rm -f /etc/apache2/mods-enabled/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.conf || true; \
    a2enmod mpm_prefork

# ----------------------------------------------------
# Opcache recommended settings
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
# Install Composer (from official image)
# ----------------------------------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# ----------------------------------------------------
# Copy application
# ----------------------------------------------------
COPY --chown=www-data:www-data . /var/www/html

# ----------------------------------------------------
# Install PHP dependencies
# ----------------------------------------------------
RUN set -ex; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader; \
    chown -R www-data:www-data /var/www/html

# ----------------------------------------------------
# Start Apache
# ----------------------------------------------------
CMD ["apache2-foreground"]
