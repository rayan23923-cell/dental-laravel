# syntax=docker/dockerfile:1
# Images for the VPS deployment (see deploy/vps/README.md), all built from the repo root:
#   app  - PHP-FPM with the application, vendor/ and the built Vite assets
#   web  - nginx serving public/ and handing PHP to `app`

# PHP pinned to a patch release: 8.3.36 fixes CVE-2026-109618/109619 (2026-10-22).
FROM php:8.3.36-fpm-alpine AS base
RUN apk add --no-cache icu-libs libzip libpng libjpeg-turbo libwebp freetype mariadb-client \
    && apk add --no-cache --virtual .build $PHPIZE_DEPS icu-dev libzip-dev libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql intl zip gd bcmath exif opcache pcntl \
    && apk del .build

# Composer runs on the same PHP as production, so platform requirements (gd, zip, sodium...) are checked for real.
FROM base AS vendor
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --no-autoloader --prefer-dist
COPY . .
RUN composer dump-autoload --no-dev --optimize --no-interaction --no-scripts

# The frontend imports Ziggy straight from vendor/, so the build needs it.
FROM node:20-alpine AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
COPY --from=vendor /app/vendor ./vendor
RUN npm run build

FROM base AS app
COPY deploy/vps/php/php.ini /usr/local/etc/php/conf.d/zz-dental.ini
COPY deploy/vps/php/zz-pool.conf /usr/local/etc/php-fpm.d/zz-pool.conf
WORKDIR /var/www/html
COPY --from=vendor /app /var/www/html
COPY --from=assets /app/public/build /var/www/html/public/build
COPY deploy/vps/entrypoint.sh /usr/local/bin/dental-entrypoint
RUN chmod +x /usr/local/bin/dental-entrypoint \
    && rm -rf tests deploy flutter_app node_modules database/*.sqlite bootstrap/cache/*.php public/hot public/storage \
    && mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs storage/app/public storage/app/private bootstrap/cache \
    && ln -s /var/www/html/storage/app/public public/storage \
    && chown -R www-data:www-data storage bootstrap/cache
ENTRYPOINT ["dental-entrypoint"]
CMD ["php-fpm"]

# public/storage is a symlink into the storage volume, which compose mounts at the same path here.
FROM nginx:1.27-alpine AS web
COPY deploy/vps/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=app /var/www/html/public /var/www/html/public
