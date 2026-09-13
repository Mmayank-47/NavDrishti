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

scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH scripts/remote_status.py "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/scripts/"
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" "$PYTHON $REMOTE_DIR/scripts/remote_status.py"
