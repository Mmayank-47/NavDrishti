param (
    [string]$TargetFolder = "ALL"
)

# scripts/upload_dataset.ps1
# Uploads specified datasets to remote Lightning AI storage.

$EnvFile = Join-Path $PSScriptRoot "..\configs\lightning.env"
if (-not (Test-Path $EnvFile)) {
    Write-Error "configs/lightning.env not found."
    exit 1
}

$envVars = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.+)$') {
        $envVars[$Matches[1].Trim()] = $Matches[2].Trim() -replace '\$HOME', $HOME
    }
}

$REMOTE_USER = $envVars["LIGHTNING_REMOTE_USER"]
$REMOTE_HOST = $envVars["LIGHTNING_REMOTE_HOST"]
$KEY_PATH    = $envVars["LIGHTNING_KEY_PATH"]
$REMOTE_DIR  = $envVars["LIGHTNING_REMOTE_DIR"]

function Upload-And-Extract {
    param(
        [string]$ArchiveName,
        [string]$SourcePath,
        [string]$RemoteSubdir = "data"
    )
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host ">>> Processing dataset: $SourcePath" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if (-not (Test-Path $SourcePath)) {
        Write-Host "WARNING: Source path not found: $SourcePath" -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $ArchiveName)) {
        Write-Host ">>> Creating archive $ArchiveName (this may take a moment)..." -ForegroundColor Yellow
        if ($ArchiveName -like "*.tar") {
            & tar --exclude=".git" -cf $ArchiveName $SourcePath
        } else {
            & tar --exclude=".git" -czf $ArchiveName $SourcePath
        }
        $sizeMB = [math]::Round((Get-Item $ArchiveName).Length / 1MB, 2)
        Write-Host ">>> Created $ArchiveName ($sizeMB MB)." -ForegroundColor Green
    } else {
        $sizeMB = [math]::Round((Get-Item $ArchiveName).Length / 1MB, 2)
        Write-Host ">>> Found existing $ArchiveName ($sizeMB MB)." -ForegroundColor Green
    }

    Write-Host ">>> Uploading $ArchiveName to Lightning AI ($sizeMB MB)..." -ForegroundColor Cyan
    & scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH $ArchiveName "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

    Write-Host ">>> Extracting on remote Lightning AI..." -ForegroundColor Green
    $cmd = "tar -xf $REMOTE_DIR/$ArchiveName -C $REMOTE_DIR && rm -f $REMOTE_DIR/$ArchiveName && ls -lh $REMOTE_DIR/data"
    & ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" $cmd

    # Clean up local archive after upload to free space
    if (Test-Path $ArchiveName) {
        Remove-Item -Force $ArchiveName
    }
    Write-Host ">>> Successfully deployed $SourcePath to remote!" -ForegroundColor Green
}

if ($TargetFolder -eq "MOTOR" -or $TargetFolder -eq "ALL") {
    # Check if MOTOR already exists on remote
    $checkCmd = "[ -d $REMOTE_DIR/data/MOTOR ] && echo 'EXISTS' || echo 'MISSING'"
    $res = & ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" $checkCmd
    if ($res -match "EXISTS") {
        Write-Host ">>> MOTOR already deployed on remote. Skipping." -ForegroundColor Gray
    } else {
        Upload-And-Extract -ArchiveName "motor_sync.tar.gz" -SourcePath "data/MOTOR"
    }
}

if ($TargetFolder -eq "OSM" -or $TargetFolder -eq "ALL") {
    $checkCmd = "[ -d $REMOTE_DIR/data/OSM ] && echo 'EXISTS' || echo 'MISSING'"
    $res = & ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" $checkCmd
    if ($res -match "EXISTS") {
        Write-Host ">>> OSM already deployed on remote. Skipping." -ForegroundColor Gray
    } else {
        Upload-And-Extract -ArchiveName "osm_sync.tar" -SourcePath "data/OSM"
    }
}

if ($TargetFolder -eq "IO-VNBD-Unsync" -or $TargetFolder -eq "ALL") {
    $checkCmd = "[ -d '$REMOTE_DIR/data/IO-VNBD/Unsynchronised V and S Dataset' ] && echo 'EXISTS' || echo 'MISSING'"
    $res = & ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" $checkCmd
    if ($res -match "EXISTS") {
        Write-Host ">>> IO-VNBD Unsynchronised already deployed on remote. Skipping." -ForegroundColor Gray
    } else {
        Upload-And-Extract -ArchiveName "iovnbd_unsync.tar.gz" -SourcePath "data/IO-VNBD/Unsynchronised V and S Dataset"
    }
}

if ($TargetFolder -eq "NavIC" -or $TargetFolder -eq "ALL") {
    $checkCmd = "[ -d '$REMOTE_DIR/data/NavICGNSS android raw measurments' ] && echo 'EXISTS' || echo 'MISSING'"
    $res = & ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" $checkCmd
    if ($res -match "EXISTS") {
        Write-Host ">>> NavIC already deployed on remote. Skipping." -ForegroundColor Gray
    } else {
        Upload-And-Extract -ArchiveName "navic_sync.tar.gz" -SourcePath "data/NavICGNSS android raw measurments"
    }
}

if ($TargetFolder -eq "GNSS-Interference" -or $TargetFolder -eq "ALL") {
    $checkCmd = "[ -d '$REMOTE_DIR/data/GNSS Dataset (with Interference and Spoofing) Part III' ] && echo 'EXISTS' || echo 'MISSING'"
    $res = & ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" $checkCmd
    if ($res -match "EXISTS") {
        Write-Host ">>> GNSS Interference already deployed on remote. Skipping." -ForegroundColor Gray
    } else {
        Upload-And-Extract -ArchiveName "gnss_interference.tar.gz" -SourcePath "data/GNSS Dataset (with Interference and Spoofing) Part III"
    }
}

Write-Host "`n>>> All requested datasets processed!" -ForegroundColor Green
