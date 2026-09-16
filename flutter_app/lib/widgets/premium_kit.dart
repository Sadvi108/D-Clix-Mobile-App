// Shared building blocks for the premium screen style introduced with the redesigned profile:
// one rounded gradient header, tinted rounded-square icon tiles, uppercase section labels,
// grouped cards with inset dividers, and the dark slate "hero" card.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/ion.dart';
import 'rn_kit.dart';

/// Named tints so every screen colour-codes the same way.
class PremiumTint {
  PremiumTint._();
  static const indigo = Color(0xFF6366F1);
  static const green = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const pink = Color(0xFFEC4899);
  static const sky = Color(0xFF0EA5E9);
  static const violet = Color(0xFF8B5CF6);
  static const red = Color(0xFFEF4444);
  static const teal = Color(0xFF14B8A6);
  static const orange = Color(0xFFF97316);
  static const slate = Color(0xFF64748B);
}

/// Card surface used by premium screens.
BoxDecoration premiumCard(AppColors c, {double radius = Radii.xl}) => BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: Shadows.soft(c),
      border: Border.all(color: c.isDark ? c.border : c.borderLight),
    );

/// Dark slate gradient used for hero summaries (dues, member ID, collections).
BoxDecoration premiumSlate(AppColors c, {double radius = Radii.xl}) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
      ),
      boxShadow: Shadows.shade(c),
      border: c.isDark ? Border.all(color: const Color(0xFF334155)) : null,
    );

/// Rounded-square icon on a soft tint of its own colour.
class TintedIcon extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final double size;
  const TintedIcon(this.icon, {super.key, this.tint, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final color = tint ?? c.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.hexA(c.isDark ? '2E' : '17'),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(icon, size: size * .5, color: color),
    );
  }
}

/// Rounded orange gradient header from the status bar down.
class PremiumHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;
  final double bottomPadding;
  const PremiumHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.bottomPadding = 22,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: Shadows.soft(c),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Gaps.xl, 8, Gaps.xl, bottomPadding),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5, fontWeight: FontWeight.w500)),
                ],
              ]),
            ),
            for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 10), a],
          ]),
          if (bottom != null) ...[const SizedBox(height: 16), bottom!],
        ]),
      ),
    );
  }
}

/// 44pt translucent round button for use on the orange header.
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  const HeaderIconButton({super.key, required this.icon, required this.label, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge unread' : label,
      excludeSemantics: true,
      child: Touchable(
        onPress: onTap,
        activeOpacity: 0.7,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0x2EFFFFFF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
            if (badge > 0)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.primary, width: 1.5),
                  ),
                  child: Text(badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Uppercase muted section label.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionLabel(this.text,
      {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(Gaps.xl + 4, 24, Gaps.xl + 4, 10)});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: c.textMuted)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Card holding rows separated by inset dividers.
class GroupCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  const GroupCard({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: Gaps.xl)});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      margin: margin,
      decoration: premiumCard(c),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Container(height: 1, margin: const EdgeInsets.only(left: 68), color: c.borderLight),
          children[i],
        ],
      ]),
    );
  }
}

/// Tappable row: tinted icon, title, optional subtitle, trailing widget or chevron.
class PremiumRow extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int titleLines;
  const PremiumRow({
    super.key,
    required this.icon,
    required this.title,
    this.tint,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        TintedIcon(icon, tint: tint),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary, height: 1.3)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontWeight: FontWeight.w500)),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (onTap != null) ...[const SizedBox(width: 6), Icon(Ion.chevronForward, size: 18, color: c.textMuted)],
      ]),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: row)),
    );
  }
}

/// Grid tile: tinted icon over a label, for quick-access grids.
class PremiumTile extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final String label;
  final VoidCallback onTap;
  const PremiumTile({super.key, required this.icon, required this.label, required this.onTap, this.tint});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Touchable(
        onPress: onTap,
        activeOpacity: 0.7,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
          decoration: premiumCard(c, radius: Radii.lg),
          child: Column(children: [
            TintedIcon(icon, tint: tint, size: 44),
            const SizedBox(height: 10),
            SizedBox(
              height: 30,
              child: Center(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w700, color: c.textPrimary)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Soft brand glow for slate cards; place in a Stack behind the content.
class SlateGlow extends StatelessWidget {
  final Alignment alignment;
  const SlateGlow({super.key, this.alignment = Alignment.topRight});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final right = alignment.x > 0;
    final topSide = alignment.y < 0;
    return Positioned(
      right: right ? -40 : null,
      left: right ? null : -50,
      top: topSide ? -50 : null,
      bottom: topSide ? null : -70,
      child: IgnorePointer(
        child: Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.primary.hexA('4D'), c.primary.hexA('00')]),
          ),
        ),
      ),
    );
  }
}
