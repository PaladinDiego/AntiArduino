<#
.SYNOPSIS
    Verifica el estado REAL del sistema tras la instalacion, sin depender de
    setup.log ni de que el instalador haya corrido en esta misma sesion.
.EXAMPLE
    .\verify-install.ps1
    .\verify-install.ps1 -WorkDir D:\embedded
#>
[CmdletBinding()]
param(
    [string]$WorkDir = "C:\embedded-dev"
)

# Copias independientes de Resolve-AntigravityProfile y Parse-JsonC.
# Este script se despliega tambien dentro de $WorkDir\scripts\ (ver
# src/06-DeployWorkspaceAssets.ps1), donde el repo original puede no estar
# presente. Debe poder correr standalone.

function Resolve-AntigravityProfileLocal {
    $ProgramsDir = Join-Path $env:LOCALAPPDATA "Programs"
    if (Test-Path $ProgramsDir) {
        $Candidates = Get-ChildItem -Path $ProgramsDir -Filter "*ntigravity*" -Directory
        foreach ($Dir in $Candidates) {
            $ProdJsonCandidates = @(
                (Join-Path $Dir.FullName "product.json"),
                (Join-Path $Dir.FullName "resources\app\product.json")
            )
            $ProdJson = $ProdJsonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($ProdJson) {
                $Data = Get-Content $ProdJson -Raw | ConvertFrom-Json
                if ($Data.dataFolderName -eq ".antigravity-ide") {
                    $BinDir = Join-Path $Dir.FullName "bin"
                    $Cmd = Get-ChildItem -Path $BinDir -Filter "*.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($Cmd) {
                        return [PSCustomObject]@{
                            BinaryPath     = $Cmd.FullName
                            InstallRoot    = $Dir.FullName
                            DataFolderName = $Data.dataFolderName
                        }
                    }
                }
            }
        }
    }
    return $null
}

function Parse-JsonCLocal([string]$JsonString) {
    $JsonString = [regex]::Replace($JsonString, '(?<!:)\/\/.*', '')
    $JsonString = [regex]::Replace($JsonString, '\/\*[\s\S]*?\*\/', '')
    $JsonString = [regex]::Replace($JsonString, ',\s*([}\]])', '$1')
    return $JsonString | ConvertFrom-Json
}

$Results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail = "")
    $Results.Add([PSCustomObject]@{ Name = $Name; Passed = $Passed; Detail = $Detail })
}

Write-Host "=== Verificacion independiente del entorno Antigravity Embedded ===" -ForegroundColor Cyan
Write-Host "WorkDir: $WorkDir"
Write-Host ""

# 1. pio.exe existe y responde a --version
$PioExe = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\pio.exe"
if (Test-Path $PioExe) {
    try {
        $VerOutput = & $PioExe --version 2>&1
        if ($LASTEXITCODE -eq 0 -and ($VerOutput -match "PlatformIO Core")) {
            Add-Check "pio.exe existe y responde a --version" $true "$VerOutput"
        } else {
            Add-Check "pio.exe existe y responde a --version" $false "ExitCode=$LASTEXITCODE, output: $VerOutput"
        }
    } catch {
        Add-Check "pio.exe existe y responde a --version" $false "Excepcion al invocar pio.exe: $_"
    }
} else {
    Add-Check "pio.exe existe y responde a --version" $false "No existe en $PioExe"
}

# 2. Las 6 plataformas por defecto estan en .platformio\platforms\
$ExpectedPlatforms = @("atmelavr", "atmelsam", "espressif8266", "espressif32", "ststm32", "raspberrypi")
$PlatformsDir = Join-Path $env:USERPROFILE ".platformio\platforms"
$MissingPlatforms = @()
foreach ($Plat in $ExpectedPlatforms) {
    if (-not (Test-Path (Join-Path $PlatformsDir $Plat))) { $MissingPlatforms += $Plat }
}
if ($MissingPlatforms.Count -eq 0) {
    Add-Check "6 plataformas instaladas en .platformio\platforms" $true "$($ExpectedPlatforms -join ', ')"
} else {
    Add-Check "6 plataformas instaladas en .platformio\platforms" $false "Faltan: $($MissingPlatforms -join ', ')"
}

