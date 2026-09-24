import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../services/user_session.dart';

/// Flutter counterparts of the React Native app's shared primitives (Expo v2.11.1,
/// `frontend/src/ui/*`). Screens ported from RN use these so the same component renders the
/// same way everywhere instead of being re-approximated per screen.

/// `TouchableOpacity`: dims to [activeOpacity] while pressed, no ripple.
class Touchable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPress;
  final double activeOpacity;
  final HitTestBehavior behavior;
  const Touchable({
    super.key,
    required this.child,
    this.onPress,
    this.activeOpacity = 0.2,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<Touchable> createState() => _TouchableState();
}

class _TouchableState extends State<Touchable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onPress,
      child: AnimatedOpacity(
        opacity: _down ? widget.activeOpacity : 1,
        duration: Duration(milliseconds: _down ? 0 : 150),
        child: widget.child,
      ),
    );
  }
}

/// RN `colors.x + "1A"` — a hex alpha suffix on a colour.
extension HexAlpha on Color {
  Color hexA(String aa) => withAlpha(int.parse(aa, radix: 16));
}

/// `src/ui/errorstate.tsx` — inline "this didn't load" banner with a retry.
class ErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;
  const ErrorState({super.key, this.message, this.onRetry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final msg = message;
    if (msg == null || msg.isEmpty) return const SizedBox.shrink();
    final c = context.appColors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: Gaps.lg, vertical: compact ? Gaps.md : Gaps.xl),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Ion.cloudOfflineOutline, size: compact ? 20 : 28, color: c.danger),
        const SizedBox(height: 8),
        Text(msg,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
                height: 18 / (compact ? 12 : 13))),
        if (onRetry != null) ...[
          const SizedBox(height: 10),
          Touchable(
            onPress: onRetry,
            activeOpacity: 0.85,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.primary),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Ion.refresh, size: 13, color: c.primary),
                const SizedBox(width: 6),
                Text('Try again',
                    style: TextStyle(
                        color: c.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// `src/ui/skeleton.tsx` — one shared 0.5↔1 opacity pulse.
class Skeleton extends StatefulWidget {
  final double? width;
  final double? widthFactor;
  final double height;
  final double radius;
  final Color? color;
  const Skeleton({
    super.key,
    this.width,
    this.widthFactor,
    this.height = 14,
    this.radius = 8,
    this.color,
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final box = FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color ?? (c.isDark ? c.surfaceAlt2 : c.border),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
    if (widget.widthFactor != null) {
      return FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widget.widthFactor,
          child: box);
    }
    return box;
  }
}

class SkeletonRow extends StatelessWidget {
  final int lines;
  const SkeletonRow({super.key, this.lines = 2});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: Shadows.soft(c),
        border: c.isDark ? Border.all(color: c.border) : null,
      ),
      child: Row(children: [
        const Skeleton(width: 40, height: 40, radius: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Skeleton(widthFactor: .62, height: 13),
            if (lines > 1) ...[
              const SizedBox(height: 8),
              const Skeleton(widthFactor: .88, height: 11),
            ],
            if (lines > 2) ...[
              const SizedBox(height: 8),
              const Skeleton(widthFactor: .45, height: 11),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        const Skeleton(width: 46, height: 16, radius: 6),
      ]),
    );
  }
}

class SkeletonList extends StatelessWidget {
  final int rows;
  final int lines;
  final EdgeInsets padding;
  const SkeletonList(
      {super.key, this.rows = 6, this.lines = 2, this.padding = const EdgeInsets.all(Gaps.xl)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            SkeletonRow(lines: lines),
          ],
        ]),
      );
}

class SkeletonStatRow extends StatelessWidget {
  const SkeletonStatRow({super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          const Expanded(
            child: Column(children: [
              Skeleton(width: 34, height: 20, radius: 6, color: Color(0x59FFFFFF)),
              SizedBox(height: 6),
              Skeleton(width: 52, height: 9, radius: 4, color: Color(0x40FFFFFF)),
            ]),
          ),
        ],
      ]);
}

/// `src/ui/glass.tsx` — frosted blur + translucent fill + hairline border.
class Glass extends StatelessWidget {
  final Widget child;
  final bool strong;
  final double radius;
  final double intensity;
  final EdgeInsetsGeometry? padding;
  const Glass({
    super.key,
    required this.child,
    this.strong = false,
    this.radius = Radii.xl,
    this.intensity = 40,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fill = c.isDark
        ? Color.fromRGBO(26, 25, 30, strong ? .78 : .55)
        : Color.fromRGBO(255, 255, 255, strong ? .80 : .60);
    final border = c.isDark ? const Color(0x1AFFFFFF) : const Color(0xA6FFFFFF);
    final sigma = intensity / 4;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// RN `Alert`-style single-OK message (`notify` in src/ui/dialogs.ts).
Future<void> notify(BuildContext context, String title, [String? message]) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );

/// RN `confirmDialog` in src/ui/dialogs.ts.
Future<bool> confirmDialog(BuildContext context, String title,
    {String? message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool destructive = false}) async {
  final c = context.appColors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel, style: TextStyle(color: c.textSecondary))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: TextStyle(color: destructive ? c.danger : c.primary))),
      ],
    ),
  );
  return ok ?? false;
}

