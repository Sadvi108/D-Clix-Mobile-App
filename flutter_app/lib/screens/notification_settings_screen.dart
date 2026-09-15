import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notification_prefs.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';

String _fmtHour(int h) => '${h.toString().padLeft(2, '0')}:00';

/// Port of `frontend/app/notification-settings.tsx` (Expo v2.11.1).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  NotifPrefs _p = NotifPrefsStore.peek() ?? NotifPrefs.defaults;
  bool _permitted = true;
  bool _testing = false;
  String? _picking; // 'start' | 'end'
  void Function()? _unsub;

  @override
  void initState() {
    super.initState();
    _unsub = NotifPrefsStore.subscribe((p) {
      if (mounted) setState(() => _p = p);
    });
    _load();
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await NotifPrefsStore.load();
      final ok = await NotificationService.hasPermission();
      if (mounted) {
        setState(() {
          _p = p;
          _permitted = ok;
        });
      }
    } catch (e) {
      debugPrint('notification settings load failed: $e');
    }
  }

  Future<void> _update(NotifPrefs next) async {
    setState(() => _p = next);
    await NotifPrefsStore.save(next);
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      if (!_permitted) {
        final granted = await NotificationService.requestPermission();
        if (mounted) setState(() => _permitted = granted);
        if (!granted) {
          if (mounted) {
            await notify(
                context,
                'Notifications are off',
                kIsWeb
                    ? 'Allow notifications for this site in your browser, then try again.'
                    : 'Enable notifications for D-CLIX in your device settings, then try again.');
          }
          return;
        }
      }
      final shown = await NotificationService.sendTestAlert();
      if (!shown && mounted) {
        // The test alert ignores quiet hours and category mutes; only the master switch blocks it.
        await notify(
            context,
            'Nothing was sent',
            !_p.enabled
                ? 'Push notifications are turned off above.'
                : 'This device would not show the notification. Check that alerts are allowed for D-CLIX.');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      final ok = await launchUrl(Uri.parse('app-settings:'));
      if (!ok) throw Exception('unsupported');
    } catch (_) {
      if (mounted) await notify(context, 'Open your device settings', 'Find D-CLIX in the app list and allow notifications.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final p = _p;

    Widget row({required IconData icon, required String title, required String sub, required bool value,
        required ValueChanged<bool> onChange, bool disabled = false}) {
      return Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 17 / 12)),
              ]),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: value,
              onChanged: disabled ? null : onChange,
              activeTrackColor: c.primary,
              inactiveTrackColor: c.border,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
          ]),
        ),
      );
    }

    Widget divider() => Container(height: 1, color: c.border);
    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
        );
    BoxDecoration card() => rnCard(c);

    Widget hourChip(String label, int hour, String key) => Expanded(
          child: Touchable(
            onPress: () => setState(() => _picking = _picking == key ? null : key),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: _picking == key ? c.primary : Colors.transparent),
              ),
              child: Column(children: [
                Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_fmtHour(hour), style: TextStyle(fontSize: 16, color: c.textPrimary, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Notification settings', horizontal: Gaps.lg),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 60),
            children: [
              // Permission banner — nothing below matters while the OS is blocking us.
              if (!_permitted)
                Touchable(
                  activeOpacity: 0.85,
                  onPress: kIsWeb ? null : _openSystemSettings,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(color: c.danger.hexA('66')),
                    ),
                    child: Row(children: [
                      Icon(Ion.warning, size: 20, color: c.danger),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Alerts are blocked', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                              kIsWeb
                                  ? 'This browser is blocking notifications for the site. Allow them in the address-bar site settings.'
                                  : 'Tap to open system settings and allow notifications for D-CLIX.',
                              style: TextStyle(fontSize: 12, color: c.textSecondary, height: 17 / 12)),
                        ]),
                      ),
                      if (!kIsWeb) ...[const SizedBox(width: 12), Icon(Ion.chevronForward, size: 18, color: c.textMuted)],
                    ]),
                  ),
                ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: card(),
                child: Column(children: [
                  row(icon: Ion.notifications, title: 'Push notifications', sub: 'Alerts on your lock screen and notification tray',
                      value: p.enabled, onChange: (v) => _update(p.copyWith(enabled: v))),
                  divider(),
                  row(icon: Ion.volumeHigh, title: 'Sound', sub: 'Play the D-CLIX chime', value: p.sound, disabled: !p.enabled,
                      onChange: (v) => _update(p.copyWith(sound: v))),
                  divider(),
                  row(icon: Ion.phonePortrait, title: 'Vibration', sub: 'Buzz when an alert arrives', value: p.vibrate,
                      disabled: !p.enabled, onChange: (v) => _update(p.copyWith(vibrate: v))),
                ]),
              ),

              Opacity(
                opacity: _testing ? 0.6 : 1,
                child: Touchable(
                  activeOpacity: 0.85,
                  onPress: _testing ? null : _test,
                  child: Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(Radii.lg)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Ion.playCircle, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(_testing ? 'Sending…' : 'Send a test notification',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ),

              sectionTitle('What to alert me about'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: card(),
                child: Column(children: [
                  for (final (i, cat) in NotifCategory.values.indexed) ...[
                    if (i > 0) divider(),
                    row(
                      icon: switch (cat) { NotifCategory.payments => Ion.wallet, NotifCategory.classes => Ion.barbell, NotifCategory.general => Ion.megaphone },
                      title: cat.label,
                      sub: cat.hint,
                      value: p.categories[cat] ?? true,
                      disabled: !p.enabled,
                      onChange: (v) => _update(p.copyWith(categories: {...p.categories, cat: v})),
                    ),
                  ],
                ]),
              ),

              sectionTitle('Quiet hours'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: card(),
                child: Column(children: [
                  row(
                    icon: Ion.moon,
                    title: 'Silence overnight',
                    sub: p.quietEnabled
                        ? 'No alerts from ${_fmtHour(p.quietStartHour)} to ${_fmtHour(p.quietEndHour)}'
                        : 'Alerts arrive at any hour',
                    value: p.quietEnabled,
                    disabled: !p.enabled,
                    onChange: (v) => _update(p.copyWith(quietEnabled: v)),
                  ),
                  if (p.quietEnabled) ...[
                    divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(children: [
                        hourChip('From', p.quietStartHour, 'start'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(Ion.arrowForward, size: 16, color: c.textMuted),
                        ),
                        hourChip('To', p.quietEndHour, 'end'),
                      ]),
                    ),
                    if (_picking != null)
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 14),
                          itemCount: 24,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, h) {
                            final active = _picking == 'start' ? h == p.quietStartHour : h == p.quietEndHour;
                            return Touchable(
                              onPress: () {
                                _update(_picking == 'start' ? p.copyWith(quietStartHour: h) : p.copyWith(quietEndHour: h));
                                setState(() => _picking = null);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: active ? c.primary : c.surfaceAlt, borderRadius: BorderRadius.circular(999)),
                                child: Text(_fmtHour(h),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : c.textPrimary)),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
