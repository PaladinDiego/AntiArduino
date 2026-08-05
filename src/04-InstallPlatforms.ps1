[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$LogFile,
    [string]$WorkDir,
    [switch]$DryRun,
    [switch]$QuickSmoke,
    [switch]$Force,
    [string[]]$Platforms = @("atmelavr", "atmelsam", "espressif8266", "espressif32", "ststm32", "raspberrypi")
)

. (Join-Path $PSScriptRoot "00-Common.ps1")

$PioPlatformsDir = Join-Path $env:USERPROFILE ".platformio\platforms"

Write-Log "Plataformas solicitadas: $($Platforms -join ', ')" "INFO"

foreach ($Plat in $Platforms) {
    $PlatDir = Join-Path $PioPlatformsDir $Plat
    
    if ((Test-Path $PlatDir) -and -not $Force) {
        Write-Log "La plataforma $Plat ya esta instalada." "OK"
        continue
    }

    if ($DryRun) {
        Write-Log "[DRYRUN] Instalaria la plataforma $Plat globalmente." "INFO"
        continue
    }

    Write-Log "Instalando plataforma $Plat globalmente (puede tardar minutos)..." "INFO"
    $Proc = Start-Process -FilePath "pio.exe" -ArgumentList "pkg install -g -p $Plat" -Wait -NoNewWindow -PassThru

    if ($Proc.ExitCode -eq 0) {
        Write-Log "Plataforma $Plat instalada correctamente." "OK"
    } else {
        Write-Log "Fallo la instalacion de la plataforma $Plat (ExitCode: $($Proc.ExitCode))." "FAIL"
        exit 1
    }
}

# espressif32 necesita intelhex/pycryptodome/esptool en el venv AISLADO de
# PlatformIO (penv), no en un python/pip global: SCons compila usando el
# interprete de penv, y un pip global nunca sera visible para ese proceso.
# Se ejecuta siempre que se pida espressif32, incluso si la plataforma ya
# estaba instalada (el bloque de arriba hace "continue" en ese caso y nunca
# llegaria aqui) -- pip es idempotente y rapido si ya estan satisfechas.
if ($Platforms -contains "espressif32") {
    $PipExe = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\pip.exe"

    if ($DryRun) {
        Write-Log "[DRYRUN] Instalaria dependencias Python para espressif32 (intelhex, pycryptodome, esptool) via $PipExe." "INFO"
    } elseif (-not (Test-Path $PipExe)) {
        Write-Log "No se encontro pip.exe en penv ($PipExe). Se esperaba que 01-InstallPioCore ya lo hubiera creado." "FAIL"
        exit 1
    } else {
        Write-Log "Instalando dependencias Python para espressif32 (intelhex, pycryptodome, esptool)..." "INFO"
        $Proc = Start-Process -FilePath $PipExe -ArgumentList "install intelhex pycryptodome esptool" -Wait -NoNewWindow -PassThru
        if ($Proc.ExitCode -eq 0) {
            Write-Log "Dependencias Python para espressif32 instaladas correctamente." "OK"
        } else {
            Write-Log "Fallo la instalacion de dependencias Python para espressif32 (ExitCode: $($Proc.ExitCode))." "FAIL"
            exit 1
        }
    }
}
