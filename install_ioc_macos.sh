#!/usr/bin/env bash
# IOcomposer website launcher for macOS.
# Installation, plugins, branding, signing, preferences and builds
# are managed exclusively by IOsonata/IOsonata/Installer.
set -euo pipefail

REF="${IOSONATA_INSTALLER_REF:-main}"
URL="https://raw.githubusercontent.com/IOsonata/IOsonata/${REF}/Installer/install_iocdevtools_macos.sh"
STAGE=$(mktemp "${TMPDIR:-/tmp}/install_iocdevtools_macos.XXXXXXXX")
trap 'rm -f "$STAGE"' EXIT

echo "Downloading IOcomposer macOS installer from IOsonata (${REF})..."
if ! curl -fsSL "$URL" -o "$STAGE"; then
  echo "Failed to download IOcomposer installer: $URL" >&2
  exit 1
fi

# Keep the caller's stdin available for the MCU selection prompt.
if [[ -t 0 ]]; then
  bash "$STAGE" "$@"
elif [[ -r /dev/tty ]]; then
  bash "$STAGE" "$@" </dev/tty
else
  case "${1:-}" in
    --help|--version) bash "$STAGE" "$@" ;;
    *) echo "Interactive installation requires a terminal. Download this launcher and run it directly." >&2; exit 1 ;;
  esac
fi
