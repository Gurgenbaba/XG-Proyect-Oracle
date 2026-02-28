ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-apache

# --- Apache DocumentRoot -> /public ---
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

# install needed packages + PHP extensions
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      git unzip \
      libjpeg-dev libpng-dev libzip-dev libfreetype6-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install gd mysqli opcache zip; \
    rm -rf /var/lib/apt/lists/*

# opcache recommended
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# apache modules
RUN a2enmod rewrite expires

# --- Fix DocumentRoot in apache configs ---
RUN set -ex; \
  sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf; \
  sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# --- Allow .htaccess to work (important for rewrites) ---
RUN set -ex; \
  sed -ri 's/AllowOverride\s+None/AllowOverride All/g' /etc/apache2/apache2.conf

# --- ServerName warning kill (optional but clean) ---
RUN set -ex; \
  echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf; \
  a2enconf servername

# --- MPM safety (falls dein Base image was lädt) ---
RUN set -ex; \
  a2dismod mpm_event || true; \
  a2dismod mpm_worker || true; \
  a2enmod mpm_prefork || true

# Composer from official image
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy app
COPY --chown=www-data:www-data . /var/www/html

# Install deps
RUN set -ex; \
  composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader; \
  chown -R www-data:www-data /var/www/html

CMD ["apache2-foreground"]
