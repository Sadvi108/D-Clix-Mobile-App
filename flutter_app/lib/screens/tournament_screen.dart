import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/response_utils.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// One row of `/Reports/TournamentSummary`.
///
/// Note what is NOT here: a date, venue or status. The report returns medal tallies per
/// tournament, age group, gender and category, so the app cannot tell upcoming from past
/// events. A tournament list needs a backend route: docs/specs/2026-09-15-tournaments.md.
class TournamentRow {
  final String name;
  final String ageGroup;
  final String gender;
  final String category;
  final int players;
  final int gold;
  final int silver;
  final int bronze;

  const TournamentRow({
    required this.name,
    this.ageGroup = '',
    this.gender = '',
    this.category = '',
    this.players = 0,
    this.gold = 0,
    this.silver = 0,
    this.bronze = 0,
  });

  String get title => name.isNotEmpty
      ? name
      : category.isNotEmpty
          ? category
          : gender.isNotEmpty
              ? gender
              : 'Tournament results';

  int get medals => gold + silver + bronze;

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim()) ?? 0;
  }

  static String _str(dynamic v) => v == null ? '' : '$v'.trim();

  factory TournamentRow.fromJson(Map<String, dynamic> m) => TournamentRow(
        name: _str(m['name'] ?? m['Name'] ?? m['tournamentName']),
        ageGroup: _str(m['ageGroup'] ?? m['AgeGroup']),
        gender: _str(m['gender'] ?? m['Gender']),
        category: _str(m['category'] ?? m['Category']),
        players: _int(m['playerCount'] ?? m['PlayerCount']),
        gold: _int(m['medalGold'] ?? m['MedalGold']),
        silver: _int(m['medalSilver'] ?? m['MedalSilver']),
        bronze: _int(m['medalBronze'] ?? m['MedalBronze']),
      );
}

List<TournamentRow> parseTournaments(dynamic res) {
  final rows = findRecordList(res);
  return rows.whereType<Map>().map((m) => TournamentRow.fromJson(Map<String, dynamic>.from(m))).toList(growable: false);
}

/// Distinct tournament names, in the order the report returned them.
List<String> tournamentNames(List<TournamentRow> rows) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in rows) {
    if (r.name.isNotEmpty && seen.add(r.name)) out.add(r.name);
  }
  return out;
}

/// Medal and player totals across [rows].
({int gold, int silver, int bronze, int players}) tournamentTotals(List<TournamentRow> rows) => (
      gold: rows.fold(0, (s, r) => s + r.gold),
      silver: rows.fold(0, (s, r) => s + r.silver),
      bronze: rows.fold(0, (s, r) => s + r.bronze),
      players: rows.fold(0, (s, r) => s + r.players),
    );

/// Tournament: the medal results the club system holds for this account.
///
/// Replaces the Expo "Competition" screen, whose Upcoming / Past tabs only relabelled the same
/// date-less rows and stamped every card UPCOMING or COMPLETED.
class TournamentScreen extends StatefulWidget {
  const TournamentScreen({super.key});

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> with UseApi<TournamentScreen> {
  // No reportType: the route casts it to int and 400s on a word.
  late final _data =
      useApi(() async => parseTournaments(await Api.reportsTournamentSummary({'fromDate': null, 'toDate': null})));
  String _selectedName = '';

  @override
  void initState() {
    super.initState();
    _data;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final all = _data.data ?? const <TournamentRow>[];
    final names = tournamentNames(all);
    final rows = _selectedName.isEmpty ? all : all.where((r) => r.name == _selectedName).toList();
    final totals = tournamentTotals(rows);

    Widget pill(String label, bool active, VoidCallback onTap) => Touchable(
          onPress: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: active ? c.primary.hexA('18') : c.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: active ? c.primary : c.border),
            ),
            child: Text(label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? c.primary : c.textSecondary)),
          ),
        );

    Widget medal(Color color, String label, int value, {double size = 42}) => Expanded(
          child: Column(children: [
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.hexA('20')),
              child: Text('$value', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            ),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.textSecondary)),
          ]),
        );

    Widget tag(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.sm)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: c.textSecondary),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary)),
          ]),
        );

    final children = <Widget>[];
    if (_data.loading && _data.data == null) {
      children.add(const RnSpinner(vertical: 40));
    } else if (_data.data == null) {
      children.add(ErrorState(message: _data.error ?? "Couldn't load tournament results.", onRetry: _data.reload));
    } else {
      if (_data.error != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text("Couldn't refresh. Showing the last loaded results.",
              style: TextStyle(fontSize: 12, color: c.textSecondary)),
        ));
      }
      if (rows.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [
            Icon(Ion.trophyOutline, size: 48, color: c.textMuted),
            const SizedBox(height: 12),
            Text('No tournament results yet',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('The club system returned no tournament results for your account.',
                  textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 13)),
            ),
          ]),
        ));
      } else {
        children.add(Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: rnCard(c, radius: Radii.xl, shadow: Shadows.card(c)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_selectedName.isEmpty ? 'ALL RESULTS' : _selectedName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.textMuted)),
            const SizedBox(height: 12),
            Row(children: [
              medal(const Color(0xFFF59E0B), 'Gold', totals.gold, size: 48),
              medal(const Color(0xFF9CA3AF), 'Silver', totals.silver, size: 48),
              medal(const Color(0xFFB45309), 'Bronze', totals.bronze, size: 48),
              medal(c.primary, 'Players', totals.players, size: 48),
            ]),
          ]),
        ));
        for (final t in rows) {
          children.add(Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: rnCard(c, radius: Radii.xl, shadow: Shadows.card(c)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x18DB2777)),
                  child: const Icon(Ion.trophy, size: 22, color: Color(0xFFDB2777)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (t.category.isNotEmpty && t.category != t.title) tag(Ion.ribbonOutline, t.category),
                      if (t.ageGroup.isNotEmpty) tag(Ion.calendarOutline, t.ageGroup),
                      if (t.gender.isNotEmpty && t.gender != t.title) tag(Ion.personOutline, t.gender),
                      tag(Ion.peopleOutline, '${t.players} ${t.players == 1 ? 'player' : 'players'}'),
                    ]),
                  ]),
                ),
              ]),
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                child: Row(children: [
                  medal(const Color(0xFFF59E0B), 'Gold', t.gold),
                  medal(const Color(0xFF9CA3AF), 'Silver', t.silver),
                  medal(const Color(0xFFB45309), 'Bronze', t.bronze),
                ]),
              ),
            ]),
          ));
        }
      }
      children.add(Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Ion.informationCircleOutline, size: 17, color: c.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                'These are medal results. Tournament dates, venues and registration are not in the club system yet, so upcoming events are announced by your academy.',
                style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 17 / 11.5)),
          ),
        ]),
      ));
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Tournament', horizontal: Gaps.lg),
        if (names.length > 1)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl, vertical: 6),
              children: [
                pill('All', _selectedName.isEmpty, () => setState(() => _selectedName = '')),
                for (final n in names) ...[
                  const SizedBox(width: 8),
                  pill(n, _selectedName == n, () => setState(() => _selectedName = _selectedName == n ? '' : n)),
                ],
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _data.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, 120),
              children: children,
            ),
          ),
        ),
      ]),
    );
  }
}
