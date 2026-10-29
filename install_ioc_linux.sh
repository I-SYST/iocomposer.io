#!/usr/bin/env bash
# IOcomposer website launcher for Linux.
# Installation, plugins, branding, preferences and builds
# are managed exclusively by IOsonata/IOsonata/Installer.
set -euo pipefail

REF="${IOSONATA_INSTALLER_REF:-main}"
URL="https://raw.githubusercontent.com/IOsonata/IOsonata/${REF}/Installer/install_iocdevtools_linux.sh"
STAGE=$(mktemp "${TMPDIR:-/tmp}/install_iocdevtools_linux.XXXXXXXX")
trap 'rm -f "$STAGE"' EXIT

echo "Downloading IOcomposer Linux installer from IOsonata (${REF})..."
if ! curl -fsSL "$URL" -o "$STAGE"; then
  echo "Failed to download IOcomposer installer: $URL" >&2
  exit 1
fi

# Do not run any additional post-install steps after the main installer.
if [[ -t 0 ]]; then
  bash "$STAGE" "$@"
elif [[ -r /dev/tty ]]; then
  bash "$STAGE" "$@" </dev/tty
else
  echo "Interactive installation requires a terminal. Download this launcher and run it directly." >&2
  exit 1
fi
