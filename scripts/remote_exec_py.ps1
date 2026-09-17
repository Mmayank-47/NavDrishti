param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    [string]$Args = ""
)

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
$PYTHON      = $envVars["LIGHTNING_PYTHON_BIN"]

$scriptName = Split-Path $ScriptPath -Leaf
Write-Host ">>> Uploading $ScriptPath to Lightning AI..." -ForegroundColor Cyan
scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o UpdateHostKeys=no -i $KEY_PATH $ScriptPath "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/scripts/$scriptName"

Write-Host ">>> Executing on Lightning AI..." -ForegroundColor Green
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o UpdateHostKeys=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" "export PYTHONPATH=$REMOTE_DIR; export LIGHTNING_REMOTE_DIR=$REMOTE_DIR; export LIGHTNING_PYTHON_BIN=$PYTHON; cd $REMOTE_DIR && $PYTHON scripts/$scriptName $Args"
