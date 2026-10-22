#!/bin/sh
# Builds and (re)starts the dental app on the VPS. Run from the repo root on the server: sh deploy/vps/deploy.sh
# First run: creates .env with random secrets and, once the app is up, replaces the seeded admin's default
# password with a random one saved to ~/dental-admin-password.txt (readable only by this user).
set -eu
cd "$(dirname "$0")/../.."

compose() { sudo docker compose --env-file .env -f deploy/vps/docker-compose.yml "$@"; }
rand() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

first_run=no
if [ ! -f .env ]; then
    first_run=yes
    umask 077
    sed -e "s|^APP_KEY=.*|APP_KEY=base64:$(head -c 32 /dev/urandom | base64)|" \
        -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$(rand 32)|" \
        -e "s|^DB_ROOT_PASSWORD=.*|DB_ROOT_PASSWORD=$(rand 32)|" \
        deploy/vps/env.example > .env
    echo "Created .env with fresh secrets."
fi

# Back up the database and uploaded files before every update (2026-10-13), the same safety
# net the offline package has. Kept in ~/dental-backups: the last 20 database dumps and the
# last 3 copies of the uploads. A failed backup stops the deploy. Skipped on the very first run.
if sudo docker ps --format '{{.Names}}' | grep -qx dental-db; then
    backups="$HOME/dental-backups"
    stamp="$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backups"
    sudo docker exec dental-db sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines "$MYSQL_DATABASE"' \
        | gzip > "$backups/db_$stamp.sql.gz"
    gzip -dc "$backups/db_$stamp.sql.gz" | grep -q 'CREATE TABLE' \
        || { echo "Database backup failed; stopping before the update." >&2; rm -f "$backups/db_$stamp.sql.gz"; exit 1; }
    if sudo docker ps --format '{{.Names}}' | grep -qx dental-app; then
        sudo docker exec dental-app tar czf - -C storage/app public > "$backups/uploads_$stamp.tgz"
    fi
    ls -1t "$backups"/db_*.sql.gz | tail -n +21 | xargs -r rm -f
    ls -1t "$backups"/uploads_*.tgz 2>/dev/null | tail -n +4 | xargs -r rm -f
    echo "Backed up to $backups (db_$stamp.sql.gz)."
fi

# --pull fetches the newest base images (PHP security fixes) instead of a cached copy.
compose build --pull
compose up -d

echo "Waiting for the app to finish migrating..."
tries=0
until sudo docker exec dental-app test -f storage/app/.seeded 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -ge 90 ] && { echo "App did not finish starting; see: sudo docker logs dental-app" >&2; exit 1; }
    sleep 2
done

if [ "$first_run" = yes ]; then
    pw="$(rand 16)"
    sudo docker exec -e NEW_PW="$pw" dental-app php artisan tinker --execute='App\Models\User::where("username","admin")->update(["password" => Illuminate\Support\Facades\Hash::make(getenv("NEW_PW"))]);' >/dev/null
    (umask 077; printf 'username: admin\npassword: %s\n' "$pw" > "$HOME/dental-admin-password.txt")
    echo "Admin password saved to ~/dental-admin-password.txt"
fi

echo "PHP $(sudo docker exec dental-app php -r 'echo PHP_VERSION;')"
compose ps
