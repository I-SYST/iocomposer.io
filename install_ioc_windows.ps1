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
$IocomposerDir    = "$env:USERPROFILE\iocomposer"
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
function Rename-EclipseToIOcomposer {
    $src = $EclipseDir
    $dst = $IocomposerDir

    if (Test-Path $src) {
        if (Test-Path $dst) {
            Write-Host "  Removing old iocomposer directory..."
            Remove-Item -Recurse -Force $dst
        }
        Write-Host "  Renaming $src to $dst..."
        Move-Item -Path $src -Destination $dst
        Write-Host "  [OK] Renamed." -ForegroundColor Green
        $script:EclipseDir  = $dst
        $script:DropinsDir  = "$dst\dropins"
    } elseif (Test-Path $dst) {
        Write-Host "  IOcomposer directory already exists."
        $script:EclipseDir  = $dst
        $script:DropinsDir  = "$dst\dropins"
    } else {
        Write-Host "  [WARN] Eclipse directory not found." -ForegroundColor Yellow
        return
    }

    # Add -name IOcomposer to eclipse.ini
    $ini = "$($script:EclipseDir)\eclipse.ini"
    if (Test-Path $ini) {
        $lines = Get-Content $ini
        if (-not ($lines -contains "-name")) {
            $out = [System.Collections.Generic.List[string]]::new()
            $done = $false
            foreach ($line in $lines) {
                if (-not $done -and $line.Trim() -eq "-vmargs") {
                    $out.Add("-name"); $out.Add("IOcomposer")
                    $done = $true
                }
                $out.Add($line)
            }
            Set-Content -Path $ini -Value $out -Encoding UTF8
            Write-Host "  [OK] eclipse.ini: added -name IOcomposer" -ForegroundColor Green
        }
    }

    # Rename Start Menu shortcut
    $shortcuts = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu" `
        -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "(?i)eclipse" }
    foreach ($lnk in $shortcuts) {
        $newPath = $lnk.FullName -replace "(?i)eclipse","IOcomposer"
        try { Rename-Item $lnk.FullName (Split-Path $newPath -Leaf) -ErrorAction SilentlyContinue } catch {}
    }
}

function Rename-EclipseToIOcomposer {
    param([string]$EclDir)

    # Add -name IOcomposer to eclipse.ini before -vmargs
    $ini = "$EclDir\eclipse.ini"
    if (Test-Path $ini) {
        $lines = Get-Content $ini
        if (-not ($lines -contains "-name")) {
            $out = [System.Collections.Generic.List[string]]::new()
            $done = $false
            foreach ($line in $lines) {
                if (-not $done -and $line.Trim() -eq "-vmargs") {
                    $out.Add("-name"); $out.Add("IOcomposer")
                    $done = $true
                }
                $out.Add($line)
            }
            Set-Content -Path $ini -Value $out -Encoding UTF8
            Write-Host "  [OK] eclipse.ini: added -name IOcomposer" -ForegroundColor Green
        } else {
            Write-Host "  eclipse.ini -name already set."
        }
    } else {
        Write-Host "  [WARN] eclipse.ini not found." -ForegroundColor Yellow
    }

    # Patch eclipse.exe manifest app title via resource hacking is not feasible without tools.
    # Instead patch any .desktop-equivalent: the Windows shortcut if found.
    $shortcuts = Get-ChildItem -Path "$env:APPDATA\Microsoft\Windows\Start Menu" `
        -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "(?i)eclipse" }
    foreach ($lnk in $shortcuts) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $sc = $shell.CreateShortcut($lnk.FullName)
            $sc.Description = "IOcomposer IDE"
            $sc.Save()
            # Rename the .lnk file itself
            $newName = $lnk.FullName -replace "(?i)eclipse","IOcomposer"
            if ($newName -ne $lnk.FullName) {
                Rename-Item -Path $lnk.FullName -NewName (Split-Path $newName -Leaf) -ErrorAction SilentlyContinue
            }
            Write-Host "  [OK] Patched shortcut: $($lnk.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Could not patch shortcut: $($lnk.Name)" -ForegroundColor Yellow
        }
    }

    Write-Host "  [OK] Rename complete." -ForegroundColor Green
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

function Install-Splash {
    param([string]$Src, [string]$EclDir)
    $installed = $false
    Write-Host "  Searching for existing splash.bmp files..."
    Get-ChildItem -Path $EclDir -Recurse -Filter "splash.bmp" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "  Found: $($_.FullName)"
        try {
            Copy-Item -Path $Src -Destination $_.FullName -Force
            Write-Host "  [OK] Replaced: $($_.FullName)" -ForegroundColor Green
            $installed = $true
        } catch { Write-Host "  [WARN] Could not replace: $($_.FullName)" -ForegroundColor Yellow }
    }
    Write-Host "  Writing to all known splash locations..."
    $targets = @("$EclDir\splash.bmp")
    Get-ChildItem -Path $EclDir -Recurse -Directory -Filter "org.eclipse.epp.package.*" -ErrorAction SilentlyContinue |
    ForEach-Object { $targets += "$($_.FullName)\splash.bmp" }
    foreach ($dst in $targets) {
        $dir = Split-Path $dst -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        try {
            Copy-Item -Path $Src -Destination $dst -Force
            Write-Host "  [OK] Written: $dst" -ForegroundColor Green
            $installed = $true
        } catch {}
    }
    if ($installed) { Write-Host "  [OK] Splash installation complete." -ForegroundColor Green }
    else            { Write-Host "  [WARN] Could not write splash to any location." -ForegroundColor Yellow }
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

$SplashUrl = "https://raw.githubusercontent.com/$PluginRepo/$PluginBranch/$PluginDirPath/splash.bmp"
$SplashTmp = [System.IO.Path]::GetTempFileName() + ".bmp"
Write-Host "  Downloading: $SplashUrl"
try {
    Invoke-WebRequest -Uri $SplashUrl -OutFile $SplashTmp -ErrorAction Stop
    $size = (Get-Item $SplashTmp).Length
    Write-Host "  [OK] splash.bmp downloaded ($size bytes)" -ForegroundColor Green
    Install-Splash -Src $SplashTmp -EclDir $EclipseDir
    Remove-Item $SplashTmp -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "  [WARN] Download failed: $_" -ForegroundColor Yellow
    $SplashLocal = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "splash.bmp"
    if (Test-Path $SplashLocal) {
        Write-Host "  Falling back to local splash.bmp"
        Install-Splash -Src $SplashLocal -EclDir $EclipseDir
    } else {
        Write-Host "  [WARN] No splash.bmp available — skipping." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------
# POST-INSTALL: RENAME TO IOCOMPOSER
# ---------------------------------------------------------
Write-Host ""
Write-Host ">>> Renaming Eclipse to IOcomposer..." -ForegroundColor Cyan
if (Test-Path $EclipseDir) {
    Rename-EclipseToIOcomposer -EclDir $EclipseDir
} else {
    Write-Host "  [WARN] Eclipse directory not found — skipping rename." -ForegroundColor Yellow
}

# ---------------------------------------------------------
# POST-INSTALL: RENAME TO IOCOMPOSER
# ---------------------------------------------------------
Write-Host ""
Write-Host ">>> Renaming Eclipse to IOcomposer..." -ForegroundColor Cyan
Rename-EclipseToIOcomposer
$OutputJar   = "$DropinsDir\com.iocomposer.embedcdt.ai.jar"
$UiOutputJar = "$DropinsDir\com.iocomposer.embedcdt.ui.jar"
Write-Host "  Target: $EclipseDir"

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