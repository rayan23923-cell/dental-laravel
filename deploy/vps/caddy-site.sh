#!/bin/sh
# Adds the dental site to the shared Caddy (container `caddy`) once, without touching the other sites.
# The Caddyfile is shared with the files site (FileNest), the SIS and any others, so:
#   - it is only ever appended to (same inode, so a single-file bind mount sees the change),
#   - a copy is kept first, and the copy is put back if Caddy rejects the new config.
set -eu
DOMAIN="${DENTAL_DOMAIN:-dental.azoclinic.duckdns.org}"
CADDYFILE="${CADDYFILE:-/home/ubuntu/headscale/Caddyfile}"
CONTAINER="${CADDY_CONTAINER:-caddy}"

[ -f "$CADDYFILE" ] || { echo "Caddyfile not found at $CADDYFILE" >&2; exit 1; }
if grep -q "^$DOMAIN" "$CADDYFILE"; then
    echo "Caddy already serves $DOMAIN."
    exit 0
fi

# Where the Caddyfile is inside the container: a bind mount of the file itself or of a folder holding it.
inner=""
for m in $(sudo docker inspect -f '{{range .Mounts}}{{.Source}}={{.Destination}} {{end}}' "$CONTAINER"); do
    src="${m%%=*}"; dst="${m#*=}"
    if [ "$src" = "$CADDYFILE" ]; then inner="$dst"; break; fi
    case "$CADDYFILE" in "$src"/*) inner="$dst${CADDYFILE#"$src"}";; esac
done
[ -n "$inner" ] || inner=/etc/caddy/Caddyfile
echo "Caddyfile inside $CONTAINER: $inner"

backup="$CADDYFILE.bak-dental-$(date +%Y%m%d_%H%M%S)"
sudo cp -p "$CADDYFILE" "$backup"
printf '\n# Dental clinic system (deploy/vps in rayan23923-cell/dental-laravel)\n%s {\n\treverse_proxy dental-web:80\n}\n' "$DOMAIN" \
    | sudo tee -a "$CADDYFILE" >/dev/null

if sudo docker exec "$CONTAINER" caddy validate --config "$inner" --adapter caddyfile >/dev/null 2>&1 \
    && sudo docker exec "$CONTAINER" caddy reload --config "$inner" --adapter caddyfile; then
    echo "Caddy now serves https://$DOMAIN (backup: $backup)."
else
    echo "Caddy rejected the new site; restoring the previous Caddyfile." >&2
    sudo sh -c "cat '$backup' > '$CADDYFILE'"
    sudo docker exec "$CONTAINER" caddy reload --config "$inner" --adapter caddyfile || true
    exit 1
fi
