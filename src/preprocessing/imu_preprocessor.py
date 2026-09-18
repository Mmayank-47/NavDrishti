"""
src/preprocessing/imu_preprocessor.py
─────────────────────────────────────────────────────────────────────────────
SIH PS 26168 — Intelligent Dead Reckoning
IMU signal preprocessing, vibration suppression, gravity compensation,
and stationary / zero-velocity (ZUPT) detection.
─────────────────────────────────────────────────────────────────────────────
"""

import numpy as np
from scipy.signal import butter, filtfilt

STANDARD_GRAVITY = 9.80665


class IMUPreprocessor:
    """
    Robust IMU signal preprocessor for vehicle & smartphone MEMS sensors.
    Handles high-frequency vibration, potholes/shocks, gravity removal,
    and stationary state (ZUPT) detection.
    """

    def __init__(
        self,
        sampling_rate_hz=10.0,
        accel_cutoff_hz=4.0,
        gyro_cutoff_hz=4.0,
        zupt_accel_var_thresh=0.08,   # (m/s^2)^2 threshold for zero velocity
        zupt_gyro_var_thresh=0.005,    # (rad/s)^2 threshold for zero velocity
        zupt_window_size=10,           # Number of samples in rolling window
        shock_accel_threshold=35.0,    # m/s^2 spike threshold for pothole/shock
    ):
        self.fs = sampling_rate_hz
        self.accel_cutoff = min(accel_cutoff_hz, (sampling_rate_hz / 2.0) * 0.95)
        self.gyro_cutoff = min(gyro_cutoff_hz, (sampling_rate_hz / 2.0) * 0.95)
        self.zupt_accel_var_thresh = zupt_accel_var_thresh
        self.zupt_gyro_var_thresh = zupt_gyro_var_thresh
        self.zupt_window = zupt_window_size
        self.shock_thresh = shock_accel_threshold

        # Design Butterworth filters if fs allows
        self._has_filter = (self.fs > 2.0 * self.accel_cutoff)
        if self._has_filter:
            nyq = 0.5 * self.fs
            b_a, a_a = butter(2, self.accel_cutoff / nyq, btype='low')
            b_g, a_g = butter(2, self.gyro_cutoff / nyq, btype='low')
            self.filter_accel_coeffs = (b_a, a_a)
            self.filter_gyro_coeffs = (b_g, a_g)

        # Dynamic Gravity Compensator
        from src.preprocessing.gravity_compensator import GravityCompensator
        self.gravity_compensator = GravityCompensator(
            sampling_rate_hz=self.fs,
            g_val=STANDARD_GRAVITY,
            tilt_fusion_cutoff_hz=0.01,
            enable_gyro_debias=True
        )

    def filter_vibrations(self, signal):
        """
        Apply zero-phase forward-backward Butterworth low-pass filter
        along the time axis (axis 0).
        """
        if not self._has_filter or len(signal) < 15:
            return signal.copy()

        b, a = self.filter_accel_coeffs
        # Filter each axis independently
        filtered = np.zeros_like(signal)
        for i in range(signal.shape[1]):
            filtered[:, i] = filtfilt(b, a, signal[:, i], padlen=min(9, len(signal)-2))
        return filtered

    def suppress_shocks(self, accel):
        """
        Clip extreme impulsive shocks (e.g. sharp potholes, speed-bumps)
        that would otherwise cause quadratic integration drift.
        """
        accel_out = accel.copy()
        mag = np.linalg.norm(accel_out, axis=1, keepdims=True)
        spike_mask = (mag > self.shock_thresh).squeeze()
        if np.any(spike_mask):
            scale = np.ones_like(mag)
            scale[spike_mask] = self.shock_thresh / mag[spike_mask]
            accel_out = accel_out * scale
        return accel_out

    def remove_gravity(self, accel_raw, gyro_raw=None, gravity_measured=None, orientation_quats=None):
        """
        Extract linear body acceleration by removing gravity vector.
        
        Four modes:
          1. Direct subtraction if measured gravity vector is provided (e.g. IO-VNBD S-* smartphone data).
          2. Dynamic 3D rotation state integration with GravityCompensator (when gyro_raw is provided).
          3. Orientation projection: rotate [0, 0, g] into body frame using pre-computed quaternions.
          4. Low-pass estimation: estimate gravity as low-frequency acceleration component.
        """
        if gravity_measured is not None:
            # IO-VNBD provides dedicated GRAVITY X, Y, Z channels
            return accel_raw - gravity_measured

        if gyro_raw is not None and len(gyro_raw) == len(accel_raw):
            # Dynamic 3D quaternion gyro integration with 0.01 Hz complementary tilt fusion
            self.gravity_compensator.reset()
            res = self.gravity_compensator.batch_process(accel_raw, gyro_raw, dt=1.0 / self.fs)
            return res['accel_clean']

        if orientation_quats is not None:
            # Gravity in ENU is [0, 0, -g]. Gravity in body is R_n_to_b @ g_enu
            from src.preprocessing.frame_transform import quaternion_to_rotation_matrix
            linear_accel = np.zeros_like(accel_raw)
            g_nav = np.array([0.0, 0.0, -STANDARD_GRAVITY])
            for k in range(len(accel_raw)):
                R_b_to_n = quaternion_to_rotation_matrix(orientation_quats[k])
                R_n_to_b = R_b_to_n.T
                g_body = R_n_to_b @ g_nav
                linear_accel[k] = accel_raw[k] - g_body
            return linear_accel

        # Low-pass filter approximation of gravity (quasi-static assumption)
        nyq = 0.5 * self.fs
        cutoff = min(0.3, nyq * 0.5)
        b, a = butter(1, cutoff / nyq, btype='low')
        g_est = np.zeros_like(accel_raw)
        for i in range(accel_raw.shape[1]):
            g_est[:, i] = filtfilt(b, a, accel_raw[:, i], padlen=min(9, len(accel_raw)-2))
        return accel_raw - g_est

    def detect_stationary(self, accel, gyro):
        """
        Detect zero-velocity (ZUPT) periods using rolling variance of
        acceleration and angular rate magnitudes.
        Vectorized with uniform_filter1d for high speed.
        Returns boolean 1D array where True indicates the vehicle is stationary.
        """
        N = len(accel)
        if N < self.zupt_window:
            return np.zeros(N, dtype=bool)

        from scipy.ndimage import uniform_filter1d

        acc_mag = np.linalg.norm(accel, axis=1)
        gyr_mag = np.linalg.norm(gyro, axis=1)
        w = self.zupt_window

        mean_a = uniform_filter1d(acc_mag, size=w, mode='nearest')
        mean_a2 = uniform_filter1d(acc_mag**2, size=w, mode='nearest')
        var_a = np.maximum(0.0, mean_a2 - mean_a**2)

        mean_g = uniform_filter1d(gyr_mag, size=w, mode='nearest')
        mean_g2 = uniform_filter1d(gyr_mag**2, size=w, mode='nearest')
        var_g = np.maximum(0.0, mean_g2 - mean_g**2)

        return (var_a < self.zupt_accel_var_thresh) & (var_g < self.zupt_gyro_var_thresh)

    def process(self, accel_raw, gyro_raw, gravity_raw=None, quats=None):
        """
        Complete preprocessing pipeline:
          1. Shock suppression
          2. Vibration low-pass filtering
          3. Gravity removal -> Linear acceleration
          4. Zero-velocity (ZUPT) detection
        """
        acc_safe = self.suppress_shocks(accel_raw)
        acc_filt = self.filter_vibrations(acc_safe)
        gyr_filt = self.filter_vibrations(gyro_raw)

        acc_linear = self.remove_gravity(
            acc_filt,
            gyro_raw=gyr_filt,
            gravity_measured=gravity_raw,
            orientation_quats=quats
        )

        zupt = self.detect_stationary(acc_filt, gyr_filt)

        return {
            'accel_filtered': acc_filt,
            'gyro_filtered': gyr_filt,
            'accel_linear': acc_linear,
            'zupt_mask': zupt,
            'sampling_rate_hz': self.fs
        }
