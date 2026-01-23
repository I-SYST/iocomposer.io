#!/bin/bash
# IOcomposer Installer for Linux
# https://iocomposer.io

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

# Run the main installer from the IOSonata Library
echo ">>> Launching Main Installer..."
curl -fsSL https://raw.githubusercontent.com/IOsonata/IOsonata/refs/heads/master/Installer/install_iocdevtools_linux.sh | bash

# Install IOComposer AI manually
ECLIPSE_DIR="$HOME/eclipse"
DROPINS_DIR="$ECLIPSE_DIR/dropins"
PLUGIN_NAME="com.iocomposer.embedcdt.ai"
PLUGIN_URL="http://com.iocomposer.embedcdt.ai/"
OUTPUT_JAR="$DROPINS_DIR/com.iocomposer.embedcdt.ai.jar"

echo ""
echo ">>> Post-Install: Adding AI Plugin ($PLUGIN_NAME)..."

# Check if Eclipse is installed
if [ -d "ECLIPSE_DIR" ]; then

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