# IOcomposer Installer for Windows
# https://iocomposer.io

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  IOcomposer Installer for Windows" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IOcomposer is currently in preview."
Write-Host "The installer is not yet available."
Write-Host ""
Write-Host "To join the preview, contact: info@i-syst.com"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

# Run the main installer from the IOSonata Library
Write-Host ">>> Launching Main Installer..." -ForegroundColor Cyan
iwr -useb https://raw.githubusercontent.com/IOsonata/IOsonata/refs/heads/master/Installer/install_iocdevtools_win.ps1 | iex

# Install IOComposer AI manually
$EclipseDropins = "$env:ProgramFiles\Eclipse Embedded CDT\dropins"
$PluginName     = "com.iocomposer.embedcdt.ai"
$PluginUrl      = "https://github.com/I-SYST/iocomposer.io/raw/main/plugin/com.iocomposer.embedcdt.ai_0.0.22.jar"
$OutputJar      = "$EclipseDropins\com.iocomposer.embedcdt.ai.jar"

Write-Host "\n>>> Post-Install: Adding AI Plugin ($PluginName)..." -ForegroundColor Cyan

# Check if the dropins directory is present, and then installs it there
if (Test-Path $EclipseDropins) {
    try {
        Invoke-WebRequest -Uri $PluginUrl -OutFile $OutputJar -ErrorAction Stop
        Write-Host "    [OK] AI Plugin installed successfully: "
    } catch {
        Write-Host "    [ERROR] Failed to download plugin with $PluginUrl" -ForegroundColor Red
        Write-Host "    Error details: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "    [ERROR] Eclipse 'dropins' folder not found. The main installation may have failed." -ForegroundColor Red
}

Write-Host ">>> Setup complete." -ForegroundColor Green
