# IOcomposer website launcher for Windows.
# Installation, plugins, branding, preferences and builds are managed
# exclusively by IOsonata/IOsonata/Installer.
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$InstallerArgs
)

$ErrorActionPreference = 'Stop'
$installerRef = $env:IOSONATA_INSTALLER_REF
if (-not $installerRef) { $installerRef = 'main' }
$url = "https://raw.githubusercontent.com/IOsonata/IOsonata/$installerRef/Installer/install_iocdevtools_win.ps1"
$stage = Join-Path $env:TEMP ("install_iocdevtools_win_" + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    Write-Host "Downloading IOcomposer Windows installer from IOsonata ($installerRef)..."
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $stage
    # Run as a script, not Invoke-Expression; preserve arguments and the exit status.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stage @InstallerArgs
    $status = $LASTEXITCODE
    if ($null -eq $status) { $status = 1 }
    exit $status
} catch {
    Write-Error "IOcomposer installer failed: $_"
    exit 1
} finally {
    Remove-Item $stage -Force -ErrorAction SilentlyContinue
}
