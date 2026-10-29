# IOcomposer website launcher for Windows.
# Installation, plugins, branding, preferences and builds are managed
# exclusively by IOsonata/IOsonata/Installer.
$ErrorActionPreference = 'Stop'
$installerRef = $env:IOSONATA_INSTALLER_REF
if (-not $installerRef) { $installerRef = 'main' }
$url = "https://raw.githubusercontent.com/IOsonata/IOsonata/$installerRef/Installer/install_iocdevtools_win.ps1"
$stage = Join-Path $env:TEMP ("install_iocdevtools_win_" + [guid]::NewGuid().ToString('N') + '.ps1')

try {
    Write-Host "Downloading IOcomposer Windows installer from IOsonata ($installerRef)..."
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $stage
    # Run as a script, not Invoke-Expression; preserve arguments and the exit status.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Help and version only print information; no elevation is needed.
    $informational = @($args | Where-Object { $_ -in @('-Help', '-Version') }).Count -gt 0
    if ($isAdmin -or $informational) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stage @args
        $status = $LASTEXITCODE
    } else {
        # Preserve every argument when crossing the UAC elevation boundary.
        $payload = @{ script = $stage; arguments = @($args) } | ConvertTo-Json -Compress -Depth 4
        $encodedPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
        $command = '$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("' + $encodedPayload + '")); $data = $json | ConvertFrom-Json; $installerArgs = @($data.arguments); & $data.script @installerArgs; if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $process = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand)
        $status = $process.ExitCode
    }

    if ($null -eq $status) { $status = 1 }
    exit $status
} catch {
    Write-Error "IOcomposer installer failed: $_"
    exit 1
} finally {
    Remove-Item $stage -Force -ErrorAction SilentlyContinue
}
