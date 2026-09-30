import '../theme/app_icons.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// The five-slot frosted bar from Expo v2.11.1, shared by both roles.
class ClubTabBar extends StatelessWidget {
  final String location;
  final bool instructor;
  const ClubTabBar(
      {super.key, required this.location, this.instructor = false});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final canViewCollections = instructor
        ? context.watch<UserSession>().allowViewCollections
        : true;
    final items = instructor
        ? [
            ('Home', '/instructor/home', AppIcons.home_outlined, AppIcons.home),
            if (canViewCollections)
              (
                'Collections',
                '/instructor/collections',
                AppIcons.payments_outlined,
                AppIcons.payments
              )
            else
              (
                'Check-In',
                '/instructor/attendance',
                AppIcons.calendar_month_outlined,
                AppIcons.calendar_month
              ),
            (
              'Reports',
              '/instructor/reports',
              AppIcons.description_outlined,
              AppIcons.description
            ),
            (
              'Settings',
              '/instructor/settings',
              AppIcons.settings_outlined,
              AppIcons.settings
            ),
          ]
        : const [
            ('Home', '/home', AppIcons.home_outlined, AppIcons.home),
            (
              'Schedule',
              '/schedule',
              AppIcons.calendar_month_outlined,
              AppIcons.calendar_month
            ),
            (
              'Payments',
              '/payments',
              AppIcons.account_balance_wallet_outlined,
              AppIcons.account_balance_wallet
            ),
            ('Profile', '/profile', AppIcons.person_outline, AppIcons.person),
          ];
    return SizedBox(
      height: 62 + bottom,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
            child: ClipRect(
                child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: c.isDark ? 16 : 24, sigmaY: c.isDark ? 16 : 24),
          child: DecoratedBox(
              decoration: BoxDecoration(
            color: c.surface.withValues(alpha: c.isDark ? .55 : .60),
            border: Border(
                top: BorderSide(
                    color:
                        Colors.white.withValues(alpha: c.isDark ? .10 : .65))),
          )),
        ))),
        Padding(
          padding: EdgeInsets.fromLTRB(6, 8, 6, bottom > 10 ? bottom : 10),
          child: Row(children: [
            for (var slot = 0; slot < 5; slot++)
              if (slot == 2)
                const Expanded(child: SizedBox())
              else
                Expanded(child: Builder(builder: (context) {
                  final item = items[slot > 2 ? slot - 1 : slot];
                  final active = location.startsWith(item.$2);
                  final color = active ? c.primary : c.textMuted;
                  return Semantics(
                      selected: active,
                      button: true,
                      child: InkWell(
                        onTap: () => context.go(item.$2),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(active ? item.$4 : item.$3,
                                  size: 22, color: color),
                              const SizedBox(height: 2),
                              FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(item.$1,
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: color))),
                            ]),
                      ));
                })),
          ]),
        ),
        Positioned(
            top: -26,
            left: 0,
            right: 0,
            child: Center(
              child: Semantics(
                  button: true,
                  label: 'Scan QR',
                  child: GestureDetector(
                    onTap: () => context
                        .push(instructor ? '/instructor/qr-scan' : '/qr-scan'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                  colors: c.gradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight),
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: [
                                BoxShadow(
                                    color: c.primary.withValues(alpha: .35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8))
                              ]),
                          child: const Icon(AppIcons.document_scanner_outlined,
                              size: 30, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('Scan',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: c.gradient[1])),
                    ]),
                  )),
            )),
      ]),
    );
  }
}
