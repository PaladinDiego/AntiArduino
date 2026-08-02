<#
.SYNOPSIS
    Validacion previa al ciclo compilar/subir/monitorear.

.DESCRIPTION
    Responde tres preguntas en un solo paso:
      1. Esta PlatformIO Core accesible y sano?
      2. Que entornos declara el platformio.ini de este proyecto?
      3. Que placas hay conectadas y en que puerto COM?

    Salida ASCII pura ([OK]/[WARN]/[FAIL]) para no romper cp1252.

.EXAMPLE
    .\preflight.ps1
    .\preflight.ps1 -WorkDir C:\embedded-dev\mi-proyecto -Json
#>
[CmdletBinding()]
param(
    [string]$WorkDir = (Get-Location).Path,
    [switch]$Json
)

$ErrorActionPreference = "Continue"

$result = [ordered]@{
    PioExe       = $null
    PioVersion   = $null
    PythonOfPio  = $null
    Environments = @()
    Ports        = @()
    Warnings     = @()
    Ok           = $false
}

# --------------------------------------------------------------------------
# 1. PlatformIO Core
# --------------------------------------------------------------------------
$pioExe = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\pio.exe"
if (-not (Test-Path $pioExe)) {
    if (-not $Json) {
        Write-Host "[FAIL] pio.exe no encontrado en $pioExe"
        Write-Host "       Ejecuta antigravity-setup.ps1 primero."
    }
    $result.Warnings += "pio.exe ausente"
    if ($Json) { $result | ConvertTo-Json -Depth 5 }
    exit 1
}

$result.PioExe = $pioExe
$result.PythonOfPio = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\python.exe"

try {
    $ver = (& $pioExe --version 2>&1 | Out-String).Trim()
    $result.PioVersion = $ver
    if (-not $Json) { Write-Host "[OK] $ver" }
}
catch {
    if (-not $Json) { Write-Host "[FAIL] pio.exe existe pero no ejecuta: $_" }
    $result.Warnings += "pio.exe no ejecutable"
}

# --------------------------------------------------------------------------
# 2. Entornos declarados en platformio.ini
# --------------------------------------------------------------------------
$iniPath = Join-Path $WorkDir "platformio.ini"
if (Test-Path $iniPath) {
    $envs = Select-String -Path $iniPath -Pattern '^\s*\[env:(.+?)\]' -AllMatches |
        ForEach-Object { $_.Matches.Groups[1].Value }
    $result.Environments = @($envs)
    if (-not $Json) {
        if ($envs) {
            Write-Host "[OK] Entornos en platformio.ini: $($envs -join ', ')"
        }
        else {
            Write-Host "[WARN] platformio.ini sin secciones [env:*]."
        }
    }
}
else {
    if (-not $Json) { Write-Host "[WARN] No hay platformio.ini en $WorkDir" }
    $result.Warnings += "sin platformio.ini"
}

# --------------------------------------------------------------------------
# 3. Puertos COM
# --------------------------------------------------------------------------
try {
    $devicesRaw = & $pioExe device list --json-output 2>&1 | Out-String
    $devices = $devicesRaw | ConvertFrom-Json
    foreach ($d in $devices) {
        $result.Ports += [ordered]@{
            Port        = $d.port
            Description = $d.description
            Hwid        = $d.hwid
        }
    }
}
catch {
    $result.Warnings += "pio device list fallo"
}

if (-not $Json) {
    if ($result.Ports.Count -eq 0) {
        Write-Host "[WARN] Ningun puerto COM detectado."
        Write-Host "       Causas por probabilidad real:"
        Write-Host "         1. Cable USB de solo carga (sin lineas de datos)"
        Write-Host "         2. Driver ausente (CP210x / CH340 / FTDI)"
        Write-Host "         3. Placa en modo boot o colgada"
        Write-Host "       NO fijes upload_port manualmente para 'arreglar' esto."
    }
    else {
        Write-Host "[OK] Puertos detectados:"
        foreach ($p in $result.Ports) {
            Write-Host ("     {0,-6} {1}" -f $p.Port, $p.Description)
        }
    }
}

# --------------------------------------------------------------------------
# 4. Monitor serial en curso?
# --------------------------------------------------------------------------
$pidFile = Join-Path $WorkDir ".antigravity-embedded\serial_monitor.pid"
if (Test-Path $pidFile) {
    try {
        $info = Get-Content $pidFile -Raw | ConvertFrom-Json
        if (Get-Process -Id $info.Pid -ErrorAction SilentlyContinue) {
            if (-not $Json) {
                Write-Host "[WARN] Monitor serial ACTIVO (PID $($info.Pid), $($info.Tag))."
                Write-Host "       Cierralo con stop_serial_monitor.ps1 antes de subir."
            }
            $result.Warnings += "monitor activo"
        }
    }
    catch { }
}

$result.Ok = ($result.Warnings.Count -eq 0)

if ($Json) {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Host ""
    if ($result.Ok) { Write-Host "[OK] Preflight limpio." }
    else { Write-Host "[WARN] Preflight con avisos: $($result.Warnings -join '; ')" }
}

exit 0
