import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../services/response_utils.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';

/// RN `fmtWhen`: "just now" / "5m ago" / "3h ago" / "02 Sep 2026".
String _fmtWhen(dynamic iso) {
  final s = '${iso ?? ''}';
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  final mins = (DateTime.now().difference(d).inSeconds / 60).round();
  if (mins < 1) return 'just now';
  if (mins < 60) return '${mins}m ago';
  if (mins < 1440) return '${mins ~/ 60}h ago';
  return fmtDateGB(s);
}

/// Port of `frontend/app/notifications.tsx` (Expo v2.11.1).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Set<String> _readIds = {};
  /// Request notifications with an action in flight, and the last failure for
  /// each — a failed Accept/Reject must stay on screen and stay retryable.
  final Set<String> _acting = {};
  final Map<String, String> _actionErrors = {};
  String? _expanded;
  bool _busy = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Opening this screen IS reading them, so drop the app-icon badge the alerts set.
    NotificationService.cancelAll();
    PushNotificationService.clearBadge();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _readIds.clear();
      _expanded = null;
    });
    await UserSession.instance.refreshNotifications();
    if (mounted) setState(() => _refreshing = false);
  }

  bool _isRead(Map n) => n['isRead'] == true || _readIds.contains('${n['id']}');

  Future<void> _markOne(Map n) async {
    try {
      await Api.profileUpdateNotification2Read({'id': n['id']});
      UserSession.instance.acknowledgeNotificationRead(n['id']);
      if (mounted) setState(() => _readIds.add('${n['id']}'));
    } catch (_) {
      /* keep showing as unread on failure */
    }
  }

  Future<void> _onTap(Map n) async {
    setState(() => _expanded = _expanded == '${n['id']}' ? null : '${n['id']}');
    if (!_isRead(n)) await _markOne(n);
  }

  /// Approve or refuse a "request" notification.
  ///
  /// Old app: `POST Profile/UpdateNotificationAction {Id, IsApproved}`, buttons
  /// shown only for `notificationType == "request"`, and the server's own reply
  /// text is what the member is told
  /// (`PushNotificationPageViewModel.cs:60-80`). Parity review F10.
  Future<void> _act(Map n, bool approve) async {
    final key = '${n['id']}';
    // Only a request carries a decision, and only a real id can be decided —
    // checked here as well as in the UI, so no other caller can shortcut it.
    if (n['id'] == null || !isRequestNotification(n) || _acting.contains(key)) return;
    setState(() {
      _acting.add(key);
      _actionErrors.remove(key);
    });
    try {
      final res = await Api.profileUpdateNotificationAction({'id': n['id'], 'isApproved': approve});
      final said = unwrapData(res);
      final msg = said is String ? said.trim() : '';
      // The old app treated HTTP OK alone as nothing: it required the server's
      // own reply text before telling the member their answer was recorded
      // (`PushNotificationPageViewModel.cs:71`). An empty or malformed body
      // leaves the request in place, retryable.
      if (msg.isEmpty || msg.toLowerCase() == 'null') {
        if (mounted) {
          setState(() => _actionErrors[key] =
              "Your academy didn't confirm this. Please try again in a moment.");
        }
        return;
      }
      if (!mounted) return;
      // The request is gone from the member's list once the club has it; re-read
      // rather than guessing what the server did with it. A failed action leaves
      // the row exactly where it was, so it can be tried again.
      await UserSession.instance.refreshNotifications();
      if (!mounted) return;
      setState(() => _expanded = null);
      await notify(context, approve ? 'Request accepted' : 'Request rejected', msg);
    } catch (e) {
      if (mounted) setState(() => _actionErrors[key] = friendlyError(e));
    } finally {
      if (mounted) setState(() => _acting.remove(key));
    }
  }

  Future<void> _markAll(List<Map> items) async {
    final unread = items.where((n) => !_isRead(n)).toList();
    if (unread.isEmpty) return;
    setState(() => _busy = true);
    try {
      await Future.wait(unread.map(_markOne));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final items = (session.notifications ?? const []).whereType<Map>().toList();
    final loading = session.notifications == null || _refreshing;
    final unreadCount = items.where((n) => !_isRead(n)).length;

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: c.background,
          padding: EdgeInsets.fromLTRB(Gaps.lg, MediaQuery.paddingOf(context).top + 10, Gaps.lg, 10),
          child: Row(children: [
            RnCircleButton(icon: Ion.chevronBack, onPress: () => safeBack(context)),
            // balances the two-button action group on the right so the title stays centred
            const SizedBox(width: 48),
            Expanded(
              child: Column(children: [
                Text('Notifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                if (unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text('$unreadCount unread',
                        style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
            Touchable(
              onPress: _busy || unreadCount == 0 ? null : () => _markAll(items),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                child: _busy
                    ? Center(
                        child: SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)))
                    : Icon(Ion.checkmarkDone, size: 20, color: unreadCount == 0 ? c.textMuted : c.primary),
              ),
            ),
            const SizedBox(width: 6),
            RnCircleButton(icon: Ion.optionsOutline, iconSize: 20, onPress: () => context.push('/notification-settings')),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 60),
              children: [
                if (loading && items.isEmpty) const SkeletonList(rows: 6, lines: 2, padding: EdgeInsets.only(top: 4)),
                if (session.notificationsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(session.notificationsError!, style: TextStyle(color: c.danger, fontSize: 13)),
                  ),
                if (!loading && items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 70),
                    child: Column(children: [
                      Icon(Ion.notificationsOffOutline, size: 48, color: c.textMuted),
                      const SizedBox(height: 16),
                      Text('No notifications',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                      const SizedBox(height: 6),
                      Text("You're all caught up", style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    ]),
                  ),
                for (final n in items)
                  Builder(builder: (context) {
                    final read = _isRead(n);
                    final open = _expanded == '${n['id']}';
                    final title = '${n['text'] ?? ''}'.trim();
                    final type = '${n['notificationType'] ?? ''}';
                    return Touchable(
                      activeOpacity: 0.85,
                      onPress: () => _onTap(n),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: read
                            ? rnCard(c)
                            : BoxDecoration(
                                color: c.isDark ? c.surfaceAlt : const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(Radii.lg),
                                boxShadow: Shadows.soft(c),
                                border: Border.all(color: c.primary.hexA('55')),
                              ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: read ? c.surfaceAlt : c.primary, shape: BoxShape.circle),
                            child: Icon(Ion.notifications, size: 18, color: read ? c.primary : Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text(title.isEmpty ? 'Notification' : title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: read ? FontWeight.w700 : FontWeight.w800,
                                          color: c.textPrimary)),
                                ),
                                const SizedBox(width: 8),
                                Text(_fmtWhen(n['notifyDate']),
                                    style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                              ]),
                              const SizedBox(height: 4),
                              Text('${n['value'] ?? ''}'.trim(),
                                  maxLines: open ? null : 2,
                                  overflow: open ? null : TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: c.textSecondary, height: 18 / 13)),
                              if (type.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(type,
                                      style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w700)),
                                ),
                              // Only a "request" carries a decision; an
                              // announcement is read and nothing more.
                              if (open && isRequestNotification(n)) ...[
                                if (_actionErrors['${n['id']}'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(_actionErrors['${n['id']}']!,
                                        style: TextStyle(fontSize: 12, color: c.danger)),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Row(children: [
                                    for (final a in [
                                      (label: 'Accept', approve: true, color: c.success),
                                      (label: 'Reject', approve: false, color: c.danger),
                                    ])
                                      Padding(
                                        padding: EdgeInsets.only(right: a.approve ? 10 : 0),
                                        child: Touchable(
                                          onPress: _acting.contains('${n['id']}')
                                              ? null
                                              : () => _act(n, a.approve),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                                            decoration: BoxDecoration(
                                              color: a.color.hexA('1F'),
                                              borderRadius: BorderRadius.circular(Radii.md),
                                              border: Border.all(color: a.color.hexA('66')),
                                            ),
                                            child: Text(a.label,
                                                style: TextStyle(
                                                    fontSize: 13, fontWeight: FontWeight.w800, color: a.color)),
                                          ),
                                        ),
                                      ),
                                  ]),
                                ),
                              ],
                            ]),
                          ),
                          if (!read) ...[
                            const SizedBox(width: 12),
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                            ),
                          ],
                        ]),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
