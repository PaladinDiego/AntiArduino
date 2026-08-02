<#
.SYNOPSIS
    Abre el monitor serial de PlatformIO en un proceso totalmente desvinculado
    del arbol de procesos del IDE (via Programador de Tareas de Windows), para
    que Antigravity no lo mate al reciclar la terminal (Job Object bug).

.DESCRIPTION
    Modos disponibles:
      Interactive (por defecto) - Ventana visible, teclado habilitado.
                                  Respeta monitor_filters de platformio.ini
                                  (incluido send_on_enter).
      Logged                    - Ventana visible + --filter log2file.
                                  OJO: log2file DESHABILITA send_on_enter, el
                                  firmware debe leer caracter por caracter.
      Background                - Sin ventana, salida espejada a
                                  .antigravity-embedded\logs\monitor_*.log
                                  Pensado para que el agente IA lea la salida.

.EXAMPLE
    .\open_serial_monitor.ps1 -Port COM9 -Baud 115200
    .\open_serial_monitor.ps1 -Env uno
    .\open_serial_monitor.ps1 -Env esp32dev -Mode Background
#>
[CmdletBinding()]
param(
    [string]$Port,
    [int]$Baud = 115200,
    [Alias("PioEnv")]
    [string]$Env = "",
    [ValidateSet("Interactive", "Logged", "Background")]
    [string]$Mode = "Interactive",
    [string]$WorkDir = (Get-Location).Path,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# --------------------------------------------------------------------------
# Validacion de entrada
# --------------------------------------------------------------------------
if (-not $Port -and -not $Env) {
    Write-Host "[FAIL] Debes indicar -Port (ej. COM9) o -Env (ej. uno)."
    exit 1
}

$pioExe = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\pio.exe"
if (-not (Test-Path $pioExe)) {
    Write-Host "[FAIL] No se encontro pio.exe en $pioExe"
    Write-Host "       Ejecuta antigravity-setup.ps1 para instalar PlatformIO Core."
    exit 1
}

$WorkDir = (Resolve-Path $WorkDir).Path
$stateDir = Join-Path $WorkDir ".antigravity-embedded"
$logDir = Join-Path $stateDir "logs"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$pidFile = Join-Path $stateDir "serial_monitor.pid"
$tag = if ($Port) { $Port } else { $Env }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# --------------------------------------------------------------------------
# Idempotencia: si ya hay un monitor vivo con el mismo tag, no abrir otro
# --------------------------------------------------------------------------
if ((Test-Path $pidFile) -and (-not $Force)) {
    try {
        $existing = Get-Content $pidFile -Raw | ConvertFrom-Json
        $existingProc = Get-Process -Id $existing.Pid -ErrorAction SilentlyContinue
        if ($existingProc -and $existing.Tag -eq $tag) {
            Write-Host "[OK] Ya hay un monitor serial abierto para '$tag' (PID $($existing.Pid))."
            Write-Host "     Usa -Force para reabrirlo, o stop_serial_monitor.ps1 para cerrarlo."
            exit 0
        }
    }
    catch {
        # PID file corrupto: lo ignoramos y seguimos
    }
}

# Si quedo un registro huerfano, limpiarlo antes de continuar
if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }

# --------------------------------------------------------------------------
# Construccion de argumentos de PlatformIO
# --------------------------------------------------------------------------
if ($Port) {
    $pioArgs = "device monitor -p $Port -b $Baud"
}
else {
    $pioArgs = "device monitor -e $Env"
}

$logFile = Join-Path $logDir "monitor_${tag}_$timestamp.log"

if ($Mode -eq "Logged") {
    $pioArgs = "$pioArgs --filter log2file"
    $logFile = "(generado por PlatformIO en la raiz del proyecto: platformio-device-monitor-*.log)"
}

# --------------------------------------------------------------------------
# Lanzador temporal: se ejecuta FUERA del Job Object del IDE
# --------------------------------------------------------------------------
$taskName = "AG_Serial_$((New-Guid).Guid.Substring(0,8))"
$tempScript = Join-Path $stateDir "run_$taskName.ps1"

