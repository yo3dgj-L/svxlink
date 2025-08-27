#!/bin/bash
set -euo pipefail

SVXUSER="svxlink"
SVXGROUP="svxlink"
SVXPASS="svxlink"
SUDOERS="/etc/sudoers"
VISUDO="/usr/sbin/visudo"   # path to visudo on Debian/Ubuntu

echo "[INFO] Ensuring group: $SVXGROUP"
getent group "$SVXGROUP" >/dev/null || groupadd -r "$SVXGROUP"

echo "[INFO] Ensuring user: $SVXUSER"
if ! getent passwd "$SVXUSER" >/dev/null; then
  useradd -m -g "$SVXGROUP" -s /bin/bash "$SVXUSER"
else
  usermod -s /bin/bash "$SVXUSER"
fi

echo "[INFO] Setting password for $SVXUSER"
if command -v chpasswd >/dev/null 2>&1; then
  echo "${SVXUSER}:${SVXPASS}" | chpasswd
  passwd -u "$SVXUSER" || true
else
  echo "[WARN] chpasswd not found; cannot set password" >&2
fi

# Add to /etc/sudoers directly (safely, via visudo)
LINE_RE="^\\s*${SVXUSER}\\s+ALL=\\(ALL\\)\\s+NOPASSWD:ALL\\s*$"
if grep -Eq "$LINE_RE" "$SUDOERS"; then
  echo "[INFO] Sudoers entry already present in $SUDOERS"
else
  echo "[INFO] Adding sudoers entry to $SUDOERS"
  TMP="$(mktemp)"
  cp -a "$SUDOERS" "${SUDOERS}.bak.$(date +%F-%H%M%S)"
  cat "$SUDOERS" > "$TMP"
  printf "%s ALL=(ALL) NOPASSWD:ALL\n" "$SVXUSER" >> "$TMP"

  if [ -x "$VISUDO" ] && "$VISUDO" -c -f "$TMP" >/dev/null 2>&1; then
    install -m 0440 -o root -g root "$TMP" "$SUDOERS"
    echo "[INFO] sudoers updated successfully"
  else
    echo "[ERROR] visudo validation failed; NOT modifying $SUDOERS" >&2
    echo "[ERROR] You can inspect: $TMP" >&2
    exit 1
  fi
  rm -f "$TMP" || true
fi

echo "[DONE] setup_svxlink_user.sh complete."
