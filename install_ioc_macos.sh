#!/bin/bash
# IOcomposer Installer for macOS
# https://iocomposer.io

set -euo pipefail

echo "=========================================="
echo "  IOcomposer Installer for macOS"
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
ECLIPSE_APP="/Applications/Eclipse.app"
DROPINS_DIR="$ECLIPSE_APP/Contents/Eclipse/dropins"
PLUGIN_NAME="com.iocomposer.embedcdt.ai"
PLUGIN_URL="https://github.com/I-SYST/iocomposer.io/raw/main/plugin/com.iocomposer.embedcdt.ai_0.0.22.jar"
OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ai.jar"

INSTALLER_URL="https://raw.githubusercontent.com/IOsonata/IOsonata/refs/heads/master/Installer/install_iocdevtools_macos.sh"

# ---------------------------------------------------------
# DOWNLOAD AND RUN MAIN INSTALLER
# ---------------------------------------------------------
echo ">>> Downloading Main Installer..."
TEMP_INSTALLER=$(mktemp /tmp/install_iocdevtools_macos.XXXXXX.sh)

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
bash "$TEMP_INSTALLER" "$@"

# ---------------------------------------------------------
# POST-INSTALL: AI PLUGIN
# ---------------------------------------------------------
echo ""
echo ">>> Post-Install: Adding AI Plugin ($PLUGIN_NAME)..."

# Check if Eclipse is installed
if [ -d "$ECLIPSE_APP" ]; then

    # Make sure dropins folder exists
    if [ ! -d "$DROPINS_DIR" ]; then
        echo "  Creating dropins directory..."
        sudo mkdir -p "$DROPINS_DIR"
    fi

    # Download to a temporary location first
    TMP_JAR=$(mktemp)
    echo "  Downloading from $PLUGIN_URL..."

    # Move to dropin folder if succesful download
    if curl -fL "$PLUGIN_URL" -o "$TMP_JAR"; then
        echo "  Installing to $DROPINS_DIR..."
        sudo mv "$TMP_JAR" "$OUTPUT_JAR"
        sudo chmod 644 "$OUTPUT_JAR"
        echo "  [OK] AI Plugin installed successfully: $OUTPUT_JAR"

    # Otherwise, delete the temporary folder
    else
        echo "  [ERROR] Failed to download plugin."
        rm -f "$TMP_JAR"
        exit 1
    fi
else
    echo "  [ERROR] Eclipse directory ($ECLIPSE_DIR) not found. The main installation may have failed."
    exit 1
fi

echo ">>> Setup complete."