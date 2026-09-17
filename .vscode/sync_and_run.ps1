<#
.SYNOPSIS
    SIH PS 26168 — Pipeline Stage Runner and Execution Controller.

.DESCRIPTION
    Automated execution runner for Intelligent Dead Reckoning (IDR) pipeline stages.
    Executes training, evaluation, fusion, and benchmarking stages across environments.

.PARAMETER Stage
    Pipeline stage to run (see Section 49 of procedure_roadmap.md):
      --preflight       Run GPU/environment preflight (00_environment_gpu.ipynb)
      --audit           Run dataset audit (01_dataset_audit.ipynb)
      --preprocess      Run preprocessing notebook
      --train-limu      Train LIMU-BERT
      --test-limu       Test LIMU-BERT (load checkpoint)
      --train-odo       Train OdoNet
      --test-odo        Test OdoNet
      --train-inertial  Train Neural Inertial Odometry
      --test-inertial   Test Neural Inertial Odometry
      --train-kalmannet Train KalmanNet
      --test-kalmannet  Test KalmanNet
      --train-map-gnn   Train GNN Map Matcher
      --test-map-gnn    Test GNN Map Matcher
      --integration     Run final pipeline integration notebook
      --benchmark       Run final SIH benchmark notebook
      --export          Run model export and mobile validation notebook
      --full            Run ALL stages in order (use with caution)

.PARAMETER FileToRun
    Run a specific .py or .ipynb file directly (bypasses --Stage selection).

.PARAMETER PullOnly
    Only pull generated artifacts from remote; do not sync or execute.

.PARAMETER SyncData
    Include data/ directory in the sync bundle (first-time setup only).
    WARNING: data/ is large. Only use when remote dataset is missing.

.EXAMPLE
    .\sync_and_run.ps1 --Stage --preflight
    .\sync_and_run.ps1 --Stage --audit
    .\sync_and_run.ps1 -PullOnly
    .\sync_and_run.ps1 -SyncData --Stage --preflight
#>

param (
    [string]$FileToRun = "",
    [switch]$PullOnly  = $false,
    [switch]$SyncData  = $false,

    # Stage flags (Section 49)
    [switch]$preflight       = $false,
    [switch]$audit           = $false,
    [switch]$reaudit         = $false,
    [switch]$preprocess      = $false,
    [switch]$trainLimu       = $false,
    [switch]$testLimu        = $false,
    [switch]$limuNioAblation = $false,
    [switch]$trainOdo        = $false,
    [switch]$testOdo         = $false,
    [switch]$trainInertial   = $false,
    [switch]$testInertial    = $false,
    [switch]$trainKalmannet  = $false,
    [switch]$testKalmannet   = $false,
    [switch]$gnssFusion      = $false,
    [switch]$trainMapGnn     = $false,
    [switch]$testMapGnn      = $false,
    [switch]$sihScenarios    = $false,
    [switch]$integration     = $false,
    [switch]$benchmark       = $false,
    [switch]$export          = $false,
    [switch]$full            = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Load credentials from configs/lightning.env ──────────────────────────────
$EnvFile = Join-Path $PSScriptRoot "..\configs\lightning.env"
if (-not (Test-Path $EnvFile)) {
    Write-Host "ERROR: configs/lightning.env not found." -ForegroundColor Red
    Write-Host "Copy configs/lightning.env.template to configs/lightning.env and fill in your credentials." -ForegroundColor Yellow
    exit 1
}

$envVars = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.+)$') {
        $k = $Matches[1].Trim()
        $v = $Matches[2].Trim() -replace '\$HOME', $HOME
        $envVars[$k] = $v
    }
}

$REMOTE_USER  = $envVars["LIGHTNING_REMOTE_USER"]
$REMOTE_HOST  = $envVars["LIGHTNING_REMOTE_HOST"]
$KEY_PATH     = $envVars["LIGHTNING_KEY_PATH"]
$REMOTE_DIR   = $envVars["LIGHTNING_REMOTE_DIR"]
$PYTHON_BIN   = $envVars["LIGHTNING_PYTHON_BIN"]
$STUDIO_NAME  = $envVars["LIGHTNING_STUDIO_NAME"]
$TEAMSPACE    = $envVars["LIGHTNING_TEAMSPACE"]

$IN_BUNDLE  = "sih_sync_bundle.tar.gz"
$OUT_BUNDLE = "sih_results_bundle.tar.gz"

