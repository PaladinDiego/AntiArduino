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
