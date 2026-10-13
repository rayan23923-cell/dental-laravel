#!/bin/sh
# Prepares the application, then hands over to php-fpm. Runs on every container start and is safe to repeat.
set -e
cd /var/www/html

if [ "$1" = "php-fpm" ]; then
    echo "Waiting for the database..."
    tries=0
    until php -r 'try { new PDO("mysql:host=".getenv("DB_HOST").";port=".(getenv("DB_PORT")?:3306).";dbname=".getenv("DB_DATABASE"), getenv("DB_USERNAME"), getenv("DB_PASSWORD")); } catch (Throwable $e) { exit(1); }'; do
        tries=$((tries + 1))
        [ "$tries" -ge 60 ] && { echo "Database did not come up." >&2; exit 1; }
        sleep 2
    done

    mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs storage/app/public storage/app/private
    php artisan migrate --force --no-interaction
    # The seeder creates the first super admin and the base stages/departments; it only runs on an empty install.
    if [ ! -f storage/app/.seeded ]; then
        php artisan db:seed --force --no-interaction && touch storage/app/.seeded
    fi
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache
    chown -R www-data:www-data storage bootstrap/cache
fi

exec docker-php-entrypoint "$@"