# 3. La extension platformio-ide aparece registrada para el perfil correcto
$Profile = Resolve-AntigravityProfileLocal
if ($Profile) {
    $ExtBase = Join-Path $env:USERPROFILE "$($Profile.DataFolderName)\extensions"
    $ExtJsonPath = Join-Path $ExtBase "extensions.json"
    $FoundInManifest = $false
    $FoundAsFolder = (Get-ChildItem -Path $ExtBase -Filter "platformio.platformio-ide*" -Directory -ErrorAction SilentlyContinue).Count -gt 0

    if (Test-Path $ExtJsonPath) {
        try {
            $ExtJsonObj = Get-Content $ExtJsonPath -Raw -Encoding Ascii | ConvertFrom-Json
            $FoundInManifest = [bool]($ExtJsonObj | Where-Object { $_.identifier.id -eq "platformio.platformio-ide" })
        } catch {
            # extensions.json invalido no bloquea el check de la carpeta
        }
    }

    if ($FoundInManifest -or $FoundAsFolder) {
        Add-Check "Extension platformio-ide registrada para el perfil correcto" $true "Perfil: $($Profile.InstallRoot) (manifest=$FoundInManifest, carpeta=$FoundAsFolder)"
    } else {
        Add-Check "Extension platformio-ide registrada para el perfil correcto" $false "No aparece en $ExtJsonPath ni como carpeta en $ExtBase"
    }
} else {
    Add-Check "Extension platformio-ide registrada para el perfil correcto" $false "No se pudo resolver el perfil de Antigravity IDE (dataFolderName=.antigravity-ide)"
}

# 4. settings.json contiene las claves de $OwnedKeys esperadas
$OwnedKeys = @("clangd.path", "clangd.arguments", "platformio.activateOnlyOnPlatformIOProject", "C_Cpp.intelliSenseEngine")
$SettingsPath = Join-Path $env:APPDATA "Antigravity IDE\User\settings.json"
if (Test-Path $SettingsPath) {
    try {
        $SettingsObj = Parse-JsonCLocal (Get-Content $SettingsPath -Raw -Encoding Ascii)
        $MissingKeys = @()
        foreach ($Key in $OwnedKeys) {
            if ($SettingsObj.psobject.properties.Match($Key).Count -eq 0) { $MissingKeys += $Key }
        }
        if ($MissingKeys.Count -eq 0) {
            Add-Check "settings.json contiene las claves de OwnedKeys" $true "$($OwnedKeys -join ', ')"
        } else {
            Add-Check "settings.json contiene las claves de OwnedKeys" $false "Faltan: $($MissingKeys -join ', ')"
        }
    } catch {
        Add-Check "settings.json contiene las claves de OwnedKeys" $false "settings.json invalido o ilegible: $_"
    }
} else {
    Add-Check "settings.json contiene las claves de OwnedKeys" $false "No existe: $SettingsPath"
}

# 5. WorkDir tiene scripts/, templates/, .vscode/tasks.json con las tareas esperadas
$ScriptsDirOk = Test-Path (Join-Path $WorkDir "scripts")
Add-Check "$WorkDir\scripts existe" $ScriptsDirOk

$TemplatesDirOk = Test-Path (Join-Path $WorkDir "templates")
Add-Check "$WorkDir\templates existe" $TemplatesDirOk

$TasksPath = Join-Path $WorkDir ".vscode\tasks.json"
$ExpectedTaskLabels = @("Arduino: Compile", "Arduino: Upload", "Arduino: Flash & Watch", "Arduino: Preflight")
if (Test-Path $TasksPath) {
    try {
        $TasksObj = Parse-JsonCLocal (Get-Content $TasksPath -Raw -Encoding Ascii)
        $Labels = @($TasksObj.tasks | ForEach-Object { $_.label })
        $MissingLabels = $ExpectedTaskLabels | Where-Object { $Labels -notcontains $_ }
        if ($MissingLabels.Count -eq 0) {
            Add-Check "$WorkDir\.vscode\tasks.json contiene las tareas esperadas" $true "$($ExpectedTaskLabels -join ', ')"
        } else {
            Add-Check "$WorkDir\.vscode\tasks.json contiene las tareas esperadas" $false "Faltan: $($MissingLabels -join ', ')"
        }
    } catch {
        Add-Check "$WorkDir\.vscode\tasks.json contiene las tareas esperadas" $false "tasks.json invalido o ilegible: $_"
    }
} else {
    Add-Check "$WorkDir\.vscode\tasks.json contiene las tareas esperadas" $false "No existe: $TasksPath"
}

# --- Resumen ---
Write-Host ""
Write-Host "=== Resultado ===" -ForegroundColor Cyan
foreach ($R in $Results) {
    if ($R.Passed) {
        Write-Host "[OK] $($R.Name)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $($R.Name) -- $($R.Detail)" -ForegroundColor Red
    }
}

$Passed = ($Results | Where-Object { $_.Passed }).Count
$Total = $Results.Count
Write-Host ""
Write-Host "$Passed de $Total checks pasaron." -ForegroundColor Cyan

if ($Passed -lt $Total) {
    Write-Host ""
    Write-Host "Checks fallidos:" -ForegroundColor Yellow
    $Results | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Detail)" -ForegroundColor Yellow
    }
    exit 1
}

exit 0
