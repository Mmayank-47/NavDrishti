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

$script = @'
import json
try:
    with open('/home/zeus/content/sih-model-training/notebooks/11_kalmannet_training.ipynb') as f:
        nb = json.load(f)
    for c in nb['cells']:
        if c.get('cell_type') == 'code' and c.get('outputs'):
            for o in c['outputs']:
                if 'text' in o:
                    lines = o['text']
                    print("".join(lines[-5:]))
except Exception as e:
    print(e)
'@

ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" "$PYTHON -c \"$script\""
