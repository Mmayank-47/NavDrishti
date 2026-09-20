import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/vehicle_marker.dart';

/// Screen: SETTINGS SCREEN
///
/// Principles:
/// - Branded HUD design with glassmorphic cards and soft borders
/// - CONFIDENCE VISUALIZATION legend (GNSS, Fused, INS, Degraded, Emergency)
///   plus custom color pickers (excluding red)
/// - VEHICLE ICON (Arrow, 3D Car, 3D Bike) with preview markers
/// - APPEARANCE (Follow System, Dark Mode, Light Mode)
/// - Units, Sensor Source, Recalibrate, and Backend connection settings
class SettingsScreen extends StatelessWidget {
  final VoidCallback? onRecalibrate;
  final bool showBackButton;

  const SettingsScreen({
    super.key,
    this.onRecalibrate,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final blueColor = isDark ? AppColors.darkBlue : AppColors.lightBlue;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: showBackButton
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: primaryTextColor),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          'Settings',
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          children: [
            // 1. CONFIDENCE VISUALIZATION & COLOR SYSTEM
            _SectionHeader(
              title: 'CONFIDENCE VISUALIZATION',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
            ),
            const SizedBox(height: 8),

            Material(
              color: surfaceColor.withValues(alpha: isDark ? 0.90 : 0.95),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: isDark ? borderColor : AppColors.lightBlue.withValues(alpha: 0.22), width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Custom Color Pickers
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 16, right: 16),
                    child: Text(
                      'CONFIDENCE HALO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                  _ColorPickerRow(
                    title: 'GNSS Aided Color',
                    subtitle: 'Normal satellite-locked confidence halo',
                    selectedColor: settings.customGnssColor,
                    defaultColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
                    onColorSelected: (col) => settings.setCustomGnssColor(col),
                    primaryTextColor: primaryTextColor,
                    secondaryTextColor: secondaryTextColor,
                  ),
                  Divider(color: borderColor, height: 1),
                  _ColorPickerRow(
                    title: 'Dead Reckoning Color',
                    subtitle: 'Inertial navigation confidence halo',
                    selectedColor: settings.customDrColor,
                    defaultColor: isDark ? AppColors.darkViolet : AppColors.lightViolet,
                    onColorSelected: (col) => settings.setCustomDrColor(col),
                    primaryTextColor: primaryTextColor,
                    secondaryTextColor: secondaryTextColor,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 14, top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: secondaryTextColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Red is strictly reserved for SOS / Emergency alerts and cannot be selected.',
                            style: TextStyle(color: secondaryTextColor, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 2. VEHICLE ICON STYLE SECTION
            _SectionHeader(
              title: 'VEHICLE ICON STYLE',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
            ),
            const SizedBox(height: 8),

            Material(
              color: surfaceColor.withValues(alpha: isDark ? 0.90 : 0.95),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: isDark ? borderColor : AppColors.lightBlue.withValues(alpha: 0.22), width: 1.0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: RadioGroup<VehicleIconStyle>(
                  groupValue: settings.vehicleIconStyle,
                  onChanged: (val) {
                    if (val != null) settings.setVehicleIconStyle(val);
                  },
                  child: Column(
                    children: [
                      RadioListTile<VehicleIconStyle>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Arrow (Directional)', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                        subtitle: Text('Flat minimalist navigation chevron', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                        secondary: SizedBox(
                          width: 34,
                          height: 34,
                          child: VehicleMarker(
                            heading: 0,
                            isDeadReckoning: false,
                            isDark: isDark,
                            iconStyle: VehicleIconStyle.arrow,
                          ),
                        ),
                        value: VehicleIconStyle.arrow,
                      ),
                      Divider(color: borderColor, height: 1),
                      RadioListTile<VehicleIconStyle>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('3D Car (Automobile)', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                        subtitle: Text('Isometric angled passenger car', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                        secondary: SizedBox(
                          width: 34,
                          height: 34,
                          child: VehicleMarker(
                            heading: 0,
                            isDeadReckoning: false,
                            isDark: isDark,
                            iconStyle: VehicleIconStyle.car,
                          ),
                        ),
                        value: VehicleIconStyle.car,
                      ),
                      Divider(color: borderColor, height: 1),
                      RadioListTile<VehicleIconStyle>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('3D Bike (Two-Wheeler)', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                        subtitle: Text('Isometric angled commuter motorcycle', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                        secondary: SizedBox(
                          width: 34,
                          height: 34,
                          child: VehicleMarker(
                            heading: 0,
                            isDeadReckoning: false,
                            isDark: isDark,
                            iconStyle: VehicleIconStyle.bike,
                          ),
                        ),
                        value: VehicleIconStyle.bike,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 3. APPEARANCE SECTION
            _SectionHeader(
              title: 'APPEARANCE',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
            ),
            const SizedBox(height: 8),

            Material(
              color: surfaceColor.withValues(alpha: isDark ? 0.90 : 0.95),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: isDark ? borderColor : AppColors.lightBlue.withValues(alpha: 0.22), width: 1.0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: RadioGroup<AppThemePreference>(
                  groupValue: settings.themePreference,
                  onChanged: (val) {
                    if (val != null) settings.setThemePreference(val);
                  },
                  child: Column(
                    children: [
                      RadioListTile<AppThemePreference>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Follow System', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                        subtitle: Text('Match device light/dark mode', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                        secondary: Icon(Icons.brightness_auto, color: isDark ? secondaryTextColor : AppColors.lightBlue),
                        value: AppThemePreference.system,
                      ),
                      Divider(color: isDark ? borderColor : AppColors.lightBlue.withValues(alpha: 0.15), height: 1),
                      RadioListTile<AppThemePreference>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Dark Mode', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                        subtitle: Text('Deep navy-black HUD visual style', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                        secondary: Icon(Icons.dark_mode_rounded, color: isDark ? secondaryTextColor : AppColors.lightViolet),
                        value: AppThemePreference.dark,
                      ),
                      Divider(color: isDark ? borderColor : AppColors.lightBlue.withValues(alpha: 0.15), height: 1),
                      RadioListTile<AppThemePreference>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Light Mode', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                        subtitle: Text('High contrast daytime palette', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                        secondary: Icon(Icons.light_mode_rounded, color: isDark ? secondaryTextColor : AppColors.lightAmber),
                        value: AppThemePreference.light,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 4. UNITS & SENSORS SECTION
            _SectionHeader(
              title: 'PREFERENCES & SENSORS',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
            ),
            const SizedBox(height: 8),

            Material(
              color: surfaceColor.withValues(alpha: isDark ? 0.90 : 0.95),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: isDark ? borderColor : AppColors.lightBlue.withValues(alpha: 0.22), width: 1.0),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text('Metric Units', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      settings.useMetricUnits ? 'km and km/h' : 'mi and mph',
                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                    ),
                    value: settings.useMetricUnits,
                    onChanged: (val) => settings.setMetricUnits(val),
                  ),
                  Divider(color: borderColor, height: 1),
                  ListTile(
                    title: Text('Phone Internal Sensors', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                    subtitle: Text('Using device built-in Accelerometer & Gyroscope', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                    trailing: Icon(Icons.sensors_rounded, color: blueColor),
                  ),
                  Divider(color: borderColor, height: 1),
                  ListTile(
                    title: Text('Recalibrate Sensors', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                    subtitle: Text('Perform 10-second forward vehicle alignment', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: secondaryTextColor),
                    onTap: () {
                      if (showBackButton) {
                        Navigator.of(context).pop();
                      }
                      onRecalibrate?.call();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color textColor;
  final Color? accentColor;

  const _SectionHeader({
    required this.title,
    required this.textColor,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Row(
        children: [
          if (accentColor != null) ...[
            Container(
              width: 4,
              height: 12,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color? selectedColor;
  final Color defaultColor;
  final ValueChanged<Color?> onColorSelected;
  final Color primaryTextColor;
  final Color secondaryTextColor;

  const _ColorPickerRow({
    required this.title,
    required this.subtitle,
    required this.selectedColor,
    required this.defaultColor,
    required this.onColorSelected,
    required this.primaryTextColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final currentColor = selectedColor ?? defaultColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: currentColor.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: kAllowedHaloColors.map((opt) {
                final isSelected = currentColor.toARGB32() == opt.color.toARGB32();
                return GestureDetector(
                  onTap: () {
                    onColorSelected(opt.color);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: opt.color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2.5)
                          : Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.0),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: opt.color.withValues(alpha: 0.8),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
