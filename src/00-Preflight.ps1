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

Write-Log "Ejecutando Preflight Checks..." "INFO"

# 1. Arquitectura OS
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Log "Se requiere Windows de 64-bits." "FAIL"
    exit 1
}

# 2. Python: Parseo de Major y Minor como enteros independientes
$PythonOk = $false
try {
    $PyVerStr = (& python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>&1).Trim()
    $Parts = $PyVerStr -split '\.'
    $Major = [int]$Parts[0]
    $Minor = [int]$Parts[1]

    if ($Major -lt 3 -or ($Major -eq 3 -and $Minor -lt 9)) {
        Write-Log "Python en el PATH es version $PyVerStr. Se requiere >= 3.9." "FAIL"
    } else {
        Write-Log "Python version $PyVerStr detectado correctamente." "OK"
        $PythonOk = $true
    }
} catch {
    Write-Log "Python no esta en el PATH o fallo al ejecutar." "FAIL"
}

if (-not $PythonOk) {
    $WingetCmd = 'winget install Python.Python.3.12 --scope user --override "/passive PrependPath=1"'
    Write-Log "Remediacion sugerida: $WingetCmd" "FAIL"

    if ($DryRun) {
        Write-Log "[DRYRUN] Preflight fallaria aqui en una corrida real. No se ofrece auto-instalacion en modo -DryRun." "WARN"
        exit 1
    }

    # Auto-remediacion interactiva: solo se ofrece si hay una consola real
    # (input no redirigido) y winget esta disponible. En ejecuciones de agente
    # (stdin redirigido/no interactivo) esto se omite automaticamente para no
    # colgar el proceso esperando una respuesta que nunca llega -- ver AGENTS.md.
    $HasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    $IsInteractive = -not [Console]::IsInputRedirected

    if ($HasWinget -and $IsInteractive) {
        $Answer = Read-Host "Se detecto winget. Instalar Python 3.12 ahora? (S/N)"
        if ($Answer -match '^(s|si|y|yes)$') {
            Write-Log "Instalando Python 3.12 via winget..." "INFO"
            $Proc = Start-Process -FilePath "winget" -ArgumentList 'install Python.Python.3.12 --scope user --override "/passive PrependPath=1"' -Wait -NoNewWindow -PassThru
            if ($Proc.ExitCode -eq 0) {
                Write-Log "Python instalado correctamente. El PATH de este proceso no se refresca solo: cierra esta terminal, abre una nueva y vuelve a ejecutar Deploy-Environment.ps1 (o setup.bat)." "OK"
            } else {
                Write-Log "La instalacion via winget fallo (ExitCode $($Proc.ExitCode)). Instala Python manualmente y vuelve a intentar." "FAIL"
            }
        } else {
            Write-Log "Instalacion declinada. Instala Python manualmente y vuelve a intentar." "INFO"
        }
    } elseif (-not $HasWinget) {
        Write-Log "winget no esta disponible en este sistema. Instala Python manualmente desde https://www.python.org/downloads/ (marca 'Add python.exe to PATH')." "INFO"
    } else {
        Write-Log "Sesion no interactiva detectada (stdin redirigido). Omitiendo prompt de auto-instalacion; sigue la remediacion sugerida arriba." "INFO"
    }

    exit 1
}

# 3. Antigravity IDE Instalado
try {
    $AgCmd = Resolve-AntigravityProfile
    Write-Log "Perfil de Antigravity IDE encontrado." "OK"
} catch {
    Write-Log "El IDE no esta instalado o no se encontro el perfil .antigravity-ide." "FAIL"
    exit 1
}
