<#
.SYNOPSIS
    Ciclo completo y seguro: cerrar monitor -> compilar -> subir -> reabrir
    monitor. Es el comando del 90% de los casos.

.DESCRIPTION
    El orden importa. En Windows el puerto COM es exclusivo: si el monitor
    esta abierto, el upload falla con "Access is denied". Por eso este script
    SIEMPRE cierra el monitor antes de tocar la placa y lo reabre despues.

.EXAMPLE
    .\flash_watch.ps1
    .\flash_watch.ps1 -Env uno
    .\flash_watch.ps1 -Env esp32dev -Port COM5 -Mode Background
    .\flash_watch.ps1 -Env uno -NoMonitor
#>
[CmdletBinding()]
param(
    [Alias("env")]
    [string]$Env = "",
    [Alias("port")]
    [string]$Port = "",
    [int]$Baud = 115200,
    [ValidateSet("Interactive", "Logged", "Background")]
    [string]$Mode = "Interactive",
    [string]$WorkDir = (Get-Location).Path,
    [switch]$NoMonitor,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$WorkDir = (Resolve-Path $WorkDir).Path

$pioExe = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\pio.exe"
if (-not (Test-Path $pioExe)) {
    Write-Host "[FAIL] pio.exe no encontrado en $pioExe"
    exit 1
}

Push-Location $WorkDir
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    # ----------------------------------------------------------------------
    # PASO 1 - Liberar el puerto COM
    # ----------------------------------------------------------------------
    Write-Host "=== [1/4] Cerrando monitor serial (liberar COM) ==="
    $stopScript = Join-Path $scriptDir "stop_serial_monitor.ps1"
    if (Test-Path $stopScript) {
        & $stopScript -WorkDir $WorkDir -Quiet
    }
    else {
        Write-Host "[WARN] stop_serial_monitor.ps1 no encontrado junto a este script."
    }

    # ----------------------------------------------------------------------
    # PASO 2 - Compilar
    # ----------------------------------------------------------------------
    Write-Host "=== [2/4] Compilando ==="
    $buildArgs = @("run")
    if ($Env) { $buildArgs += @("-e", $Env) }

    & $pioExe @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Compilacion fallida. Revisa la PRIMERA linea con 'error:'."
        exit 1
    }
    Write-Host "[OK] Compilacion exitosa."

    if ($BuildOnly) {
        Write-Host "[OK] -BuildOnly activo. Fin."
        exit 0
    }

    # ----------------------------------------------------------------------
    # PASO 3 - Subir
    # ----------------------------------------------------------------------
    Write-Host "=== [3/4] Subiendo firmware ==="
    $uploadArgs = @("run", "-t", "upload")
    if ($Env) { $uploadArgs += @("-e", $Env) }
    if ($Port) { $uploadArgs += @("--upload-port", $Port) }

    & $pioExe @uploadArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Upload fallido."
        Write-Host "       Si dice 'Please specify upload_port': Windows no ve la placa."
        Write-Host "       Revisa cable de datos, driver y modo boot (en ese orden)."
        Write-Host "       Si dice 'Access is denied': algo mas tiene el COM abierto."
        exit 1
    }
    Write-Host "[OK] Upload completado."

    # ----------------------------------------------------------------------
    # PASO 4 - Reabrir monitor
    # ----------------------------------------------------------------------
    if ($NoMonitor) {
        Write-Host "=== [4/4] -NoMonitor activo, no se reabre el monitor ==="
    }
    else {
        Write-Host "=== [4/4] Reabriendo monitor serial ==="
        $openScript = Join-Path $scriptDir "open_serial_monitor.ps1"
        if (Test-Path $openScript) {
            $openArgs = @{ WorkDir = $WorkDir; Mode = $Mode; Baud = $Baud }
            if ($Port) { $openArgs["Port"] = $Port }
            elseif ($Env) { $openArgs["Env"] = $Env }
            & $openScript @openArgs
        }
        else {
            Write-Host "[WARN] open_serial_monitor.ps1 no encontrado."
        }
    }

    $sw.Stop()
    Write-Host ""
    Write-Host "=== RESUMEN ==="
    Write-Host ("  Entorno : {0}" -f $(if ($Env) { $Env } else { "(default de platformio.ini)" }))
    Write-Host ("  Puerto  : {0}" -f $(if ($Port) { $Port } else { "(autodeteccion)" }))
    Write-Host ("  Compilar: [OK]")
    Write-Host ("  Subir   : [OK]")
    Write-Host ("  Monitor : {0}" -f $(if ($NoMonitor) { "omitido" } else { "abierto (modo $Mode)" }))
    Write-Host ("  Tiempo  : {0:N1}s" -f $sw.Elapsed.TotalSeconds)
}
finally {
    Pop-Location
}
