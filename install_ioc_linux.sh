#!/bin/bash
# IOcomposer Installer for Linux
# https://iocomposer.io

set -euo pipefail

# ---------------------------------------------------------
# BANNER
# ---------------------------------------------------------
echo "=========================================="
echo "  IOcomposer Installer for Linux"
echo "=========================================="
echo ""

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
PLUGIN_ID="com.iocomposer.embedcdt.ai"
PLUGIN_URL="${IOCOMPOSER_AI_PLUGIN_URL:-}"
OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ai.jar"

UI_PLUGIN_ID="com.iocomposer.embedcdt.ui"
UI_OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ui.jar"

INSTALLER_URL="https://raw.githubusercontent.com/IOsonata/IOsonata/refs/heads/master/Installer/install_iocdevtools_linux.sh"

# SDK root (where IOsonata/external live). Default matches the main installer.
SDK_ROOT="$HOME/IOcomposer"

# Parse --home <path> (without consuming $@)
if [[ $# -gt 0 ]]; then
  for ((i=1; i<=$#; i++)); do
    arg="${!i}"
    if [[ "$arg" == "--home" ]] && (( i < $# )); then
      next=$((i+1))
      SDK_ROOT="${!next}"
      break
    fi
  done
fi

# Skip post-install steps for non-install flows
SKIP_POST=0
for a in "$@"; do
  case "$a" in
    --uninstall|--help|--version) SKIP_POST=1 ;;
  esac
done

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
  local plugin_id="${1:-$PLUGIN_ID}"
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
    [[ "$f" == ${plugin_id}_*.jar ]] || continue

    local ver="${f#${plugin_id}_}"
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
patch_eclipse_ini() {
  local ini="$ECLIPSE_DIR/eclipse.ini"
  local custom="$DROPINS_DIR/iocomposer_customization.ini"
  printf '# IOcomposer preference customization\norg.eclipse.ui/showIntro=false\norg.eclipse.ui/defaultPerspectiveId=com.iocomposer.embedcdt.ui.perspective\norg.eclipse.epp.package.embedcpp/showNewsOnStartup=false\norg.eclipse.epp.package.embedcpp.ui/showNewsOnStartup=false\norg.eclipse.epp.package.cpp/showNewsOnStartup=false\norg.eclipse.epp.package.common/showNewsOnStartup=false\norg.eclipse.epp.mpc.ui/showNewsOnStartup=false\n' > "$custom"
  echo "  Written: $custom"
  if grep -q "iocomposer_customization.ini" "$ini" 2>/dev/null; then
    echo "  eclipse.ini already patched."
  else
    awk -v p="$custom" '
      /^-vmargs$/ {
        print "-pluginCustomization"
        print p
        print "-vmargs"
        next
      }
      { print }
    ' "$ini" > "$ini.tmp" && mv "$ini.tmp" "$ini"
    echo "  Patched: $ini"
  fi
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
  bash "$TEMP_INSTALLER" "$@"
elif [ -r /dev/tty ]; then
  bash "$TEMP_INSTALLER" "$@" </dev/tty
else
  echo "❌ No TTY available for interactive prompts."
  echo "   Run instead:"
  echo "   curl -fsSL https://iocomposer.io/install_ioc_linux.sh -o /tmp/install.sh && bash /tmp/install.sh"
  exit 1
fi

# If we ran a non-install flow (uninstall/help/version), do not attempt post-install steps.
if [[ "$SKIP_POST" == "1" ]]; then
  echo ""
  echo ">>> Skipping post-install steps."
  exit 0
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
        mkdir -p "$DROPINS_DIR"
    fi

    # Discover latest plugin URL if not overridden
    if [ -z "$PLUGIN_URL" ]; then
      echo "  Discovering latest AI plugin from GitHub..."
      if ! PLUGIN_URL="$(discover_latest_plugin_url)"; then
        echo "  ⚠️  Failed to discover latest plugin JAR for: $PLUGIN_ID"
        echo "     You can override by setting IOCOMPOSER_AI_PLUGIN_URL to a direct JAR URL."
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

# ---------------------------------------------------------
# POST-INSTALL: UI PLUGIN
# ---------------------------------------------------------
echo ""
echo ">>> Post-Install: Adding UI Plugin ($UI_PLUGIN_ID)..."

if [ -d "$ECLIPSE_DIR" ]; then
  [ -d "$DROPINS_DIR" ] || mkdir -p "$DROPINS_DIR"
  if UI_URL="$(discover_latest_plugin_url "$UI_PLUGIN_ID")"; then
    echo "  Latest UI plugin URL: $UI_URL"
    TMP=$(mktemp)
    if curl -fL "$UI_URL" -o "$TMP"; then
      mv "$TMP" "$UI_OUTPUT_JAR"
      chmod 644 "$UI_OUTPUT_JAR"
      echo "  [OK] UI Plugin installed: $UI_OUTPUT_JAR"
    else
      echo "  [WARN] Failed to download UI plugin."
      rm -f "$TMP"
    fi
  else
    echo "  [WARN] Failed to discover UI plugin JAR."
  fi
  echo ">>> Patching eclipse.ini for IOcomposer preferences..."
  patch_eclipse_ini
else
  echo "  [ERROR] Eclipse directory not found."
  exit 1
fi

# ---------------------------------------------------------
# POST-INSTALL: SPLASH SCREEN
# ---------------------------------------------------------
echo ""
echo ">>> Installing IOcomposer splash screen..."
SPLASH_SRC="$(dirname "$0")/splash.bmp"

if [ -f "$SPLASH_SRC" ]; then
  echo "  Searching for splash targets..."
  INSTALLED=0
  while IFS= read -r SPLASH_FILE; do
    echo "  Found: $SPLASH_FILE"
    cp "$SPLASH_SRC" "$SPLASH_FILE" && {
      echo "  [OK] Replaced: $(basename "$(dirname "$SPLASH_FILE")")/splash.bmp"
      INSTALLED=1
    }
  done < <(find "$ECLIPSE_DIR" -name "splash.bmp" 2>/dev/null)
  if [ "$INSTALLED" = "1" ]; then
    echo "  [OK] Splash installation complete."
  else
    echo "  [WARN] No splash.bmp found — trying fallback..."
    cp "$SPLASH_SRC" "$ECLIPSE_DIR/splash.bmp" 2>/dev/null && echo "  Copied to eclipse root."
  fi
else
  echo "  [WARN] splash.bmp not found next to installer — skipping."
fi

# ---------------------------------------------------------
# POST-INSTALL: Build External SDK Index (RAG)
# ---------------------------------------------------------
echo ""
echo ">>> Post-Install: Building external SDK index..."
INDEX_SCRIPT="$SDK_ROOT/IOsonata/Installer/build_external_index.py"

if [ -f "$INDEX_SCRIPT" ]; then
  if command -v python3 >/dev/null 2>&1; then
    echo "  Running: python3 $INDEX_SCRIPT --sdk-root $SDK_ROOT/external"
    if python3 "$INDEX_SCRIPT" --sdk-root "$SDK_ROOT/external"; then
      echo "  [OK] External SDK index built."
    else
      echo "  [WARN] External SDK index build failed."
      echo "         You can retry manually with:"
      echo "         python3 $INDEX_SCRIPT --sdk-root $SDK_ROOT/external"
    fi
  else
    echo "  [WARN] python3 not found. Skipping external SDK index build."
  fi
else
  echo "  [WARN] Index script not found at: $INDEX_SCRIPT"
  echo "         Skipping external SDK index build."
fi

echo ""
echo ">>> Setup complete."