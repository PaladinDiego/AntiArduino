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

$AgCmd = Resolve-AntigravityProfile
Write-Log "Usando binario del IDE: $AgCmd" "INFO"

$Extensions = @("llvm-vs-code-extensions.vscode-clangd", "platformio.platformio-ide")
$Installed = & $AgCmd --list-extensions

if ([string]::IsNullOrWhiteSpace(($Installed -join "`n"))) {
    Write-Log "--list-extensions no devolvio ninguna salida util (ExitCode: $LASTEXITCODE). El binario del IDE parece estar roto." "FAIL"
    exit 1
} elseif ($LASTEXITCODE -ne 0) {
    Write-Log "--list-extensions crasheo al cerrar (ExitCode: $LASTEXITCODE) pero ya entrego el listado de extensiones. Ignorando el codigo de salida residual." "WARN"
    $LASTEXITCODE = 0
}

foreach ($Ext in $Extensions) {
    if (($Installed -match $Ext) -and -not $Force) {
        Write-Log "Extension $Ext ya esta instalada." "OK"
        continue
    }

    if ($DryRun) {
        Write-Log "[DRYRUN] Instalaria extension $Ext." "INFO"
        continue
    }

    Write-Log "Intentando instalacion estandar de $Ext..." "INFO"
    $Proc = Start-Process -FilePath $AgCmd -ArgumentList "--install-extension $Ext" -Wait -NoNewWindow -PassThru
    
    if ($Proc.ExitCode -ne 0 -and $Ext -eq "platformio.platformio-ide") {
        Write-Log "Instalacion estandar fallo. Ejecutando fallback manual via GitHub API..." "WARN"
        
        $ApiUrl = "https://api.github.com/repos/platformio/platformio-vscode-ide/releases/latest"
        $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
        $Asset = $Release.assets | Where-Object { $_.name -like "*.vsix" } | Select-Object -First 1
        
        if (-not $Asset) {
            Write-Log "No se encontro .vsix en la release." "FAIL"
            exit 1
        }
        
        $TempVsix = Join-Path $env:TEMP $Asset.name
        Write-Log "Descargando $($Asset.name)..." "INFO"
        Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $TempVsix -UseBasicParsing
        
        $ExtBase = Join-Path $env:USERPROFILE ".antigravity-ide\extensions"
        if (-not (Test-Path $ExtBase)) { New-Item -ItemType Directory -Path $ExtBase -Force | Out-Null }
        
        $ExtFolder = "platformio.platformio-ide-$($Release.tag_name -replace '^v','')"
        $TargetDir = Join-Path $ExtBase $ExtFolder
        if (Test-Path $TargetDir) { Remove-Item -Path $TargetDir -Recurse -Force }
        
        Write-Log "Extrayendo VSIX (ZIP)..." "INFO"
        Expand-Archive -Path $TempVsix -DestinationPath $TargetDir -Force
        
        $Inner = Join-Path $TargetDir "extension"
        if (Test-Path $Inner) {
            Move-Item -Path "$Inner\*" -Destination $TargetDir -Force
            Remove-Item -Path $Inner -Force
        }
        
        $PkgJson = Join-Path $TargetDir "package.json"
        if (Test-Path $PkgJson) {
            Backup-File $PkgJson
            Write-Log "Parcheando package.json (reemplazo estricto a texto plano)..." "INFO"
            
            $Content = Get-Content $PkgJson -Raw -Encoding Ascii
            $Content = $Content -replace '"extensionDependencies"', '"extensionPack"'
            $Content = $Content -replace '"ms-vscode\.cpptools"\s*,?', ''
            $Content = $Content -replace ',\s*]', ']'
            
            try {
                $null = $Content | ConvertFrom-Json
                Set-Content -Path $PkgJson -Value $Content -Encoding Ascii -Force
            } catch {
                Write-Log "JSON invalido al parchear. Restaurando backup..." "FAIL"
                $BakPath = Get-ChildItem -Path $TargetDir -Filter "package.json.bak_*" | Select-Object -First 1
                if ($BakPath) { Copy-Item -Path $BakPath.FullName -Destination $PkgJson -Force }
                exit 1
            }
        }

        # Registrar manualmente en extensions.json
        $ExtJsonPath = Join-Path $ExtBase "extensions.json"
        if (Test-Path $ExtJsonPath) {
            Write-Log "Registrando extension en el manifiesto extensions.json del IDE..." "INFO"
            $ExtJsonObj = Get-Content $ExtJsonPath -Raw -Encoding Ascii | ConvertFrom-Json

            if (-not ($ExtJsonObj | Where-Object { $_.identifier.id -eq "platformio.platformio-ide" })) {
                $NormalizedPath = "/$($TargetDir.Replace('\','/'))"
                $NewEntry = [PSCustomObject]@{
                    identifier = [PSCustomObject]@{ id = "platformio.platformio-ide" }
                    version = ($Release.tag_name -replace '^v','')
                    location = [PSCustomObject]@{ "`$mid" = 1; path = $NormalizedPath; scheme = "file" }
                    relativeLocation = $ExtFolder
                    metadata = [PSCustomObject]@{ isApplicationScoped = $true }
                }

                $ExtJsonObj += $NewEntry
                $NewJsonStr = $ExtJsonObj | ConvertTo-Json -Depth 10 -Compress

                Backup-File $ExtJsonPath
                try {
                    $null = $NewJsonStr | ConvertFrom-Json
                    Set-Content -Path $ExtJsonPath -Value $NewJsonStr -Encoding Ascii -Force
                } catch {
                    Write-Log "JSON resultante invalido para extensions.json. Restaurando backup..." "FAIL"
                    $BakPath = Get-ChildItem -Path $ExtBase -Filter "extensions.json.bak_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($BakPath) { Copy-Item -Path $BakPath.FullName -Destination $ExtJsonPath -Force }
                    exit 1
                }
            }
        }
        Write-Log "Instalacion manual completada." "OK"

    } elseif ($Proc.ExitCode -ne 0) {
        Write-Log "Fallo la instalacion de $Ext." "FAIL"
        exit 1
    }
}
