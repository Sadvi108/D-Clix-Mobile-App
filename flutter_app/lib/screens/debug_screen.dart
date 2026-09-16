import '../theme/app_icons.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// Debug dump for the current session. Debug builds only: see `developerRoutes`, which keeps
/// it out of release builds because it shows the bearer token.
///
/// Open via `localhost:3000/#/debug` after login. Shows every cached
/// response, every computed value, and exposes a one-tap "Copy all JSON"
/// button so the raw payloads can be pasted into chat for parser tuning.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  static const _enc = JsonEncoder.withIndent('  ');

  String _pretty(dynamic v) {
    if (v == null) return 'null';
    try {
      return _enc.convert(v);
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final dump = _buildDump(session);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Debug — API dump'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.refresh),
            tooltip: 'Refresh',
            onPressed: () async => UserSession.instance.refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy all JSON',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: dump));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Whole dump copied to clipboard')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summary(c, 'Logged in?', '${session.isLoggedIn}'),
          _summary(c, 'isInstructor', '${session.isInstructor}'),
          _summary(c, 'Resolved displayName', session.displayName),
          _summary(c, 'Resolved clubName', session.clubName),
          _summary(c, 'Resolved registrationNo', session.registrationNo),
          _summary(c, 'Computed dueAmount',
              'RM ${session.dueAmount.toStringAsFixed(2)}'),
          _summary(c, 'Computed invoiceCount', '${session.invoiceCount}'),
          _summary(c, 'Computed earliestDueDate', session.earliestDueDate),
          _summary(c, 'unreadNotifications', '${session.unreadNotifications}'),
          _summary(c, 'outstandingList length',
              '${session.outstandingList?.length ?? "null"}'),
          _summary(c, 'nextBookings length',
              '${session.nextBookings?.length ?? "null"}'),
          _summary(c, 'allBookings length',
              '${session.allBookings?.length ?? "null"}'),
          _summary(c, 'notifications length',
              '${session.notifications?.length ?? "null"}'),
          const SizedBox(height: 16),
          _block(c, 'authData keys',
              (session.authData?.keys.toList() ?? []).join(', ')),
          _block(c, 'authData (full)', _pretty(session.authData)),
          _block(c, 'myInfo keys',
              (session.myInfo?.keys.toList() ?? []).join(', ')),
          _block(c, 'myInfo (full)', _pretty(session.myInfo)),
          _block(c, 'homeStatsRaw (full /Reports/HomePageStats)',
              _pretty(session.homeStatsRaw)),
          _block(c, 'homeStats (parsed)', _pretty(session.homeStats)),
          if (session.homeStatsError != null)
            _block(c, 'homeStatsError', session.homeStatsError!),
          _block(c, 'outstandingRaw (full /Outstanding/Fetch)',
              _pretty(session.outstandingRaw)),
          _block(
              c, 'outstandingList (parsed)', _pretty(session.outstandingList)),
          if (session.outstandingError != null)
            _block(c, 'outstandingError', session.outstandingError!),
          _block(c, 'nextBookings (full /ClassBooking/NextBookings)',
              _pretty(session.nextBookings)),
          _block(c, 'allBookings (full /ClassBooking/GetBookings)',
              _pretty(session.allBookings)),
          _block(c, 'notifications (full /Profile/MyNotifications)',
              _pretty(session.notifications)),
          _block(c, 'studentAddtnlInfo (full /Profile/StudentAddtnlInfo)',
              _pretty(session.studentAddtnlInfo)),
          _block(c, 'clubStats (full /Profile/MyClubStats)',
              _pretty(session.clubStats)),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  String _buildDump(UserSession s) {
    return [
      '## SUMMARY',
      'displayName: ${s.displayName}',
      'clubName: ${s.clubName}',
      'registrationNo: ${s.registrationNo}',
      'isInstructor: ${s.isInstructor}',
      'dueAmount (computed): RM ${s.dueAmount.toStringAsFixed(2)}',
      'invoiceCount (computed): ${s.invoiceCount}',
      'earliestDueDate (computed): ${s.earliestDueDate}',
      'unreadNotifications: ${s.unreadNotifications}',
      'outstandingList.length: ${s.outstandingList?.length}',
      'nextBookings.length: ${s.nextBookings?.length}',
      'allBookings.length: ${s.allBookings?.length}',
      'notifications.length: ${s.notifications?.length}',
      '',
      '## authData',
      _pretty(s.authData),
      '',
      '## /Profile/MyInfo',
      _pretty(s.myInfo),
      '',
      '## /Reports/HomePageStats (raw)',
      _pretty(s.homeStatsRaw),
      '',
      '## /Reports/HomePageStats (parsed homeStats)',
      _pretty(s.homeStats),
      '',
      '## /Outstanding/Fetch (raw)',
      _pretty(s.outstandingRaw),
      '',
      '## /Outstanding/Fetch (parsed outstandingList)',
      _pretty(s.outstandingList),
      '',
      '## /ClassBooking/NextBookings',
      _pretty(s.nextBookings),
      '',
      '## /ClassBooking/GetBookings',
      _pretty(s.allBookings),
      '',
      '## /Profile/MyNotifications',
      _pretty(s.notifications),
      '',
      '## /Profile/StudentAddtnlInfo',
      _pretty(s.studentAddtnlInfo),
      '',
      '## /Profile/MyClubStats',
      _pretty(s.clubStats),
    ].join('\n');
  }

  Widget _summary(AppColors c, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 220,
            child: Text(label,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: SelectableText(value,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _block(AppColors c, String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    color: c.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4)),
            const SizedBox(width: 8),
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: body));
              },
              child: Icon(Icons.copy, size: 14, color: c.textMuted),
            ),
          ]),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: SelectableText(
              body.length > 10000
                  ? '${body.substring(0, 10000)}\n\n…(${body.length - 10000} more chars)'
                  : body,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.45),
            ),
          ),
        ]),
      );
}
