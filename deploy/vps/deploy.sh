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

compose build
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

compose ps
