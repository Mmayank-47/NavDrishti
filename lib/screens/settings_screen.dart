import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/galaxy_background.dart';
import '../widgets/liquid_glass_card.dart';
import '../widgets/vehicle_marker.dart';
import 'permissions_onboarding_screen.dart';

/// Screen: SETTINGS SCREEN
///
/// Principles:
/// - Branded HUD design with glassmorphic cards and soft borders
/// - CONFIDENCE VISUALIZATION legend (GNSS, Fused, INS, Degraded, Emergency)
///   plus custom color pickers (excluding red)
/// - VEHICLE ICON (Arrow, 3D Car, 3D Bike) with preview markers
/// - APPEARANCE (Follow System, Dark Mode, Light Mode)
/// - Units, Sensor Source, and Backend connection settings
class SettingsScreen extends StatelessWidget {
  final bool showBackButton;

  const SettingsScreen({
    super.key,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final blueColor = isDark ? AppColors.darkBlue : AppColors.lightBlue;

    return Scaffold(
      backgroundColor: Colors.transparent,
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
      body: GalaxyBackground(
        child: SafeArea(
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

            LiquidGlassCard(
              glowColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
              padding: EdgeInsets.zero,
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

            LiquidGlassCard(
              glowColor: isDark ? AppColors.darkBlue : AppColors.lightBlue,
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

            const SizedBox(height: 22),

            // 3. APPEARANCE SECTION
            _SectionHeader(
              title: 'APPEARANCE',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
            ),
            const SizedBox(height: 8),

            LiquidGlassCard(
              glowColor: isDark ? AppColors.darkViolet : AppColors.lightViolet,
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
                      subtitle: Text('Deep obsidian-black HUD visual style', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                      secondary: Icon(Icons.dark_mode_rounded, color: isDark ? secondaryTextColor : AppColors.lightViolet),
                      value: AppThemePreference.dark,
                    ),
                    Divider(color: isDark ? borderColor : AppColors.lightBlue.withValues(alpha: 0.15), height: 1),
                    RadioListTile<AppThemePreference>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Light Mode', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                      subtitle: Text('High contrast daytime frosted palette', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                      secondary: Icon(Icons.light_mode_rounded, color: isDark ? secondaryTextColor : AppColors.lightAmber),
                      value: AppThemePreference.light,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 4. SENSOR SOURCE SECTION (Item 1)
            _SectionHeader(
              title: 'SENSOR SOURCE',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
            ),
            const SizedBox(height: 8),

            LiquidGlassCard(
              glowColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
              padding: EdgeInsets.zero,
              child: RadioGroup<ImuSource>(
                groupValue: settings.imuSource,
                onChanged: (val) {
                  if (val != null) settings.setImuSource(val);
                },
                child: Column(
                  children: [
                    RadioListTile<ImuSource>(
                      title: Text(
                        'Phone Sensors',
                        style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Built-in Accelerometer & Gyroscope (Default)',
                        style: TextStyle(color: secondaryTextColor, fontSize: 12),
                      ),
                      secondary: Icon(Icons.phone_android_rounded, color: blueColor),
                      value: ImuSource.phoneSensors,
                    ),
                    Divider(color: borderColor, height: 1),
                    RadioListTile<ImuSource>(
                      title: Text(
                        'External IMU',
                        style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Hardware FOG / MEMS Interface (NAV-SHIELD Edge)',
                        style: TextStyle(color: secondaryTextColor, fontSize: 12),
                      ),
                      secondary: Icon(Icons.developer_board_rounded, color: blueColor),
                      value: ImuSource.externalImu,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            // 5. PREFERENCES & TOOLS SECTION
            _SectionHeader(
              title: 'PREFERENCES & TOOLS',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
            ),
            const SizedBox(height: 8),

            LiquidGlassCard(
              glowColor: isDark ? AppColors.darkCyan : AppColors.lightBlue,
              padding: EdgeInsets.zero,
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
                    title: Text('App & Sensor Permissions', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                    subtitle: Text('Manage location, motion sensors, and notification access', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                    trailing: Icon(Icons.security_rounded, color: blueColor),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PermissionsOnboardingScreen(isModalFromSettings: true),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 6. EMERGENCY CONTACT & SOS
            _SectionHeader(
              title: 'EMERGENCY CONTACT & SOS',
              textColor: secondaryTextColor,
              accentColor: isDark ? AppColors.darkRed : AppColors.lightRed,
            ),
            const SizedBox(height: 8),

            LiquidGlassCard(
              glowColor: isDark ? AppColors.darkRed : AppColors.lightRed,
              borderColor: (isDark ? AppColors.darkRed : AppColors.lightRed).withValues(alpha: 0.40),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (isDark ? AppColors.darkRed : AppColors.lightRed)
                            .withValues(alpha: 0.18),
                        border: Border.all(
                          color: (isDark ? AppColors.darkRed : AppColors.lightRed).withValues(alpha: 0.45),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? AppColors.darkRed : AppColors.lightRed).withValues(alpha: 0.30),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.contact_emergency_rounded,
                        color: isDark ? AppColors.darkRed : AppColors.lightRed,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      settings.hasEmergencyContact
                          ? settings.emergencyContactName
                          : 'No Emergency Contact Configured',
                      style: TextStyle(
                        color: primaryTextColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      settings.hasEmergencyContact
                          ? '${settings.emergencyContactPhone} · ${settings.emergencyContactRelation}'
                          : 'Tap to configure contact for crash dispatch alerts',
                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.edit_rounded, color: isDark ? AppColors.darkCyan : AppColors.lightBlue, size: 20),
                      onPressed: () => _showEmergencyContactDialog(context, settings),
                    ),
                    onTap: () => _showEmergencyContactDialog(context, settings),
                  ),
                  if (settings.hasEmergencyContact) ...[
                    Divider(color: borderColor, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Notified on crash countdown expiry',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                          TextButton(
                            onPressed: () => settings.clearEmergencyContact(),
                            child: Text(
                              'Remove',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkRed : AppColors.lightRed,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }

  void _showEmergencyContactDialog(BuildContext context, SettingsService settings) {
    final nameController = TextEditingController(text: settings.emergencyContactName);
    final phoneController = TextEditingController(text: settings.emergencyContactPhone);
    final relationController = TextEditingController(text: settings.emergencyContactRelation);

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryText = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
        final secondaryText = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
        final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
        final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightBlue;

        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          title: Text(
            'Emergency Contact Setup',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: primaryText,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This contact will receive automated SMS/distress telemetry if a vehicle impact or SOS alert timer expires.',
                  style: TextStyle(fontSize: 12, color: secondaryText),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: primaryText),
                  decoration: InputDecoration(
                    labelText: 'Contact Full Name',
                    labelStyle: TextStyle(color: secondaryText),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: primaryText),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: TextStyle(color: secondaryText),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: relationController,
                  style: TextStyle(color: primaryText),
                  decoration: InputDecoration(
                    labelText: 'Relationship (e.g. Sister, Spouse, Friend)',
                    labelStyle: TextStyle(color: secondaryText),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: secondaryText)),
            ),
            FilledButton(
              onPressed: () {
                settings.setEmergencyContact(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  relation: relationController.text.trim().isEmpty ? 'Contact' : relationController.text.trim(),
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Emergency contact saved successfully')),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: cyanColor),
              child: const Text('Save Contact'),
            ),
          ],
        );
      },
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