/// JavaScript `String(n)` for a number: `150`, `150.5` — never `150.00`.
String jsNum(num n) {
  if (n is int || n == n.roundToDouble()) return n.toInt().toString();
  return n.toString();
}

/// JavaScript `n.toLocaleString()` (en): grouped thousands, up to 3 decimals, no padding.
String localeNum(num n) {
  final neg = n < 0;
  final fixed = n.abs().toStringAsFixed(3);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final frac = parts[1].replaceFirst(RegExp(r'0+$'), '');
  return '${neg ? '-' : ''}$whole${frac.isEmpty ? '' : '.$frac'}';
}

/// RN `initialsOf` used by the home headers and avatars.
String initialsOf(String? name) {
  final words = (name == null || name.trim().isEmpty ? '?' : name)
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  return words.map((w) => w[0]).take(2).join().toUpperCase();
}

/// JS `n.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})`.
String money2(num n) {
  final parts = n.abs().toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${n < 0 ? '-' : ''}$whole.${parts[1]}';
}


/// RN `safeBack(router)`: pop when there is somewhere to go back to, else the role's home.
void safeBack(BuildContext context, [String? fallback]) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback ?? (UserSession.instance.isInstructor ? '/instructor/home' : '/home'));
  }
}

/// The stack-screen header every RN detail screen uses: a round back button, an h3 title and a
/// matching spacer (or [trailing]) so the title sits centred.
class RnHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final double horizontal;
  final Color? background;
  const RnHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.horizontal = Gaps.xl,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      color: background ?? c.background,
      padding: EdgeInsets.fromLTRB(horizontal, MediaQuery.paddingOf(context).top + 10, horizontal, 10),
      child: Row(children: [
        RnCircleButton(icon: Ion.chevronBack, onPress: onBack ?? () => safeBack(context)),
        Expanded(
          child: Text(title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
        ),
        trailing ?? const SizedBox(width: 42, height: 42),
      ]),
    );
  }
}

/// 42px round surfaceAlt button (`backBtn` / `iconBtn` in the RN styles).
class RnCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPress;
  final double iconSize;
  final Color? iconColor;
  final double size;
  const RnCircleButton({
    super.key,
    required this.icon,
    this.onPress,
    this.iconSize = 22,
    this.iconColor,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Touchable(
      onPress: onPress,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
        child: Icon(icon, size: iconSize, color: iconColor ?? c.textPrimary),
      ),
    );
  }
}

/// Back chevron for a screen that is also a bottom-tab root (Schedule, Payments, Training):
/// visible only when pushed as a drill-down (`canPopHere`), so the tab-root header stays
/// pixel-identical to before. Profile's header has its own icon-button style already, so it
/// gates the same way inline instead of using this widget.
class TabRootBackButton extends StatelessWidget {
  const TabRootBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!canPopHere(context)) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      RnCircleButton(icon: Ion.chevronBack, onPress: () => safeBack(context)),
      const SizedBox(width: Gaps.md),
    ]);
  }
}

/// `context.canPop()` asserts when there's no GoRouter in the tree at all — true for a handful
/// of screen tests that mount a screen standalone to check its data wiring, not its navigation.
/// Those screens are always inside the app's router in the real app; this just keeps a
/// build-time (not tap-time) canPop check from crashing when one isn't there.
bool canPopHere(BuildContext context) => GoRouter.maybeOf(context)?.canPop() ?? false;

/// `shadow.soft` card with the dark-mode hairline most RN list cards use.
BoxDecoration rnCard(AppColors c, {double radius = Radii.lg, List<BoxShadow>? shadow, Color? color}) => BoxDecoration(
      color: color ?? c.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow ?? Shadows.soft(c),
      border: c.isDark ? Border.all(color: c.border) : null,
    );

/// Centered small spinner (`ActivityIndicator color={colors.primary}`).
class RnSpinner extends StatelessWidget {
  final double vertical;
  final Color? color;
  const RnSpinner({super.key, this.vertical = 24, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: vertical),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: color ?? context.appColors.primary),
          ),
        ),
      );
}

/// RN `fmtDate`: `toLocaleDateString("en-GB", {day: "2-digit", month: "short", year: "numeric"})`.
String fmtDateGB(dynamic iso, {String empty = ''}) {
  final s = '${iso ?? ''}';
  if (s.isEmpty) return empty;
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
}
