# Dataset Audit Report — SIH PS 26168

**Intelligent Dead Reckoning with GNSS Fusion**  
**Audit Timestamp:** 2026-09-13T08:48:59.652772+00:00  
**Status:** Complete  

---

## Executive Summary

| Dataset | Role | Primary? | Size (MB) | Sessions / Files Audited |
|---|---|:---:|---|---|
| **IO_VNBD** | Primary real vehicle dataset for official SIH... | Yes | 3726.1 | 30 |
| **GNSS_INTERFERENCE** | GNSS interference, jamming, and spoofing expe... | No | 4146.4 | 5 |
| **NAVIC_GNSS** | Android/NavIC raw GNSS measurement experiment... | No | 3287.9 | 3 |
| **MOTOR** | Additional real vehicle/motorcycle data — sch... | No | 47.3 | 0 |
| **OSM** | Offline OpenStreetMap road data for GNN map m... | No | 0.0 | 0 |

---

### IO_VNBD ★ PRIMARY

- **Source Folder:** `data\IO-VNBD`
- **Role:** Primary real vehicle dataset for official SIH inertial-odometry benchmarking
- **Size:** 3726.1 MB

| Session File | Sampled Rows | Columns | Timestamp Col | IMU Cols | GNSS Cols | GT Cols | Est. Hz |
|---|---|---|---|---|---|---|---|
| `S-M.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-M.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-S1.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-S1.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-S2.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-S2.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-S3a.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-S3a.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-S3b.csv` | 6,813 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-S3b.csv` | 6,813 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-S3c.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-S3c.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-S4.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-S4.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-Vfa01.csv` | 11,486 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-Vfa01.csv` | 11,535 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-Vfa02.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-Vfa02.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |
| `S-Vta1a.csv` | 20,000 | 24 | TIME SINCE START (ms | 10 | 7 | 0 | 10.0 |
| `V-Vta1a.csv` | 20,000 | 29 | Time Since Start of  | 3 | 11 | 2 | 10.0 |

**Notes:**
- ⚠ Primary benchmark dataset containing vehicle and smartphone IMU + GNSS + GT data.
- ⚠ Session-level train/validation/test splits defined to prevent data leakage.
- ⚠ Ground truth reference used exclusively for loss calculation and evaluation, never during GNSS-denied inference.

---
### GNSS_INTERFERENCE

- **Source Folder:** `data\GNSS Dataset (with Interference and Spoofing) Part III\GNSS Dataset (with Interference and Spoofing) Part III`
- **Role:** GNSS interference, jamming, and spoofing experiments
- **Size:** 4146.4 MB

| Session File | Sampled Rows | Columns | Timestamp Col | IMU Cols | GNSS Cols | GT Cols | Est. Hz |
|---|---|---|---|---|---|---|---|
| `pvtSolution12.json` | 0 | 0 | N/A | 0 | 0 | 0 | N/A |
| `pvtSolution13.json` | 0 | 0 | N/A | 0 | 0 | 0 | N/A |
| `pvtSolution14.json` | 0 | 0 | N/A | 0 | 0 | 0 | N/A |
| `pvtSolution15.json` | 0 | 0 | N/A | 0 | 0 | 0 | N/A |
| `pvtSolution16.json` | 0 | 0 | N/A | 0 | 0 | 0 | N/A |

**Notes:**
- ⚠ Contains rich JSON observations and PVT solutions (velN, velE, velD, lat, lon, height, numSV).
- ⚠ Use for GNSS quality/degradation detection experiments and covariance estimation.
- ⚠ Validate schemas before use in any fusion pipeline.

---
### NAVIC_GNSS

- **Source Folder:** `data\NavICGNSS android raw measurments\NavICGNSS android raw measurments`
- **Role:** Android/NavIC raw GNSS measurement experiments and GNSS-side validation
- **Size:** 3287.9 MB

| Session File | Sampled Rows | Columns | Timestamp Col | IMU Cols | GNSS Cols | GT Cols | Est. Hz |
|---|---|---|---|---|---|---|---|
| `gnss_log_2024_08_15_15_51_07_rnx_data.txt` | 20,000 | 1 | N/A | 0 | 0 | 0 | N/A |
| `gnss_log_2024_08_25_18_19_58_rnx_data.txt` | 20,000 | 1 | N/A | 0 | 0 | 0 | N/A |
| `gnss_log_2024_08_26_17_06_52_rnx_data.txt` | 20,000 | 1 | N/A | 0 | 0 | 0 | N/A |

**Notes:**
- ⚠ Contains Android raw GNSS measurements across multiple inclination angles (0, 45, 90, 135, 180 deg).
- ⚠ Includes reference Ublox ground truth static positions.
- ⚠ Supports NavIC (IRNSS) constellation raw measurements.

---
### MOTOR

- **Source Folder:** `data\MOTOR`
- **Role:** Additional real vehicle/motorcycle data — schema must be audited before use
- **Size:** 47.3 MB

**Notes:**
- ⚠ Annotations cover Road Type, Lanes, Markings, Divider, Traffic Density.
- ⚠ Use only after coordinate system, sensor schema, and ground truth are confirmed.

---
### OSM

- **Source Folder:** `data\OSM`
- **Role:** Offline OpenStreetMap road data for GNN map matching — not a trajectory dataset
- **Size:** 0.0 MB

**Notes:**
- ⚠ india-260912.osm.pbf covers India road network (1.7 GB).
- ⚠ Local subgraphs extracted per session bounding box during GNN training.
- ⚠ Never load full India road network into memory at once.

---

## Proposed Train / Validation / Test Split Strategy

- **Method:** `session_level`
- **Rationale:** Adjacent samples from the same trajectory must never be split randomly. Session-level splitting prevents temporal leakage.

### IO-VNBD Split Assignment
- **Training Drivers:** M (Driver B), Vf (Driver E), Vta (Driver E), Vtb (Driver E), Vw (Driver E)
- **Validation Drivers:** Y (Driver D)
- **Test Drivers (Locked):** S (Driver A)

> ⚠ **WARNING:** Do NOT use final test sessions for ANY hyperparameter tuning or architecture selection.
