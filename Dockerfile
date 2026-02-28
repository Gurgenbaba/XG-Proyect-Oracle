ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-apache

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
    \
    # Fix: allow only one MPM (mod_php -> prefork)
    a2dismod mpm_event || true; \
    a2dismod mpm_worker || true; \
    a2enmod mpm_prefork; \
    \
    rm -rf /var/lib/apt/lists/*

RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN set -ex; \
  sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf; \
  sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html

RUN set -ex; \
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader; \
    chown -R www-data:www-data /var/www/html

CMD ["apache2-foreground"]
