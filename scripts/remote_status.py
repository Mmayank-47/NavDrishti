import os
import torch

ckpt_path = '/home/zeus/content/sih-model-training/checkpoints/kalmannet/kalmannet_best.pt'
if os.path.exists(ckpt_path):
    d = torch.load(ckpt_path, map_location='cpu', weights_only=False)
    print("BEST CHECKPOINT -> Epoch:", d.get('epoch'), "| Best Val Loss:", round(float(d.get('best_val_loss', 0)), 4), "| Pos RMSE:", round(float(d.get('val_pos_rmse', 0)), 2), "m | Vel RMSE:", round(float(d.get('val_vel_rmse', 0)), 2), "m/s")
else:
    print("Checkpoint not found yet.")
