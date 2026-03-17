# IOcomposer Installer for Windows
# https://iocomposer.io

# ---------------------------------------------------------
# BANNER
# ---------------------------------------------------------
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  IOcomposer Installer for Windows" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

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

$UiPluginId     = "com.iocomposer.embedcdt.ui"
$UiOutputJar    = "$DropinsDir\com.iocomposer.embedcdt.ui.jar"

$InstallerUrl = "https://raw.githubusercontent.com/IOsonata/IOsonata/master/Installer/install_iocdevtools_win.ps1"

# SDK root (where IOsonata/external live). Default matches the main installer.
$SdkRoot = "$env:USERPROFILE\IOcomposer"

# Parse --home <path> argument
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "--home" -and ($i + 1) -lt $args.Count) {
        $SdkRoot = $args[$i + 1]
        break
    }
}

# Skip post-install steps for non-install flows
$SkipPost = $false
foreach ($a in $args) {
    if ($a -eq "--uninstall" -or $a -eq "--help" -or $a -eq "--version") {
        $SkipPost = $true
        break
    }
}

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
    param([string]$Id = $PluginId)
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
        if ($name -notmatch "^$([regex]::Escape($Id))_(.+)\.jar$") { continue }
        
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
function Patch-EclipseIni {
    $ini    = "$EclipseDir\eclipse.ini"
    $custom = "$DropinsDir\iocomposer_customization.ini"
    $content = @(
        "# IOcomposer preference customization",
        "org.eclipse.ui/showIntro=false",
        "org.eclipse.ui/defaultPerspectiveId=com.iocomposer.embedcdt.ui.perspective",
        "org.eclipse.epp.package.embedcpp/showNewsOnStartup=false",
        "org.eclipse.epp.package.embedcpp.ui/showNewsOnStartup=false",
        "org.eclipse.epp.package.cpp/showNewsOnStartup=false",
        "org.eclipse.epp.package.common/showNewsOnStartup=false",
        "org.eclipse.epp.mpc.ui/showNewsOnStartup=false"
    )
    Set-Content -Path $custom -Value $content -Encoding UTF8
    Write-Host "  Written: $custom"
    if (-not (Test-Path $ini)) { Write-Host "  [WARN] eclipse.ini not found."; return }
    $raw = Get-Content $ini -Raw
    if ($raw -match "iocomposer_customization.ini") { Write-Host "  eclipse.ini already patched."; return }
    $lines = Get-Content $ini
    $out = [System.Collections.Generic.List[string]]::new()
    $done = $false
    foreach ($line in $lines) {
        if (-not $done -and $line.Trim() -eq "-vmargs") {
            $out.Add("-pluginCustomization"); $out.Add($custom)
            $out.Add("-vmargs")
            $done = $true; continue
        }
        $out.Add($line)
    }
    if (-not $done) { $out.Add("-pluginCustomization"); $out.Add($custom) }
    Set-Content -Path $ini -Value $out -Encoding UTF8
    Write-Host "  Patched: $ini"
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

# If we ran a non-install flow (uninstall/help/version), do not attempt post-install steps.
if ($SkipPost) {
    Write-Host ""
    Write-Host ">>> Skipping post-install steps." -ForegroundColor Cyan
    exit 0
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

# ---------------------------------------------------------
# POST-INSTALL: UI PLUGIN
# ---------------------------------------------------------
Write-Host ""
Write-Host ">>> Post-Install: Adding UI Plugin ($UiPluginId)..." -ForegroundColor Cyan

if (Test-Path $EclipseDir) {
    if (-not (Test-Path $DropinsDir)) { New-Item -ItemType Directory -Path $DropinsDir -Force | Out-Null }
    $UiUrl = Discover-LatestPluginUrl -Id $UiPluginId
    if ($UiUrl) {
        Write-Host "  Latest UI plugin URL: $UiUrl"
        try {
            Invoke-WebRequest -Uri $UiUrl -OutFile $UiOutputJar -ErrorAction Stop
            Write-Host "  [OK] UI Plugin installed: $UiOutputJar" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Failed to download UI plugin." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARN] Failed to discover UI plugin JAR." -ForegroundColor Yellow
    }
    Write-Host ">>> Patching eclipse.ini for IOcomposer preferences..." -ForegroundColor Cyan
    Patch-EclipseIni
} else {
    Write-Host "  [ERROR] Eclipse directory not found." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------
# POST-INSTALL: SPLASH SCREEN
# ---------------------------------------------------------
Write-Host ""
Write-Host ">>> Installing IOcomposer splash screen..." -ForegroundColor Cyan
$SplashSrc = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "splash.bmp"

if (Test-Path $SplashSrc) {
    Write-Host "  Searching for splash targets..."
    $Installed = $false
    Get-ChildItem -Path $EclipseDir -Recurse -Filter "splash.bmp" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "  Found: $($_.FullName)"
        try {
            Copy-Item -Path $SplashSrc -Destination $_.FullName -Force
            Write-Host "  [OK] Replaced: $($_.Directory.Name)/splash.bmp" -ForegroundColor Green
            $Installed = $true
        } catch { Write-Host "  [WARN] Could not replace: $($_.FullName)" -ForegroundColor Yellow }
    }
    if (-not $Installed) {
        Write-Host "  [WARN] No splash.bmp found — trying fallback..." -ForegroundColor Yellow
        try { Copy-Item -Path $SplashSrc -Destination "$EclipseDir\splash.bmp" -Force
              Write-Host "  Copied to eclipse root." } catch {}
    }
} else {
    Write-Host "  [WARN] splash.bmp not found next to installer - skipping." -ForegroundColor Yellow
}

# ---------------------------------------------------------
# POST-INSTALL: Build External SDK Index (RAG)
# ---------------------------------------------------------
Write-Host ""
Write-Host ">>> Post-Install: Building external SDK index..." -ForegroundColor Cyan

$IndexScript = "$SdkRoot\IOsonata\Installer\build_external_index.py"
$ExternalSdkPath = "$SdkRoot\external"

if (Test-Path $IndexScript) {
    # Check if python is available
    if (Get-Command "python" -ErrorAction SilentlyContinue) {
        Write-Host "  Running: python $IndexScript --sdk-root $ExternalSdkPath"
        
        # Execute Python script and check the exit code ($LASTEXITCODE)
        & python "$IndexScript" --sdk-root "$ExternalSdkPath"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] External SDK index built." -ForegroundColor Green
        } else {
            Write-Host "  [WARNING] External SDK index build failed." -ForegroundColor Yellow
            Write-Host "     You can retry manually with:" -ForegroundColor Yellow
            Write-Host "     python `"$IndexScript`" --sdk-root `"$ExternalSdkPath`"" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARNING] 'python' command not found. Skipping external SDK index build." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [WARNING] Index script not found at: $IndexScript" -ForegroundColor Yellow
    Write-Host "     Skipping external SDK index build." -ForegroundColor Yellow
}

Write-Host ""
Write-Host ">>> Setup complete." -ForegroundColor Green