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

ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" "ls -la $REMOTE_DIR/plots/kalmannet 2>/dev/null; ls -la $REMOTE_DIR/results/kalmannet* 2>/dev/null; ps aux | grep ipykernel"
