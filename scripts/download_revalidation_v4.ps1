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

Write-Host ">>> Downloading revalidation v4 results..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path ".\results\phase_revalidation_v4" | Out-Null
New-Item -ItemType Directory -Force -Path ".\plots\phase_revalidation_v4" | Out-Null

scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o UpdateHostKeys=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/results/phase_revalidation_v4/revalidation_v4_results.json" ".\results\phase_revalidation_v4\"

Write-Host ">>> Downloading plots..." -ForegroundColor Cyan
scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o UpdateHostKeys=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/plots/phase_revalidation_v4/*" ".\plots\phase_revalidation_v4\"

Write-Host ">>> Done!" -ForegroundColor Green
