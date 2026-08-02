function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $FormattedMsg = "[$Timestamp] [$Type] $Message"
    Write-Host "[$Type] $Message"
    
    if (Get-Variable LogFile -ErrorAction SilentlyContinue) { 
        Add-Content -Path $LogFile -Value $FormattedMsg -Encoding Ascii 
    }
}

function Resolve-AntigravityProfile {
    $ProgramsDir = Join-Path $env:LOCALAPPDATA "Programs"
    if (Test-Path $ProgramsDir) {
        $Candidates = Get-ChildItem -Path $ProgramsDir -Filter "*ntigravity*" -Directory
        foreach ($Dir in $Candidates) {
            $ProdJson = Join-Path $Dir.FullName "product.json"
            if (Test-Path $ProdJson) {
                $Data = Get-Content $ProdJson -Raw | ConvertFrom-Json
                if ($Data.dataFolderName -eq ".antigravity-ide") {
                    return Join-Path $Dir.FullName "bin\antigravity.cmd"
                }
            }
        }
    }
    
    Write-Log "No se encontro un perfil de Antigravity IDE con dataFolderName = '.antigravity-ide'." "FAIL"
    throw "Perfil de Antigravity IDE no encontrado. Abortando operacion."
}

function Backup-File([string]$FilePath) {
    if (Test-Path $FilePath) {
        $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $BakPath = "$FilePath.bak_$Stamp"
        Copy-Item -Path $FilePath -Destination $BakPath -Force
        Write-Log "Backup creado: $BakPath" "INFO"
    }
}

function Parse-JsonC([string]$JsonString) {
    $JsonString = [regex]::Replace($JsonString, '(?<!:)\/\/.*', '')
    $JsonString = [regex]::Replace($JsonString, '\/\*[\s\S]*?\*\/', '')
    $JsonString = [regex]::Replace($JsonString, ',\s*([}\]])', '$1')
    return $JsonString | ConvertFrom-Json
}
