import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
import '../services/trip_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/galaxy_background.dart';
import '../widgets/liquid_glass_card.dart';
import 'destination_entry_screen.dart';

/// Screen: PERMISSIONS ONBOARDING & RESILIENCE SETUP
///
/// Principles:
/// - Explicitly requests and explains permissions needed for GPS-denied navigation:
///   1. Location (GNSS/GPS tracking and boundary fix)
///   2. Motion & Sensors (IMU accelerometer, gyroscope, magnetometer for Dead Reckoning)
///   3. Notifications & SOS (Persistent lock-screen status & emergency SOS alerts)
///   4. Floating Mini-Nav (Picture-in-Picture / overlay window when minimized)
/// - Plain-language explanations of WHY each permission is necessary
/// - Graceful handling when a user denies any permission with clear functionality limits
/// - Re-accessible from Settings to audit or update permissions at any time
class PermissionsOnboardingScreen extends StatefulWidget {
  final bool isModalFromSettings;

  const PermissionsOnboardingScreen({
    super.key,
    this.isModalFromSettings = false,
  });

  @override
  State<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState
    extends State<PermissionsOnboardingScreen> {
  bool _locationGranted = true;
  bool _sensorsGranted = true;
  bool _notificationsGranted = true;
  bool _overlayGranted = true;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _locationGranted = prefs.getBool('perm_location_granted') ?? true;
      _sensorsGranted = prefs.getBool('perm_sensors_granted') ?? true;
      _notificationsGranted = prefs.getBool('perm_notifications_granted') ?? true;
      _overlayGranted = prefs.getBool('perm_overlay_granted') ?? true;
    });
  }

  Future<void> _savePermission(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _promptEmergencyContactIfNeeded() async {
    final settings = context.read<SettingsService>();
    if (settings.hasEmergencyContact) return;

    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final primary = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
        final secondary = isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
        final cyan = isDark ? AppColors.darkCyan : AppColors.lightBlue;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xF20B132B),
                        const Color(0xFA030712),
                      ]
                    : [
                        Colors.white,
                        const Color(0xF2F1F5F9),
                      ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkLuminousBorder : const Color(0x80CBD5E1),
                  width: 1.2,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.60 : 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.darkRed : AppColors.lightRed).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (isDark ? AppColors.darkRed : AppColors.lightRed).withValues(alpha: 0.40),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        Icons.contact_emergency_rounded,
                        color: isDark ? AppColors.darkRed : AppColors.lightRed,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emergency Contact Setup',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                          Text(
                            'Alerted with coordinates upon crash detection or SOS',
                            style: TextStyle(fontSize: 12, color: secondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const ValueKey('sos_contact_name_field'),
                  controller: nameController,
                  style: TextStyle(color: primary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Contact Full Name',
                    hintText: 'e.g. Priya Sharma',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('sos_contact_phone_field'),
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: primary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+91 98765 43210',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('sos_contact_skip_button'),
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Skip For Now'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('sos_contact_save_button'),
                        onPressed: () async {
                          if (nameController.text.trim().isNotEmpty &&
                              phoneController.text.trim().isNotEmpty) {
                            await settings.setEmergencyContact(
                              name: nameController.text.trim(),
                              phone: phoneController.text.trim(),
                              relation: 'Emergency Contact',
                            );
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: cyan,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save Contact'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_onboarding', true);

    // Initialize notification service if granted
    if (_notificationsGranted) {
      await TripNotificationService.instance.initialize();
      await TripNotificationService.instance.requestPermissions();
    }

    if (!mounted) return;

    if (widget.isModalFromSettings) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, secondaryAnimation) => const DestinationEntryScreen(),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText =
        isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final secondaryText =
        isDark ? AppColors.darkSecondaryText : AppColors.lightSecondaryText;
    final surfaceColor =
        isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor =
        isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cyanColor = isDark ? AppColors.darkCyan : AppColors.lightBlue;
    final amberColor = isDark ? AppColors.darkAmber : AppColors.lightAmber;
    final greenColor = isDark ? AppColors.darkGreen : AppColors.lightGreen;
    final redColor = isDark ? AppColors.darkRed : AppColors.lightRed;

    final anyDenied = !_locationGranted || !_sensorsGranted || !_notificationsGranted || !_overlayGranted;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isModalFromSettings
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.close_rounded, color: primaryText),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                'Sensor & OS Permissions',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : null,
      body: GalaxyBackground(
        child: SafeArea(
          child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          children: [
            if (!widget.isModalFromSettings) ...[
              const SizedBox(height: 12),
              // Brand Icon Header
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cyanColor.withValues(alpha: 0.16),
                    border: Border.all(
                      color: cyanColor.withValues(alpha: 0.40),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cyanColor.withValues(alpha: 0.25),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Icon(Icons.shield_rounded, size: 34, color: cyanColor),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'Welcome to NAV-SHIELD',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: primaryText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'To maintain centimeter-level vehicle tracking through tunnels, basements, and satellite blackouts, NAV-SHIELD requires four essential device access points:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: secondaryText,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 1. Location Permission Card
            _PermissionTile(
              icon: Icons.location_on_rounded,
              iconColor: cyanColor,
              title: 'Location & Satellite Fix',
              badge: _locationGranted ? 'GRANTED' : 'DENIED',
              badgeColor: _locationGranted ? greenColor : redColor,
              isGranted: _locationGranted,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              primaryText: primaryText,
              secondaryText: secondaryText,
              explanation:
                  'Acquires initial GNSS coordinates before entering tunnels and re-synchronizes when satellite signals recover.',
              limitationText:
                  'Without location access, real GPS coordinates cannot be initialized. App will rely exclusively on manual map pins.',
              onToggle: (val) {
                setState(() => _locationGranted = val);
                _savePermission('perm_location_granted', val);
              },
            ),

            const SizedBox(height: 14),

            // 2. Motion & Activity Sensors Permission Card
            _PermissionTile(
              icon: Icons.sensors_rounded,
              iconColor: isDark ? AppColors.darkViolet : AppColors.lightViolet,
              title: 'Motion & Inertial Sensors',
              badge: _sensorsGranted ? 'GRANTED' : 'DENIED',
              badgeColor: _sensorsGranted ? greenColor : redColor,
              isGranted: _sensorsGranted,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              primaryText: primaryText,
              secondaryText: secondaryText,
              explanation:
                  'Reads high-frequency accelerometer and gyroscope data to calculate displacement during Dead Reckoning navigation.',
              limitationText:
                  'Without motion sensors, inertial dead reckoning cannot function in underground parking garages or tunnels.',
              onToggle: (val) {
                setState(() => _sensorsGranted = val);
                _savePermission('perm_sensors_granted', val);
              },
            ),

            const SizedBox(height: 14),

            // 3. Notifications Permission Card
            _PermissionTile(
              icon: Icons.notifications_active_rounded,
              iconColor: amberColor,
              title: 'Lock-Screen & SOS Alerts',
              badge: _notificationsGranted ? 'GRANTED' : 'DENIED',
              badgeColor: _notificationsGranted ? greenColor : redColor,
              isGranted: _notificationsGranted,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              primaryText: primaryText,
              secondaryText: secondaryText,
              explanation:
                  'Maintains a persistent background trip progress indicator and broadcasts automated crash dispatch confirmations.',
              limitationText:
                  'Lock-screen status updates and background mode transitions will not be visible.',
              onToggle: (val) {
                setState(() => _notificationsGranted = val);
                _savePermission('perm_notifications_granted', val);
                if (val) {
                  _promptEmergencyContactIfNeeded();
                }
              },
            ),

            const SizedBox(height: 14),

            // 4. Floating Mini-Nav (Picture-in-Picture)
            _PermissionTile(
              icon: Icons.picture_in_picture_alt_rounded,
              iconColor: cyanColor,
              title: 'Floating Mini-Nav (PiP / Overlay)',
              badge: _overlayGranted ? 'GRANTED' : 'DENIED',
              badgeColor: _overlayGranted ? greenColor : redColor,
              isGranted: _overlayGranted,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              primaryText: primaryText,
              secondaryText: secondaryText,
              explanation:
                  'Renders a compact floating navigation tile over other apps when minimized, showing turn arrows, distance, and live ETA.',
              limitationText:
                  'If denied, NAV-SHIELD falls back gracefully to standard lock-screen and status-bar notifications.',
              onToggle: (val) {
                setState(() => _overlayGranted = val);
                _savePermission('perm_overlay_granted', val);
              },
            ),

            const SizedBox(height: 20),

            // Graceful Denial Warning Banner
            if (anyDenied)
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: amberColor.withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: amberColor.withValues(alpha: 0.50),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: amberColor, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Degraded Resiliency Notice',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: amberColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'One or more permissions are currently denied. NAV-SHIELD will still run, but features requiring hardware access will operate in simulated fallback mode.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Action: Complete Onboarding / Confirm Settings (Glowing Cyan Gradient)
            Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: AppColors.cyanGlowGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.darkCyan.withValues(alpha: 0.40),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _completeOnboarding,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: const Color(0xFF030712),
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  widget.isModalFromSettings
                      ? 'Save & Return'
                      : (anyDenied
                          ? 'Continue with Limited Features'
                          : 'Grant & Launch NAV-SHIELD'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: Color(0xFF030712),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String badge;
  final Color badgeColor;
  final bool isGranted;
  final bool isDark;
  final Color surfaceColor;
  final Color borderColor;
  final Color primaryText;
  final Color secondaryText;
  final String explanation;
  final String limitationText;
  final ValueChanged<bool> onToggle;

  const _PermissionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.isGranted,
    required this.isDark,
    required this.surfaceColor,
    required this.borderColor,
    required this.primaryText,
    required this.secondaryText,
    required this.explanation,
    required this.limitationText,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      glowColor: isGranted ? iconColor : AppColors.darkRed,
      borderColor: isGranted
          ? (isDark ? iconColor.withValues(alpha: 0.35) : borderColor)
          : AppColors.darkRed.withValues(alpha: 0.45),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: isDark ? 0.20 : 0.15),
                  border: Border.all(color: iconColor.withValues(alpha: 0.4), width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isGranted,
                activeThumbColor: iconColor,
                activeTrackColor: iconColor.withValues(alpha: 0.35),
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            explanation,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: secondaryText,
            ),
          ),
          if (!isGranted) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      limitationText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.redAccent,
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
    );
  }
}
