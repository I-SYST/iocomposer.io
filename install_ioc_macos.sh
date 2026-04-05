#!/bin/bash
# IOcomposer Installer for macOS
# https://iocomposer.io

set -euo pipefail

# ---------------------------------------------------------
# Banner
# ---------------------------------------------------------
echo "=========================================="
echo "  IOcomposer Installer for macOS"
echo "=========================================="
echo ""

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
ECLIPSE_APP="/Applications/Eclipse.app"
DROPINS_DIR="$ECLIPSE_APP/Contents/Eclipse/dropins"

# AI plugin discovery (override supported via IOCOMPOSER_AI_PLUGIN_URL)
PLUGIN_NAME="com.iocomposer.embedcdt.ai"
PLUGIN_REPO="I-SYST/iocomposer.io"
PLUGIN_REPO_BRANCH="main"
PLUGIN_DIR_PATH="plugin"
PLUGIN_ID="com.iocomposer.embedcdt.ai"
PLUGIN_URL="${IOCOMPOSER_AI_PLUGIN_URL:-}"
OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ai.jar"
IOCOMPOSER_APP="/Applications/IOcomposer.app"
UI_PLUGIN_ID="com.iocomposer.embedcdt.ui"
UI_OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ui.jar"

UI_PLUGIN_ID="com.iocomposer.embedcdt.ui"
UI_OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ui.jar"

INSTALLER_URL="https://raw.githubusercontent.com/IOsonata/IOsonata/refs/heads/master/Installer/install_iocdevtools_macos.sh"

# SDK root (where IOsonata/external live). Default matches the main installer.
SDK_ROOT="$HOME/IOcomposer"

# Parse --home <path> (without consuming $@, works under set -u)
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
  # macOS uses BSD sort (no -V), so we compare padded strings in bash.
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
    [[ -n "$f" ]] || continue
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

  [[ -n "$best_file" ]] || return 1
  echo "https://github.com/${PLUGIN_REPO}/raw/${PLUGIN_REPO_BRANCH}/${PLUGIN_DIR_PATH}/${best_file}"
}
rename_eclipse_app() {
  local src="/Applications/Eclipse.app"
  local dst="$IOCOMPOSER_APP"

  if [[ -d "$src" ]]; then
    [[ -d "$dst" ]] && { echo "  Removing old IOcomposer.app..."; sudo rm -rf "$dst"; }
    echo "  Renaming Eclipse.app to IOcomposer.app..."
    sudo mv "$src" "$dst"
    sudo chown -R "$(stat -f "%u:%g" /Applications)" "$dst" 2>/dev/null || true
    echo "  [OK] Renamed."
  elif [[ -d "$dst" ]]; then
    echo "  IOcomposer.app already exists."
  else
    echo "  [WARN] Eclipse.app not found."
    return 0
  fi

  local plist="$dst/Contents/Info.plist"
  sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName IOcomposer" "$plist" 2>/dev/null || \
    sudo /usr/libexec/PlistBuddy -c "Add :CFBundleName string IOcomposer" "$plist" 2>/dev/null || true
  sudo /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName IOcomposer" "$plist" 2>/dev/null || \
    sudo /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string IOcomposer" "$plist" 2>/dev/null || true
  echo "  [OK] Info.plist patched."

  sudo rm -f "$dst/Contents/eclipse.ini.tmp" "$dst/Contents/Eclipse/eclipse.ini.tmp" 2>/dev/null || true

  local ini
  ini="$(find "$dst/Contents" -name "eclipse.ini" 2>/dev/null | head -1)"
  if [[ -n "$ini" ]] && ! grep -q "^-name$" "$ini"; then
    sudo awk '/^-vmargs$/ { print "-name"; print "IOcomposer" } { print }' \
      "$ini" | sudo tee "$ini.new" >/dev/null && sudo mv "$ini.new" "$ini"
    echo "  [OK] eclipse.ini: added -name IOcomposer"
  fi

  sudo touch "$dst" 2>/dev/null || true
}

