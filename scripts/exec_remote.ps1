param(
    [Parameter(Mandatory=$true)]
    [string]$Cmd
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

ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o UpdateHostKeys=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" "export PYTHONPATH=$REMOTE_DIR; export LIGHTNING_REMOTE_DIR=$REMOTE_DIR; export LIGHTNING_PYTHON_BIN=$PYTHON; cd $REMOTE_DIR && $Cmd"
