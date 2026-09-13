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

$cmd = @'
/home/zeus/miniconda3/envs/cloudspace/bin/python - <<'EOF'
import torch
ckpt_path = '/home/zeus/content/sih-model-training/checkpoints/kalmannet/kalmannet_best.pt'
c = torch.load(ckpt_path, map_location='cpu')
print(f"Best Epoch: {c.get('epoch')} | Best Val Loss: {c.get('best_val_loss'):.4f} | Pos RMSE: {c.get('val_pos_rmse'):.2f}m | Vel RMSE: {c.get('val_vel_rmse'):.2f}m/s")
EOF
'@

ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH "${REMOTE_USER}@${REMOTE_HOST}" $cmd
