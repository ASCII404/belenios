#!/bin/sh
# =============================================================================
# Belenios container entrypoint
# =============================================================================
set -e

BELENIOS_BASE="/opt/belenios"
BELENIOS_USR="${BELENIOS_BASE}/usr"

PUBLIC_URL="${BELENIOS_PUBLIC_URL:-http://localhost:8001}"
ADMIN_MAIL="${BELENIOS_ADMIN_MAIL:-noreply@example.com}"
PORT="${BELENIOS_PORT:-8001}"

BELENIOS_SHAREDIR="${BELENIOS_USR}/share/belenios-server"

mkdir -p /data/etc /data/log /data/lib /data/upload /data/accounts /data/spool /tmp/belenios

if ! [ -f /data/spool/version ]; then
    echo 1 > /data/spool/version
fi

touch /data/password_db.csv

sed \
    -e "s@_VARDIR_@/data@g" \
    -e "s@_RUNDIR_@/tmp/belenios@g" \
    -e "s@_SHAREDIR_@${BELENIOS_SHAREDIR}@g" \
    -e "s@127.0.0.1:8001@${PORT}@g" \
    -e "s@prefix=\"http://127.0.0.1:8001\"@prefix=\"${PUBLIC_URL}\"@g" \
    "${BELENIOS_BASE}/demo/ocsigenserver.conf.in" > /data/etc/ocsigenserver.conf

# Patch the mail address separately to avoid @ delimiter conflicts
sed -i "s/noreply@example\.org/${ADMIN_MAIL}/g" /data/etc/ocsigenserver.conf

echo "[entrypoint] Starting Belenios on port ${PORT} (public URL: ${PUBLIC_URL})..."
exec "${BELENIOS_USR}/bin/belenios-server" -c /data/etc/ocsigenserver.conf
