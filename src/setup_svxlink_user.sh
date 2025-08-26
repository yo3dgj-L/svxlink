#!/bin/bash
set -e

SVXUSER="svxlink"
SVXGROUP="svxlink"
SVXPASS="svxlink"

echo "[INFO] Ensuring group $SVXGROUP exists..."
getent group "$SVXGROUP" >/dev/null || groupadd -r "$SVXGROUP"

echo "[INFO] Ensuring user $SVXUSER exists..."
if ! getent passwd "$SVXUSER" >/dev/null; then
  useradd -m -g "$SVXGROUP" -s /bin/bash "$SVXUSER"
else
  usermod -s /bin/bash "$SVXUSER"
fi

echo "[INFO] Setting password for $SVXUSER..."
echo "${SVXUSER}:${SVXPASS}" | chpasswd
passwd -u "$SVXUSER" || true

echo "[INFO] Adding $SVXUSER to sudoers with NOPASSWD..."
if [ -d /etc/sudoers.d ]; then
  echo "$SVXUSER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SVXUSER"
  chmod 0440 "/etc/sudoers.d/$SVXUSER"
fi

echo "[INFO] Done."
