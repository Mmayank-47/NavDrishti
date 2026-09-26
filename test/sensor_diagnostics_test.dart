import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:nav_shield/screens/sensor_diagnostics_screen.dart';

void main() {
  group('SensorDiagnosticsScreen Widget Tests', () {
    testWidgets('Renders local-only banner and Step 1 Tilt Phone RIGHT (7 total steps)', (tester) async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();
      final magController = StreamController<MagnetometerEvent>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: SensorDiagnosticsScreen(
            customAccelerometerStream: accelController.stream,
            customGyroscopeStream: gyroController.stream,
            customMagnetometerStream: magController.stream,
          ),
        ),
      );

      // Verify title & Local-Only banner
      expect(find.text('Sensor Diagnostics'), findsOneWidget);
      expect(find.text("Reading live from this device's sensors (Local-Only)"), findsOneWidget);
      expect(find.text("Direct hardware telemetry · Completely independent of Python backend"), findsOneWidget);

      // Verify step 1 of 7
      expect(find.text('STEP 1 OF 7'), findsOneWidget);
      expect(find.text('Tilt Phone RIGHT'), findsOneWidget);
      expect(find.text('Roll Axis — Negative X Acceleration'), findsOneWidget);
      expect(find.text('X ≤ -2.2 m/s²'), findsOneWidget);

      // Verify Live Readout card
      expect(find.text('LIVE HARDWARE READOUT'), findsOneWidget);
      expect(find.text('ACCELEROMETER (m/s²)'), findsOneWidget);
      expect(find.text('GYROSCOPE (rad/s)'), findsOneWidget);
      expect(find.text('MAGNETOMETER (µT) & COMPASS'), findsOneWidget);

      await accelController.close();
      await gyroController.close();
      await magController.close();
    });

    testWidgets('Live numeric values update when sensor streams emit including magnetometer', (tester) async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();
      final magController = StreamController<MagnetometerEvent>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: SensorDiagnosticsScreen(
            customAccelerometerStream: accelController.stream,
            customGyroscopeStream: gyroController.stream,
            customMagnetometerStream: magController.stream,
          ),
        ),
      );

      // Emit sensor events
      accelController.add(AccelerometerEvent(-1.50, 2.34, 9.81, DateTime.now()));
      gyroController.add(GyroscopeEvent(0.05, -0.12, 0.45, DateTime.now()));
      magController.add(MagnetometerEvent(18.5, -32.4, 45.0, DateTime.now()));
      await tester.pump();

      // Check numeric readouts
      expect(find.text('-1.50'), findsOneWidget);
      expect(find.text('+2.34'), findsOneWidget);
      expect(find.text('+9.81'), findsOneWidget);
      expect(find.text('+0.05'), findsOneWidget);
      expect(find.text('-0.12'), findsOneWidget);
      expect(find.text('+0.45'), findsOneWidget);
      expect(find.text('+18.50'), findsOneWidget);
      expect(find.text('-32.40'), findsOneWidget);
      expect(find.text('+45.00'), findsOneWidget);

      await accelController.close();
      await gyroController.close();
      await magController.close();
    });

    testWidgets('Auto-advances step when expected motion threshold is reached', (tester) async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: SensorDiagnosticsScreen(
            customAccelerometerStream: accelController.stream,
            customGyroscopeStream: gyroController.stream,
          ),
        ),
      );

      expect(find.text('Tilt Phone RIGHT'), findsOneWidget);

      // Trigger threshold for Step 1: X <= -2.2
      accelController.add(AccelerometerEvent(-2.85, 0.1, 9.81, DateTime.now()));
      await tester.pump();

      // Should show pass confirmation
      expect(find.text('Motion Confirmed! Advancing...'), findsOneWidget);

      // Wait for 800ms auto-advance delay
      await tester.pump(const Duration(milliseconds: 900));

      // Should now be on Step 2 of 7: Tilt Phone LEFT
      expect(find.text('STEP 2 OF 7'), findsOneWidget);
      expect(find.text('Tilt Phone LEFT'), findsOneWidget);

      await accelController.close();
      await gyroController.close();
    });

    testWidgets('Magnetometer step 7 detects >= 180° rotation and passes', (tester) async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();
      final magController = StreamController<MagnetometerEvent>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: SensorDiagnosticsScreen(
            customAccelerometerStream: accelController.stream,
            customGyroscopeStream: gyroController.stream,
            customMagnetometerStream: magController.stream,
          ),
        ),
      );

      // Skip first 6 steps to reach Step 7
      for (int i = 0; i < 6; i++) {
        await tester.tap(find.text('Skip'));
        await tester.pump();
      }

      // Verify Step 7 is active
      expect(find.text('STEP 7 OF 7'), findsOneWidget);
      expect(find.text('Rotate Phone Flat (Compass Check)'), findsOneWidget);

      // Emit starting magnetometer reading (North: x=0, y=10 => heading ~90°)
      magController.add(MagnetometerEvent(0.0, 10.0, 30.0, DateTime.now()));
      await tester.pump();

      // Rotate 90° (East: x=10, y=0 => heading ~0°)
      magController.add(MagnetometerEvent(10.0, 0.0, 30.0, DateTime.now()));
      await tester.pump();

      // Rotate another 90° (South: x=0, y=-10 => heading ~270°)
      magController.add(MagnetometerEvent(0.0, -10.0, 30.0, DateTime.now()));
      await tester.pump();

      // Should confirm pass (accumulated heading delta >= 180°)
      expect(find.text('Motion Confirmed! Advancing...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 900));

      // Reaches summary screen
      expect(find.textContaining('Diagnostics Completed'), findsOneWidget);
      expect(find.text('Rotate Phone Flat (Compass Check)'), findsOneWidget);

      await accelController.close();
      await gyroController.close();
      await magController.close();
    });

    testWidgets('Manual skip through all 7 steps reaches Summary Screen', (tester) async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: SensorDiagnosticsScreen(
            customAccelerometerStream: accelController.stream,
            customGyroscopeStream: gyroController.stream,
          ),
        ),
      );

      // Skip through all 7 steps
      for (int i = 0; i < 7; i++) {
        final skipBtn = find.text('Skip');
        expect(skipBtn, findsOneWidget);
        await tester.tap(skipBtn);
        await tester.pump();
      }

      // Summary screen should be reached
      expect(find.textContaining('Diagnostics Completed (0/7 Passed)'), findsOneWidget);
      expect(find.text('Restart Test'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await accelController.close();
      await gyroController.close();
    });
  });
}