$launcherTemplate = @'
# Lanzador generado automaticamente por open_serial_monitor.ps1
# Se ejecuta desde el Programador de Tareas para escapar del Job Object del IDE.
$ErrorActionPreference = "Stop"
$pioExe   = '__PIOEXE__'
$pioArgs  = '__PIOARGS__'
$workDir  = '__WORKDIR__'
$pidFile  = '__PIDFILE__'
$tag      = '__TAG__'
$mode     = '__MODE__'
$logFile  = '__LOGFILE__'

if ($mode -eq 'Background') {
    # Sin ventana: PowerShell hospeda a pio y espeja la salida al log
    $inner = "& '$pioExe' $pioArgs 2>&1 | Tee-Object -FilePath '$logFile'"
    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', $inner `
        -WorkingDirectory $workDir -WindowStyle Hidden -PassThru
}
else {
    # Ventana visible e interactiva: pio.exe es el proceso directo
    $proc = Start-Process -FilePath $pioExe -ArgumentList $pioArgs `
        -WorkingDirectory $workDir -WindowStyle Normal -PassThru
}

$info = [ordered]@{
    Pid       = $proc.Id
    Tag       = $tag
    Mode      = $mode
    LogFile   = $logFile
    WorkDir   = $workDir
    StartedAt = (Get-Date).ToString('o')
}
$info | ConvertTo-Json | Set-Content -Path $pidFile -Encoding UTF8
'@

$launcher = $launcherTemplate.
    Replace('__PIOEXE__', $pioExe).
    Replace('__PIOARGS__', $pioArgs).
    Replace('__WORKDIR__', $WorkDir).
    Replace('__PIDFILE__', $pidFile).
    Replace('__TAG__', $tag).
    Replace('__MODE__', $Mode).
    Replace('__LOGFILE__', $logFile)

Set-Content -Path $tempScript -Value $launcher -Encoding UTF8

# --------------------------------------------------------------------------
# Registrar, ejecutar y borrar la tarea programada
# --------------------------------------------------------------------------
$trCommand = "powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempScript`""

try {
    schtasks /create /tn $taskName /tr $trCommand /sc once /st 00:00 /f | Out-Null
    schtasks /run /tn $taskName | Out-Null
}
catch {
    Write-Host "[FAIL] No se pudo registrar la tarea programada: $_"
    Write-Host "       Revisa si una politica de grupo bloquea schtasks."
    exit 1
}

# Esperar a que el lanzador escriba el PID (hasta 10 s)
$deadline = (Get-Date).AddSeconds(10)
while ((-not (Test-Path $pidFile)) -and ((Get-Date) -lt $deadline)) {
    Start-Sleep -Milliseconds 250
}

schtasks /delete /tn $taskName /f 2>&1 | Out-Null

if (-not (Test-Path $pidFile)) {
    Write-Host "[WARN] La tarea se ejecuto pero no se registro el PID."
    Write-Host "       Causas probables: sesion no interactiva, o politica de grupo."
    Write-Host "       Lanzador usado: $tempScript"
    exit 1
}

$info = Get-Content $pidFile -Raw | ConvertFrom-Json
Write-Host "[OK] Monitor serial abierto (modo $Mode) para '$tag'. PID $($info.Pid)."

switch ($Mode) {
    "Background" {
        Write-Host "     Log espejo: $($info.LogFile)"
        Write-Host "     Leelo con:  Get-Content '$($info.LogFile)' -Tail 20 -Wait"
    }
    "Logged" {
        Write-Host "     PlatformIO escribe platformio-device-monitor-*.log en el proyecto."
        Write-Host "     [WARN] --filter log2file deshabilita send_on_enter."
    }
    default {
        Write-Host "     Ventana interactiva abierta. Cierra con stop_serial_monitor.ps1."
    }
}