patch_eclipse_ini() {
  local ini="$ECLIPSE_APP/Contents/Eclipse/eclipse.ini"
  local custom="$ECLIPSE_APP/Contents/Eclipse/plugin_customization.ini"

  echo "  Appending UI preferences to plugin_customization.ini..."
  # Just append to the portable file created by the main installer
  sudo touch "$custom"
  if ! grep -q "defaultPerspectiveId=com.iocomposer.embedcdt.ui.perspective" "$custom"; then
    printf '\n# IOcomposer UI preference customization\norg.eclipse.ui/showIntro=false\norg.eclipse.ui/defaultPerspectiveId=com.iocomposer.embedcdt.ui.perspective\norg.eclipse.epp.package.embedcpp/showNewsOnStartup=false\norg.eclipse.epp.package.embedcpp.ui/showNewsOnStartup=false\norg.eclipse.epp.package.cpp/showNewsOnStartup=false\norg.eclipse.epp.package.common/showNewsOnStartup=false\norg.eclipse.epp.mpc.ui/showNewsOnStartup=false\n' | sudo tee -a "$custom" >/dev/null
  fi

  # Only modify eclipse.ini to inject the UI scaling fix
  if ! grep -q "^-Dswt.autoScale=false" "$ini"; then
     sudo sed -i.bak '/^-vmargs$/a\
-Dswt.autoScale=false\
' "$ini"
  fi
  
  echo "  [OK] UI preferences appended. eclipse.ini remains portable."
}

