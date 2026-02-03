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

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
$EclipseDir     = "$env:ProgramFiles\Eclipse Embedded CDT"
$DropinsDir     = "$EclipseDir\dropins"

# AI Plugin Discovery
$PluginName     = "com.iocomposer.embedcdt.ai"
$PluginRepo     = "I-SYST/iocomposer.io"
$PluginBranch   = "main"
$PluginDirPath  = "plugin"
$PluginId       = "com.iocomposer.embedcdt.ai"
$PluginUrl      = $env:IOCOMPOSER_AI_PLUGIN_URL
$OutputJar      = "$DropinsDir\com.iocomposer.embedcdt.ai.jar"

$InstallerUrl   = "https://raw.githubusercontent.com/IOsonata/IOsonata/refs/heads/master/Installer/install_iocdevtools_win.ps1"

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
function Get-VersionKey {
    param([string]$Version)
    
    # Turn a dotted version like 0.0.22 into a lexicographically sortable key
    $parts = $Version -split '\.'
    $key = ""
    
    foreach ($p in $parts) {
        $key += $p.PadLeft(5, '0')
    }
    
    # Pad to 6 segments
    for ($i = $parts.Count; $i -lt 6; $i++) {
        $key += "00000"
    }
    
    return $key
}

function Discover-LatestPluginUrl {
    $api = "https://api.github.com/repos/$PluginRepo/contents/$PluginDirPath`?ref=$PluginBranch"
    
    try {
        $response = Invoke-RestMethod -Uri $api -Headers @{
            "Accept" = "application/vnd.github+json"
            "User-Agent" = "iocomposer-installer"
        } -ErrorAction Stop
    } catch {
        return $null
    }
    
    $bestFile = $null
    $bestKey = ""
    
    foreach ($item in $response) {
        $name = $item.name
        if (-not $name) { continue }
        
        # Match pattern: com.iocomposer.embedcdt.ai_*.jar
        if ($name -notmatch "^$([regex]::Escape($PluginId))_(.+)\.jar$") { continue }
        
        $ver = $Matches[1]
        
        # Accept numeric dotted versions like 0.0.22
        if ($ver -notmatch '^[0-9]+(\.[0-9]+)*$') { continue }
        
        $key = Get-VersionKey -Version $ver
        
        if (-not $bestKey -or $key -gt $bestKey) {
            $bestKey = $key
            $bestFile = $name
        }
    }
    
    if (-not $bestFile) { return $null }
    
    return "https://github.com/$PluginRepo/raw/$PluginBranch/$PluginDirPath/$bestFile"
}

# ---------------------------------------------------------
# DOWNLOAD AND RUN MAIN INSTALLER
# ---------------------------------------------------------
Write-Host ">>> Downloading Main Installer..." -ForegroundColor Cyan

try {
    Invoke-WebRequest -Uri $InstallerUrl -UseBasicParsing | Invoke-Expression
} catch {
    Write-Host "X Failed to download installer from:" -ForegroundColor Red
    Write-Host "   $InstallerUrl" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------
# POST-INSTALL: AI PLUGIN
# ---------------------------------------------------------
Write-Host ""
Write-Host ">>> Post-Install: Adding AI Plugin ($PluginName)..." -ForegroundColor Cyan

# Check if Eclipse is installed
if (Test-Path $EclipseDir) {

    # Make sure dropins folder exists
    if (-not (Test-Path $DropinsDir)) {
        Write-Host "  Creating dropins directory..."
        New-Item -ItemType Directory -Path $DropinsDir -Force | Out-Null
    }

    # Discover latest plugin URL if not overridden
    if (-not $PluginUrl) {
        Write-Host "  Discovering latest AI plugin from GitHub..."
        $PluginUrl = Discover-LatestPluginUrl
        
        if (-not $PluginUrl) {
            Write-Host "  [WARNING] Failed to discover latest plugin JAR for: $PluginId" -ForegroundColor Yellow
            Write-Host "     You can override by setting IOCOMPOSER_AI_PLUGIN_URL environment variable." -ForegroundColor Yellow
            Write-Host ">>> Setup complete (without AI plugin)." -ForegroundColor Green
            exit 0
        }
        Write-Host "  Latest plugin URL: $PluginUrl"
    } else {
        Write-Host "  Using overridden plugin URL: $PluginUrl"
    }

    # Download plugin
    Write-Host "  Downloading from $PluginUrl..."
    
    try {
        Invoke-WebRequest -Uri $PluginUrl -OutFile $OutputJar -ErrorAction Stop
        Write-Host "  [OK] AI Plugin installed successfully: $OutputJar" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Failed to download AI plugin (non-critical)." -ForegroundColor Yellow
        Write-Host "     The plugin may not be available yet or the URL has changed." -ForegroundColor Yellow
        Write-Host "     You can install it manually later from:" -ForegroundColor Yellow
        Write-Host "     $PluginUrl" -ForegroundColor Yellow
        # Don't exit with error - plugin is optional
    }

} else {
    Write-Host "  [ERROR] Eclipse directory ($EclipseDir) not found. The main installation may have failed." -ForegroundColor Red
    exit 1
}

Write-Host ">>> Setup complete." -ForegroundColor Green