# ── Stage → notebook mapping ──────────────────────────────────────────────────
$stageMap = [ordered]@{
    "preflight"      = "notebooks/00_environment_gpu.ipynb"
    "audit"          = "notebooks/01_dataset_audit.ipynb"
    "reaudit"        = "notebooks/01b_driver_split_reaudit.ipynb"
    "preprocess"     = "notebooks/02_preprocessing.ipynb"
    "trainLimu"      = "notebooks/05_limu_bert_training.ipynb"
    "testLimu"       = "notebooks/06_limu_bert_testing.ipynb"
    "limuNioAblation"= "notebooks/05b_limu_bert_nio_ablation.ipynb"
    "trainOdo"       = "notebooks/07_odo_net_training.ipynb"
    "testOdo"        = "notebooks/08_odo_net_testing.ipynb"
    "trainInertial"  = "notebooks/09_inertial_odometry_training.ipynb"   # v2 (fixed uncertainty)
    "testInertial"   = "notebooks/10_inertial_odometry_testing.ipynb"    # baseline vs fixed comparison
    "trainKalmannet" = "notebooks/11_kalmannet_training.ipynb"
    "testKalmannet"  = "notebooks/12_kalmannet_testing.ipynb"
    "gnssFusion"     = "notebooks/14_gnss_fusion.ipynb"
    "trainMapGnn"    = "notebooks/16_map_gnn_training.ipynb"
    "testMapGnn"     = "notebooks/17_map_gnn_testing.ipynb"
    "sihScenarios"   = "notebooks/19b_sih_scenarios.ipynb"
    "integration"    = "notebooks/20_final_pipeline_integration.ipynb"
    "benchmark"      = "notebooks/21_final_sih_benchmark.ipynb"
    "export"         = "notebooks/23_model_export_and_mobile_validation.ipynb"
}

# ── Determine what to run ─────────────────────────────────────────────────────
$filesToRun = @()

if ($full) {
    $filesToRun = $stageMap.Values
} else {
    foreach ($stage in $stageMap.Keys) {
        $flag = Get-Variable -Name $stage -ValueOnly -ErrorAction SilentlyContinue
        if ($flag) { $filesToRun += $stageMap[$stage] }
    }
    if ($FileToRun -ne "") {
        $filesToRun = @($FileToRun -replace '\\', '/')
    }
}

# ── Helper: studio notice ─────────────────────────────────────────────────────
function Show-StudioNotice {
    Write-Host "`n⚠  Cannot reach Lightning AI Studio." -ForegroundColor Yellow
    Write-Host "   Start it via:" -ForegroundColor Yellow
    Write-Host "   lightning studio start --teamspace $TEAMSPACE --name $STUDIO_NAME" -ForegroundColor Cyan
    Write-Host "   or visit https://lightning.ai`n" -ForegroundColor Cyan
}

# ── SSH helper ────────────────────────────────────────────────────────────────
function Invoke-SSH {
    param([string]$Cmd, [switch]$Interactive)
    $sshArgs = @(
        "-o", "LogLevel=ERROR",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "UpdateHostKeys=no",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=10",
        "-i", $KEY_PATH
    )
    if ($Interactive) { $sshArgs += "-t" }
    $sshArgs += "$REMOTE_USER@$REMOTE_HOST"
    $sshArgs += $Cmd
    & ssh @sshArgs | Out-Host
    return [int]$LASTEXITCODE
}

# ── PULL ONLY MODE ────────────────────────────────────────────────────────────
if ($PullOnly) {
    Write-Host "=" * 60 -ForegroundColor Magenta
    Write-Host ">>> Pulling generated outputs from Lightning AI..." -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Magenta

    $pullCmd = "cd $REMOTE_DIR && find . -maxdepth 5 -type f \( " +
               "-name '*.png' -o -name '*.pdf' -o -name '*.onnx' " +
               "-o -name '*.pth' -o -name '*.pt' -o -name '*.ckpt' " +
               "-o -name '*.csv' -o -name '*.json' -o -name '*_executed.ipynb' " +
               "-o -name '*.log' \) " +
               "! -path '*/.git/*' ! -path '*/node_modules/*' " +
               "! -path '*/.vscode/*' ! -path '*/venv/*' ! -path '*/data/*' " +
               "-print0 | tar --null -czf $OUT_BUNDLE --files-from - 2>/dev/null"

    $rc = Invoke-SSH -Cmd $pullCmd
    if ($rc -ne 0) { Show-StudioNotice; exit $rc }

    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY_PATH `
        "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${OUT_BUNDLE}" "./" 2>$null
    $ErrorActionPreference = $oldEap

    if (Test-Path $OUT_BUNDLE) {
        & tar -xzf $OUT_BUNDLE
        Remove-Item -Force $OUT_BUNDLE
        Invoke-SSH -Cmd "rm -f $REMOTE_DIR/$OUT_BUNDLE" | Out-Null
        Write-Host ">>> Artifacts synced to workspace." -ForegroundColor Magenta
    } else {
        Write-Host ">>> No new artifacts found on remote." -ForegroundColor Gray
    }
    exit 0
}

# ── Validate something to run ─────────────────────────────────────────────────
if ($filesToRun.Count -eq 0) {
    Write-Host "ERROR: No stage or file specified." -ForegroundColor Red
    Write-Host "Usage: .\sync_and_run.ps1 -preflight" -ForegroundColor Yellow
    Write-Host "       .\sync_and_run.ps1 -audit" -ForegroundColor Yellow
    Write-Host "       .\sync_and_run.ps1 -FileToRun notebooks/00_environment_gpu.ipynb" -ForegroundColor Yellow
    Write-Host "       .\sync_and_run.ps1 -full   (runs ALL stages)" -ForegroundColor Yellow
    exit 1
}

# ── 1. PACKAGE & SYNC ─────────────────────────────────────────────────────────
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ">>> [1/3] Syncing code to Lightning AI..." -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

$tarItems = @()
$candidates = @("notebooks", "src", "configs", "scripts", "training", "evaluation", "docs", "exports")
foreach ($dir in $candidates) {
    if (Test-Path $dir) { $tarItems += "./$dir" }
}

# Root-level code/config files
Get-ChildItem -File -Path . -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -match '^\.(py|json|ya?ml|sh|toml|md|txt)$' -and
    $_.Name -ne "package-lock.json"
} | ForEach-Object { $tarItems += "./$($_.Name)" }

if ($SyncData -and (Test-Path "data")) {
    Write-Host ">>> WARNING: Including data/ in sync bundle (large upload)." -ForegroundColor Yellow
    $tarItems += "./data"
}

if ($tarItems.Count -eq 0) {
    Write-Host ">>> Notice: Nothing to bundle yet." -ForegroundColor Gray
} else {
    Write-Host ">>> Bundling: $($tarItems -join ', ')" -ForegroundColor Gray
    & tar --exclude=".git" --exclude=".vscode" `
          --exclude="data/**/*.zip" --exclude="data/**/*.tar.gz" `
          --exclude="venv" --exclude=".venv" --exclude="__pycache__" `
          --exclude="*.zip" --exclude="node_modules" `
          --exclude="configs/lightning.env" `
          -czf $IN_BUNDLE $tarItems
}