sync_user_prefs() {
  echo ">>> Syncing MCU Toolchain Preferences for renamed IOcomposer profile..."
  
  # Force Eclipse to generate the new ~/.eclipse hash folder for the renamed app.
  "$ECLIPSE_APP/Contents/MacOS/eclipse" -nosplash -initialize 2>/dev/null || true
  
  # Find the newly created profile folder
  local instance_cfg=$(python3 -c '
import os, sys
base = os.path.expanduser("~/.eclipse")
cands = []
if os.path.isdir(base):
  for root, dirs, _ in os.walk(base):
    if "configuration" in dirs:
      p = os.path.join(root, "configuration")
      try: cands.append((os.path.getmtime(p), p))
      except: pass
if cands:
  cands.sort(reverse=True)
  print(cands[0][1])
')
  
  if [[ -n "$instance_cfg" ]]; then
    mkdir -p "$instance_cfg/.settings"
    local bundle_settings="$ECLIPSE_APP/Contents/Eclipse/configuration/.settings"
    if [[ -d "$bundle_settings" ]]; then
       cp -a "$bundle_settings/"*.prefs "$instance_cfg/.settings/" 2>/dev/null || true
       echo "  [OK] MCU settings successfully synced to user profile: $instance_cfg"
    fi
  fi
}

install_splash() {
  local src="$1"
  local eclipse_dir="$2"
  local found=0

  while IFS= read -r dst; do
    sudo cp "$src" "$dst" && { echo "  [OK] Replaced: $dst"; found=1; }
  done < <(find "$eclipse_dir" -name "splash.bmp" 2>/dev/null)

  local targets=("$eclipse_dir/Contents/Eclipse/splash.bmp")
  while IFS= read -r plugindir; do
    targets+=("$plugindir/splash.bmp")
  done < <(find "$eclipse_dir" -maxdepth 6 -type d \
    -name "org.eclipse.epp.package.*" 2>/dev/null)

  for dst in "${targets[@]}"; do
    sudo mkdir -p "$(dirname "$dst")" 2>/dev/null
    sudo cp "$src" "$dst" 2>/dev/null && { echo "  [OK] Written: $dst"; found=1; }
  done

  [[ "$found" == "1" ]] \
    && echo "  [OK] Splash installation complete." \
    || echo "  [WARN] Could not write splash to any location."
}


# ---------------------------------------------------------
# DOWNLOAD AND RUN MAIN INSTALLER
# ---------------------------------------------------------
echo ">>> Downloading Main Installer..."
TEMP_INSTALLER=$(mktemp /tmp/install_iocdevtools_macos.XXXXXX.sh)

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
  echo "   curl -fsSL https://iocomposer.io/install_ioc_macos.sh -o /tmp/install.sh && bash /tmp/install.sh"
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
if [[ -d "$ECLIPSE_APP" ]]; then

  # Make sure dropins folder exists
  if [[ ! -d "$DROPINS_DIR" ]]; then
    echo "  Creating dropins directory..."
    sudo mkdir -p "$DROPINS_DIR"
  fi

  # Discover latest plugin URL if not overridden
  if [[ -z "$PLUGIN_URL" ]]; then
      if ! PLUGIN_URL="$(discover_latest_plugin_url)"; then
      echo "  [ERROR] Failed to discover latest plugin JAR for: $PLUGIN_ID"
      echo "          You can override by setting IOCOMPOSER_AI_PLUGIN_URL to a direct JAR URL."
      exit 1
    fi
  fi

  # Download to a temporary location first
  TMP_JAR=$(mktemp)
  if curl -fsSL "$PLUGIN_URL" -o "$TMP_JAR"; then
    sudo mv "$TMP_JAR" "$OUTPUT_JAR"
    sudo chmod 644 "$OUTPUT_JAR"
    echo "  [OK] AI Plugin installed successfully: $OUTPUT_JAR"
  else
    echo "  [ERROR] Failed to download plugin."
    rm -f "$TMP_JAR"
    exit 1
  fi

else
  echo "  [ERROR] Eclipse app ($ECLIPSE_APP) not found. The main installation may have failed."
  exit 1
fi

# ---------------------------------------------------------
# POST-INSTALL: RENAME TO IOCOMPOSER
# ---------------------------------------------------------
echo ""
echo ">>> Renaming Eclipse to IOcomposer..."
rename_eclipse_app || true
if [[ -d "$IOCOMPOSER_APP" ]]; then
  ECLIPSE_APP="$IOCOMPOSER_APP"
  DROPINS_DIR="$ECLIPSE_APP/Contents/Eclipse/dropins"
  OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ai.jar"
  UI_OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ui.jar"
  
  # Trigger the RENAME FIX for MCU settings here
  sync_user_prefs
fi

# ---------------------------------------------------------
# POST-INSTALL: UI PLUGIN
# ---------------------------------------------------------
echo ""
echo ">>> Post-Install: Adding UI Plugin ($UI_PLUGIN_ID)..."
if [[ -d "$ECLIPSE_APP" ]]; then
  [[ -d "$DROPINS_DIR" ]] || sudo mkdir -p "$DROPINS_DIR"
  if UI_URL="$(discover_latest_plugin_url "$UI_PLUGIN_ID")"; then
      TMP=$(mktemp)
    if curl -fsSL "$UI_URL" -o "$TMP"; then
      sudo mv "$TMP" "$UI_OUTPUT_JAR"
      sudo chmod 644 "$UI_OUTPUT_JAR"
      echo "  [OK] UI Plugin installed: $UI_OUTPUT_JAR"
    else
      echo "  [WARN] Failed to download UI plugin."; rm -f "$TMP"
    fi
  else
    echo "  [WARN] Failed to discover UI plugin JAR."
  fi
  echo ">>> Patching eclipse.ini..."
  patch_eclipse_ini
else
  echo "  [ERROR] App not found: $ECLIPSE_APP"; exit 1
fi

# ---------------------------------------------------------
# POST-INSTALL: SPLASH SCREEN
# ---------------------------------------------------------
echo ""
echo ">>> Installing IOcomposer splash screen..."
SPLASH_URL="https://raw.githubusercontent.com/${PLUGIN_REPO}/${PLUGIN_REPO_BRANCH}/${PLUGIN_DIR_PATH}/splash.bmp"
SPLASH_TMP=$(mktemp /tmp/iocomposer_splash_XXXXXX.bmp)
if curl -fsSL "$SPLASH_URL" -o "$SPLASH_TMP"; then
  install_splash "$SPLASH_TMP" "$ECLIPSE_APP"
  rm -f "$SPLASH_TMP"
else
  echo "  [WARN] Could not download splash.bmp."
  rm -f "$SPLASH_TMP"
fi

echo ""
echo ">>> Signing IOcomposer.app..."
# codesign MUST run last — any file written into the bundle after signing
# (plugins, splash, eclipse.ini) invalidates the signature and causes Gatekeeper
# to block the app on reboot.
if [[ -d "$IOCOMPOSER_APP" ]]; then
  echo "  Removing quarantine attributes..."
  sudo xattr -cr "$IOCOMPOSER_APP" 2>/dev/null || true
  echo "  Applying ad-hoc codesign..."
  if sudo codesign --force --deep --sign - "$IOCOMPOSER_APP"; then
    echo "  [OK] Ad-hoc signature applied."
  else
    echo "  [WARN] codesign failed — app may be blocked after reboot."
    echo "         Run manually: sudo codesign --force --deep --sign - \"$IOCOMPOSER_APP\""
  fi
else
  echo "  [WARN] IOcomposer.app not found — skipping codesign."
fi

# ---------------------------------------------------------
# POST-INSTALL: Build External SDK Index (RAG)
# ---------------------------------------------------------
echo ""
echo ">>> Post-Install: Building external SDK index..."
INDEX_SCRIPT="$SDK_ROOT/IOsonata/Installer/build_external_index.py"

if [[ -f "$INDEX_SCRIPT" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    echo "  Running: python3 $INDEX_SCRIPT --sdk-root $SDK_ROOT/external"
    if python3 "$INDEX_SCRIPT" --sdk-root "$SDK_ROOT/external"; then
      echo "  [OK] External SDK index built."
    else
      echo "  [WARN] External SDK index build failed."
      echo "         You can retry manually with:"
      echo "         python3 \"$INDEX_SCRIPT\" --sdk-root \"$SDK_ROOT/external\""
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
