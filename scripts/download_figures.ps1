$EnvFile = Join-Path $PSScriptRoot "..\configs\lightning.env"
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

Write-Host ">>> Downloading figures from Lightning AI..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path ".\figures" | Out-Null
scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o UpdateHostKeys=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/figures/*" ".\figures\"
Write-Host ">>> Done!" -ForegroundColor Green
