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
                        return $Cmd.FullName
                    }
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