$rc = Invoke-SSH -Cmd "mkdir -p $REMOTE_DIR"
if ($rc -ne 0) {
    if (Test-Path $IN_BUNDLE) { Remove-Item -Force $IN_BUNDLE }
    Show-StudioNotice
    exit $rc
}

if (Test-Path $IN_BUNDLE) {
    & scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -i $KEY_PATH `
        $IN_BUNDLE "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
    Invoke-SSH -Cmd "tar -xzf $REMOTE_DIR/$IN_BUNDLE -C $REMOTE_DIR && rm -f $REMOTE_DIR/$IN_BUNDLE"
    Remove-Item -Force $IN_BUNDLE
}

# ── 2. EXECUTE ON REMOTE GPU ──────────────────────────────────────────────────
Write-Host "`n" + "=" * 60 -ForegroundColor Green
Write-Host ">>> [2/3] Executing on Lightning GPU..." -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Green

foreach ($file in $filesToRun) {
    Write-Host "`n>>> Running: $file" -ForegroundColor Green
    $remoteFile = $file -replace '\\', '/'
    $execCmd = "bash ${REMOTE_DIR}/scripts/run_remote.sh $remoteFile"
    $rc = Invoke-SSH -Cmd $execCmd -Interactive
    if ($rc -ne 0) {
        Write-Host ">>> FAILED: $file (exit code $rc)" -ForegroundColor Red
        Write-Host ">>> Pulling any partial artifacts before exit..." -ForegroundColor Yellow
        break
    }
}

# ── 3. PULL ARTIFACTS BACK ────────────────────────────────────────────────────
Write-Host "`n" + "=" * 60 -ForegroundColor Magenta
Write-Host ">>> [3/3] Pulling generated outputs back to workspace..." -ForegroundColor Magenta
Write-Host "=" * 60 -ForegroundColor Magenta

$pullCmd = "cd $REMOTE_DIR && find . -maxdepth 5 -type f \( " +
           "-name '*.png' -o -name '*.pdf' -o -name '*.onnx' " +
           "-o -name '*.pth' -o -name '*.pt' -o -name '*.ckpt' " +
           "-o -name '*.csv' -o -name '*.json' -o -name '*_executed.ipynb' " +
           "-o -name '*.log' \) " +
           "! -path '*/.git/*' ! -path '*/node_modules/*' " +
           "! -path '*/.vscode/*' ! -path '*/venv/*' ! -path '*/data/*' " +
           "-print0 | tar --null -czf $OUT_BUNDLE --files-from - 2>/dev/null"

Invoke-SSH -Cmd $pullCmd | Out-Null
$oldEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& scp -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY_PATH `
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${OUT_BUNDLE}" "./" 2>$null
$ErrorActionPreference = $oldEap

if (Test-Path $OUT_BUNDLE) {
    & tar -xzf $OUT_BUNDLE
    Remove-Item -Force $OUT_BUNDLE
    Invoke-SSH -Cmd "rm -f $REMOTE_DIR/$OUT_BUNDLE" | Out-Null
    Write-Host ">>> Artifacts synced to workspace." -ForegroundColor Magenta
} else {
    Write-Host ">>> No new artifacts to pull." -ForegroundColor Gray
}

Write-Host "`n>>> Done." -ForegroundColor Cyan
