<#
.SYNOPSIS
    Cierra el monitor serial abierto por open_serial_monitor.ps1 y libera el
    puerto COM.

.DESCRIPTION
    Nunca mata procesos por nombre (pio/python): eso rompe compilaciones en
    curso. Estrategia en tres capas:
      1. Mata el arbol de procesos del PID registrado (hijos primero).
      2. Barrido de seguridad: busca por linea de comando cualquier
         'device monitor' asociado a este WorkDir o puerto.
      3. Verifica que el puerto COM quedo realmente libre.

.EXAMPLE
    .\stop_serial_monitor.ps1
    .\stop_serial_monitor.ps1 -Port COM9
#>
[CmdletBinding()]
param(
    [string]$WorkDir = (Get-Location).Path,
    [string]$Port,
    [switch]$Quiet
)

$ErrorActionPreference = "SilentlyContinue"

function Write-Line($msg) { if (-not $Quiet) { Write-Host $msg } }

$WorkDir = (Resolve-Path $WorkDir).Path
$stateDir = Join-Path $WorkDir ".antigravity-embedded"
$pidFile = Join-Path $stateDir "serial_monitor.pid"

# --------------------------------------------------------------------------
# 1. Matar arbol de procesos del PID registrado
# --------------------------------------------------------------------------
function Stop-ProcessTree($targetPid) {
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$targetPid" -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        Stop-ProcessTree $child.ProcessId
    }
    $proc = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
        return $true
    }
    return $false
}

$killed = 0

if (Test-Path $pidFile) {
    try {
        $info = Get-Content $pidFile -Raw | ConvertFrom-Json
        if (-not $Port -and $info.Tag -match '^COM\d+$') { $Port = $info.Tag }
        if (Stop-ProcessTree $info.Pid) {
            Write-Line "[OK] Monitor serial cerrado (PID $($info.Pid), $($info.Tag))."
            $killed++
        }
        else {
            Write-Line "[INFO] El PID $($info.Pid) ya no existia (cerrado manualmente)."
        }
    }
    catch {
        Write-Line "[WARN] serial_monitor.pid ilegible. Paso al barrido por linea de comando."
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
else {
    Write-Line "[INFO] No hay monitor registrado en $pidFile."
}

# --------------------------------------------------------------------------
# 2. Barrido de seguridad por linea de comando
# --------------------------------------------------------------------------
$escapedWorkDir = $WorkDir.Replace('\', '\\')
$candidates = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -and
        $_.CommandLine -like '*device monitor*' -and
        ($_.CommandLine -like "*$WorkDir*" -or
         $_.CommandLine -like "*$escapedWorkDir*" -or
         ($Port -and $_.CommandLine -like "*$Port*"))
    }

foreach ($c in $candidates) {
    Write-Line "[OK] Monitor huerfano encontrado (PID $($c.ProcessId)). Cerrando."
    Stop-ProcessTree $c.ProcessId | Out-Null
    $killed++
}

Start-Sleep -Milliseconds 400

# --------------------------------------------------------------------------
# 3. Limpieza de lanzadores y tareas huerfanas
# --------------------------------------------------------------------------
Get-ChildItem -Path $stateDir -Filter "run_AG_Serial_*.ps1" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$stale = schtasks /query /fo csv /nh 2>$null | Where-Object { $_ -like '*AG_Serial_*' }
foreach ($line in $stale) {
    $name = ($line -split '","')[0].Trim('"')
    if ($name) { schtasks /delete /tn $name /f 2>&1 | Out-Null }
}

# --------------------------------------------------------------------------
# 4. Verificar que el puerto quedo libre
# --------------------------------------------------------------------------
if ($Port) {
    $free = $false
    try {
        $sp = New-Object System.IO.Ports.SerialPort $Port
        $sp.Open()
        $sp.Close()
        $sp.Dispose()
        $free = $true
    }
    catch { $free = $false }

    if ($free) {
        Write-Line "[OK] $Port libre. Listo para compilar/subir."
    }
    else {
        Write-Line "[WARN] $Port sigue ocupado. Revisa el plotter web o el monitor de PlatformIO IDE."
        exit 1
    }
}
else {
    Write-Line "[OK] Puerto liberado. Listo para compilar/subir."
}

exit 0
