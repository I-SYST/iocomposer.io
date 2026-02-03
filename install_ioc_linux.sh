#!/bin/bash
# IOcomposer Installer for Linux
# https://iocomposer.io

set -euo pipefail

echo "=========================================="
echo "  IOcomposer Installer for Linux"
echo "=========================================="
echo ""
echo "IOcomposer is currently in preview."
echo "The installer is not yet available."
echo ""
echo "To join the preview, contact: info@i-syst.com"
echo ""
echo "=========================================="

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
ECLIPSE_DIR="$HOME/eclipse"
DROPINS_DIR="$ECLIPSE_DIR/dropins"

# AI Plugin Discovery
PLUGIN_NAME="com.iocomposer.embedcdt.ai"
PLUGIN_REPO="I-SYST/iocomposer.io"
PLUGIN_REPO_BRANCH="main"
PLUGIN_DIR_PATH="plugin"
PLUGIN_ID="plugin"
PLUGIN_URL="${IOCOMPOSER_AI_PLUGIN_URL:-}"
OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ai.jar"

INSTALLER_URL="https://raw.githubusercontent.com/IOsonata/IOsonata/refs/heads/master/Installer/install_iocdevtools_linux.sh"

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
version_key() {
  # Turn a dotted version like 0.0.22 into a lexicographically sortable key.
  local ver="$1"
  local key=""
  local IFS='.'
  local parts=()
  read -ra parts <<< "$ver"

  local p=""
  for p in "${parts[@]}"; do
    key="${key}$(printf '%05d' "$p")"
  done

  # pad to 6 segments: 1.2 == 1.2.0.0.0.0
  local i=0
  for ((i=${#parts[@]}; i<6; i++)); do
    key="${key}00000"
  done

  echo "$key"
}

discover_latest_plugin_url() {
  local api="https://api.github.com/repos/${PLUGIN_REPO}/contents/${PLUGIN_DIR_PATH}?ref=${PLUGIN_REPO_BRANCH}"
  local json=""

  json="$(curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: iocomposer-installer' "$api")" || return 1

  # Extract "name" fields (avoid jq dependency)
  local names=""
  names="$(echo "$json" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')" || true

  local best_file=""
  local best_key=""

  local f=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [[ "$f" == ${PLUGIN_ID}_*.jar ]] || continue

    local ver="${f#${PLUGIN_ID}_}"
    ver="${ver%.jar}"

    # Accept numeric dotted versions like 0.0.22
    if [[ ! "$ver" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
      continue
    fi

    local key
    key="$(version_key "$ver")"

    if [[ -z "$best_key" || "$key" > "$best_key" ]]; then
      best_key="$key"
      best_file="$f"
    fi
  done <<< "$names"

  [ -n "$best_file" ] || return 1
  echo "https://github.com/${PLUGIN_REPO}/raw/${PLUGIN_REPO_BRANCH}/${PLUGIN_DIR_PATH}/${best_file}"
}

# ---------------------------------------------------------
# DOWNLOAD AND RUN MAIN INSTALLER
# ---------------------------------------------------------
echo ">>> Downloading Main Installer..."
TEMP_INSTALLER=$(mktemp /tmp/install_iocdevtools_linux.XXXXXX.sh)

# Cleanup on exit
cleanup() {
    rm -f "$TEMP_INSTALLER" 2>/dev/null || true
}
trap cleanup EXIT

if ! curl -fsSL "$INSTALLER_URL" -o "$TEMP_INSTALLER"; then
    echo "❌ Failed to download installer from:"
    echo "   $INSTALLER_URL"
    exit 1
fi

chmod +x "$TEMP_INSTALLER"

echo ">>> Launching Main Installer..."

if [ -t 0 ]; then
  # Normal run (stdin is already the terminal)
  bash "$TEMP_INSTALLER" "$@"
elif [ -r /dev/tty ]; then
  # Running from a pipe: give the child script the controlling terminal for prompts
  bash "$TEMP_INSTALLER" "$@" </dev/tty
else
  echo "❌ No TTY available for interactive prompts."
  echo "   Run instead:"
  echo "   curl -fsSL https://iocomposer.io/install_ioc_linux.sh -o /tmp/install.sh && bash /tmp/install.sh"
  exit 1
fi

# ---------------------------------------------------------
# POST-INSTALL: AI PLUGIN
# ---------------------------------------------------------
echo ""
echo ">>> Post-Install: Adding AI Plugin ($PLUGIN_NAME)..."

# Check if Eclipse is installed
if [ -d "$ECLIPSE_DIR" ]; then

    # Make sure dropins folder exists
    if [ ! -d "$DROPINS_DIR" ]; then
        echo "  Creating dropins directory..."
        sudo mkdir -p "$DROPINS_DIR"
    fi

    # Discover latest plugin URL if not overridden
    if [ -z "$PLUGIN_URL" ]; then
      echo "  Discovering latest AI plugin from GitHub..."
      if ! PLUGIN_URL="$(discover_latest_plugin_url)"; then
        echo "  ⚠️  Failed to discover latest plugin JAR for: $PLUGIN_ID"
        echo "     You can override by setting IOCOMPOSER_AI_PLUGIN_URL to a direct JAR URL."
        echo "     The plugin may not be available yet."
        echo "     You can install it manually later."
        # Don't exit with error - plugin is optional on Linux
        echo ">>> Setup complete (without AI plugin)."
        exit 0
      fi
      echo "  Latest plugin URL: $PLUGIN_URL"
    else
      echo "  Using overridden plugin URL: $PLUGIN_URL"
    fi

    # Download to a temporary location first
    TMP_JAR=$(mktemp)
    echo "  Downloading from $PLUGIN_URL..."

    # Move to dropin folder if succesful download
    if curl -fL "$PLUGIN_URL" -o "$TMP_JAR"; then
        echo "  Installing to $DROPINS_DIR..."
        mv "$TMP_JAR" "$OUTPUT_JAR"
        chmod 644 "$OUTPUT_JAR"
        echo "  [OK] AI Plugin installed successfully: $OUTPUT_JAR"

    # Otherwise, delete the temporary file
    else
        echo "  ⚠️  Failed to download AI plugin (non-critical)."
        echo "     The plugin may not be available yet or the URL has changed."
        echo "     You can install it manually later from:"
        echo "     $PLUGIN_URL"
        rm -f "$TMP_JAR"
        # Don't exit with error - plugin is optional
    fi
else
    echo "  [ERROR] Eclipse directory ($ECLIPSE_DIR) not found. The main installation may have failed."
    exit 1
fi

echo ">>> Setup complete."
