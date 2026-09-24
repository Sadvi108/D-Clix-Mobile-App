import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/response_utils.dart';
import '../../services/rn_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/ion.dart';
import '../../utils/qr_content.dart';
import '../../utils/training_schedule.dart';
import '../../widgets/report_kit.dart';
import '../../widgets/rn_kit.dart';
import '../../widgets/use_api.dart';

/// Ports of the instructor `frontend/app/r-*.tsx` report screens (Expo v2.11.1).
///
/// Each one is a [ReportScaffold] with the same filters, the same request body and the same
/// card fields as its RN counterpart. Server quirks that RN documented (filters the routes
/// ignore, `reportType` cast to int) are handled the same way here.

typedef Row_ = Map<String, dynamic>;

List<RkOption> _opts(List<Row_>? rows) =>
    [for (final o in rows ?? const <Row_>[]) (id: (o['id'] ?? '') as Object, text: '${o['text'] ?? ''}')];

Widget _title(BuildContext context, String text, {int lines = 2, double bottom = 0}) => Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(text.isEmpty ? '—' : text,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.appColors.textPrimary)),
    );

Widget _pill(IconData icon, String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.hexA('22'), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      ]),
    );

DateTime _monthStart() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, 1);
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

// ── r-student-centers ──────────────────────────────────────────────────────────
class RStudentCentersScreen extends StatefulWidget {
  const RStudentCentersScreen({super.key});
  @override
  State<RStudentCentersScreen> createState() => _RStudentCentersScreenState();
}

class _RStudentCentersScreenState extends State<RStudentCentersScreen> with UseApi<RStudentCentersScreen> {
  late final _data = useApi(RnApi.reportStudentCenters);
  @override
  void initState() {
    super.initState();
    _data;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return ReportScaffold<Row_>(
      title: 'Student Centers',
      loading: _data.loading,
      error: _data.error,
      data: _data.data,
      onRefresh: _data.reload,
      renderItem: (r, _) => RkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, '${r['centername'] ?? ''}'),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _pill(Ion.people, '${RnApi.number(r['activeStudents']).toInt()} Active', c.success),
              _pill(Ion.people, '${RnApi.number(r['inactveStudents']).toInt()} Inactive', c.danger),
            ]),
          ),
          KV('Type', r['centertype']),
          KV('Code', r['shortid']),
        ]),
      ),
    );
  }
}

// ── r-training-centers ─────────────────────────────────────────────────────────
class RTrainingCentersScreen extends StatefulWidget {
  const RTrainingCentersScreen({super.key});
  @override
  State<RTrainingCentersScreen> createState() => _RTrainingCentersScreenState();
}

class _RTrainingCentersScreenState extends State<RTrainingCentersScreen> with UseApi<RTrainingCentersScreen> {
  late final _data = useApi(RnApi.reportTrainingCenters);
  @override
  void initState() {
    super.initState();
    _data;
  }

  @override
  Widget build(BuildContext context) => ReportScaffold<Row_>(
        title: 'Training Centers',
        loading: _data.loading,
        error: _data.error,
        data: _data.data,
        onRefresh: _data.reload,
        renderItem: (r, _) => RkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _title(context, '${r['name'] ?? ''}', bottom: 4),
            KV('Code', r['code']),
            KV('Address', r['address']),
            KV('Total Classes', r['totalClasses']),
            KV('Total Students', r['totalStudents'], strong: true),
            KV('Assigned', r['studentAssigned']),
            KV('Not Assigned', r['studentNotAssigned']),
            KV('Exam Center Students', r['examCentersAssignedStudents']),
            KV('Advance Training', r['advanceTrainingStudents']),
          ]),
        ),
      );
}

// ── r-exam-centers ─────────────────────────────────────────────────────────────
class RExamCentersScreen extends StatefulWidget {
  const RExamCentersScreen({super.key});
  @override
  State<RExamCentersScreen> createState() => _RExamCentersScreenState();
}

class _RExamCentersScreenState extends State<RExamCentersScreen> with UseApi<RExamCentersScreen> {
  late final _data = useApi(RnApi.reportExamCenters);
  @override
  void initState() {
    super.initState();
    _data;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return ReportScaffold<Row_>(
      title: 'Exam Centers',
      loading: _data.loading,
      error: _data.error,
      data: _data.data,
      onRefresh: _data.reload,
      renderItem: (r, _) => RkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, '${r['centername'] ?? ''}'),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _pill(Ion.people, '${RnApi.number(r['activeStudents']).toInt()} Active', c.success),
              _pill(Ion.people, '${RnApi.number(r['inactveStudents']).toInt()} Inactive', c.danger),
            ]),
          ),
          KV('Code', r['shortid']),
        ]),
      ),
    );
  }
}

// ── r-student-list ─────────────────────────────────────────────────────────────
const _avatarTints = [
  Color(0xFF4F46E5), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B),
  Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFFDB2777), Color(0xFF14B8A6),
];

/// Stable per-student tint so a roster reads as a list of people, not a wall of grey.
Color _tintFor(dynamic id) {
  var h = 0;
  for (final u in '$id'.codeUnits) {
    h = (h * 31 + u) & 0xFFFFFFFF;
  }
  return _avatarTints[h % _avatarTints.length];
}

/// Whatever photo field the backend adds to a roster row; none today.
String? _photoOf(Map s) {
  final raw = '${s['photo'] ?? s['profilePic'] ?? s['dp'] ?? s['imageUrl'] ?? s['picture'] ?? ''}'.trim();
  if (raw.isEmpty) return null;
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)
      ? raw
      : 'https://www.maclubsystem.com/${raw.replaceFirst(RegExp(r'^/+'), '')}';
}

/// Roster row avatar: the student's photo when the row carries one, else tinted initials.
Widget _studentAvatar(Map s, {double size = 48}) {
  final photo = _photoOf(s);
  final tint = _tintFor(s['id']);
  final initials = Text(initialsOf('${s['text'] ?? ''}'),
      style: TextStyle(fontSize: size / 3, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: tint));
  return Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    decoration: BoxDecoration(shape: BoxShape.circle, color: tint.hexA('22')),
    child: photo == null
        ? initials
        : CachedNetworkImage(
            imageUrl: photo,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => initials,
            errorWidget: (_, __, ___) => initials),
  );
}

class RStudentListScreen extends StatefulWidget {
  const RStudentListScreen({super.key});
  @override
  State<RStudentListScreen> createState() => _RStudentListScreenState();
}

class _RStudentListScreenState extends State<RStudentListScreen> with UseApi<RStudentListScreen> {
  Object _centerId = '';
  final _name = TextEditingController();
  final _ic = TextEditingController();
  final _qr = TextEditingController();

  List<Row_> _centerList = const [];
  List<String> _failed = const [];

  // Every centre's students, loaded in parallel so the full roster shows without searching.
  // The centre list is part of the same load: waiting on a separate centres request left the
  // screen spinning forever when that request failed.
  late final _students = useApi<List<Row_>>(() async {
    final list = await RnApi.dropdownListByType(3);
    final failed = <String>[];
    final perCenter = await Future.wait(list.map((c) async {
      try {
        final rows = await RnApi.studentListByTcId(RnApi.number(c['id']).toInt());
        return [for (final s in rows) {...s, 'centerName': c['text'], 'centerId': c['id']}];
      } catch (_) {
        failed.add('${c['text'] ?? c['id']}');
        return const <Row_>[];
      }
    }));
    if (mounted) {
      setState(() {
        _centerList = list;
        _failed = failed;
      });
    }
    return perCenter.expand((x) => x).toList();
  });

  @override
  void initState() {
    super.initState();
    _students;
    for (final t in [_name, _ic, _qr]) {
      t.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _ic.dispose();
    _qr.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController ctrl, String hint, {IconData? icon}) {
    final c = context.appColors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RkLabel(label),
      Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: c.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.border)),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 15, color: c.textMuted), const SizedBox(width: 6)],
          Expanded(
            child: TextField(
              controller: ctrl,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              cursorColor: c.primary,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: hint,
                hintStyle: TextStyle(color: c.textMuted, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          if (ctrl.text.isNotEmpty)
            Touchable(onPress: ctrl.clear, child: Icon(Ion.closeCircle, size: 16, color: c.textMuted)),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    var all = _students.data ?? const <Row_>[];
    if ('$_centerId'.isNotEmpty) all = all.where((s) => '${s['centerId']}' == '$_centerId').toList();
    final n = _name.text.trim().toLowerCase();
    if (n.isNotEmpty) all = all.where((s) => '${s['text'] ?? ''}'.toLowerCase().contains(n)).toList();
    final i = _ic.text.trim().toLowerCase();
    if (i.isNotEmpty) all = all.where((s) => '${s['value'] ?? ''}'.toLowerCase().contains(i)).toList();
    final q = _qr.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      // A scanned student QR carries `ST-00089623`; match on the id it encodes.
      final scanned = QrContent.parse(_qr.text);
      final scannedId = scanned?.type == QrType.student ? scanned!.id : null;
      all = all.where((s) {
        final id = RnApi.number(s['id']).toInt();
        return (scannedId != null && id == scannedId) ||
            '${s['value'] ?? ''}'.toLowerCase() == q ||
            '${s['text'] ?? ''}'.toLowerCase() == q ||
            '$id' == q ||
            QrContent.student(id).toLowerCase() == q;
      }).toList();
    }
    final loading = _students.data == null && _students.error == null;
    final anyFilter = '$_centerId'.isNotEmpty || n.isNotEmpty || i.isNotEmpty || q.isNotEmpty;

    Widget centered(Widget child) => Center(child: Padding(padding: const EdgeInsets.all(40), child: child));
    Widget body;
    if (loading) {
      body = Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: c.primary)));
    } else if (_students.data == null) {
      body = Padding(
        padding: const EdgeInsets.all(Gaps.xl),
        child: ErrorState(message: _students.error ?? "Couldn't load students.", onRetry: _students.reload),
      );
    } else if (all.isEmpty) {
      body = centered(Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Ion.peopleOutline, size: 44, color: c.textMuted),
        const SizedBox(height: 10),
        Text(anyFilter ? 'No students match your filters.' : 'No students found.',
            style: TextStyle(color: c.textSecondary, fontSize: 14)),
      ]));
      body = RefreshIndicator(
        color: c.primary,
        onRefresh: _students.reload,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [body]),
      );
    } else {
      body = RefreshIndicator(
          color: c.primary,
          onRefresh: _students.reload,
          child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 140),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, idx) {
          final s = all[idx];
          return RkCard(
            child: Row(children: [
              _studentAvatar(s),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _title(context, '${s['text'] ?? ''}', lines: 1),
                  const SizedBox(height: 2),
                  Text('Reg / IC No: ${'${s['value'] ?? ''}'.isEmpty ? '—' : s['value']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textSecondary)),
                  const SizedBox(height: 2),
                  Text('Center: ${'${s['centerName'] ?? ''}'.isEmpty ? '—' : s['centerName']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ]),
              ),
            ]),
          );
        },
      ));
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ScreenHeader(title: 'Student List', subtitle: loading ? 'Loading…' : '${all.length} student${all.length == 1 ? '' : 's'}'),
        Container(
          margin: const EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectField(
              label: 'Training Center',
              placeholder: 'All Centers',
              value: _centerId,
              options: [(id: '', text: 'All Centers'), ..._opts(_centerList)],
              loading: loading,
              onChange: (id, _) => setState(() => _centerId = id),
            ),
            const SizedBox(height: 10),
            _field('Name', _name, 'Search name'),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _field('IC No.', _ic, 'IC / Reg no')),
              const SizedBox(width: 10),
              Expanded(child: _field('QR Code', _qr, 'Scan / paste code', icon: Ion.qrCodeOutline)),
            ]),
          ]),
        ),
        if (_failed.isNotEmpty && _students.data != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 6, Gaps.xl, 0),
            child: ErrorState(
              compact: true,
              message:
                  "Couldn't load students from ${_failed.length == 1 ? _failed.single : '${_failed.length} centres'}. Pull down to retry.",
              onRetry: _students.reload,
            ),
          ),
        Expanded(child: body),
      ]),
    );
  }
}

// ── r-training-schedule ────────────────────────────────────────────────────────
const _dayLabels = ['Other', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Every training time across every centre the instructor can see, grouped by day.
///
/// `/Listing/TrainingTimeByTcId` answers one centre at a time, so all centres are fetched in
/// parallel. A centre that fails is reported, never silently dropped.
class RTrainingScheduleScreen extends StatefulWidget {
  const RTrainingScheduleScreen({super.key});
  @override
  State<RTrainingScheduleScreen> createState() => _RTrainingScheduleScreenState();
}

class _RTrainingScheduleScreenState extends State<RTrainingScheduleScreen> with UseApi<RTrainingScheduleScreen> {
  Object _centreId = '';
  int _day = -1; // -1 = every day
  List<String> _failed = const [];

  late final _schedule = useApi<List<ScheduleSlot>>(() async {
    final centres = await RnApi.dropdownListByType(3);
    final failed = <String>[];
    final perCentre = await Future.wait(centres.map((c) async {
      try {
        return (centre: c as Map, rows: (await RnApi.trainingTimeByTcId(RnApi.number(c['id']).toInt())).cast<Map>());
      } catch (_) {
        failed.add('${c['text'] ?? c['id']}');
        return (centre: c as Map, rows: const <Map>[]);
      }
    }));
    if (mounted) setState(() => _failed = failed);
    return buildSchedule(perCentre);
  });

  @override
  void initState() {
    super.initState();
    _schedule;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final all = _schedule.data ?? const <ScheduleSlot>[];
    final centreOptions = <RkOption>[
      (id: '', text: 'All Centers'),
      for (final entry in {for (final s in all) '${s.centreId}': s.centre}.entries) (id: entry.key, text: entry.value),
    ];
    final inCentre = '$_centreId'.isEmpty ? all : all.where((s) => '${s.centreId}' == '$_centreId').toList();
    final days = {for (final s in inCentre) s.weekday}.toList()..sort((a, b) => (a == 0 ? 8 : a).compareTo(b == 0 ? 8 : b));
    final shown = _day < 0 ? inCentre : inCentre.where((s) => s.weekday == _day).toList();
    final centreCount = {for (final s in inCentre) '${s.centreId}'}.length;

    Widget chip(String label, bool active, VoidCallback onTap) => Touchable(
          activeOpacity: 0.8,
          onPress: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? c.primary : c.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? c.primary : c.border),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : c.textSecondary)),
          ),
        );

    final items = <Widget>[];
    if (_failed.isNotEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ErrorState(
          compact: true,
          message: "Couldn't load ${_failed.length == 1 ? _failed.single : '${_failed.length} centres'}. Pull down to retry.",
          onRetry: _schedule.reload,
        ),
      ));
    }
    var lastDay = -2;
    for (final s in shown) {
      if (s.weekday != lastDay) {
        lastDay = s.weekday;
        final count = shown.where((x) => x.weekday == s.weekday).length;
        items.add(Padding(
          padding: EdgeInsets.only(top: items.isEmpty ? 0 : 14, bottom: 8),
          child: Text('${_dayLabels[s.weekday]} · $count class${count == 1 ? '' : 'es'}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.textPrimary)),
        ));
      }
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RkCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CentreRosterPage(centreId: s.centreId, centreName: s.centre, classLabel: s.label))),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.primary.hexA('18'), shape: BoxShape.circle),
              child: Icon(Ion.timeOutline, size: 18, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _title(context, s.label),
                const SizedBox(height: 2),
                Text(s.centre.isEmpty ? '—' : s.centre,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ]),
            ),
            Icon(Ion.peopleOutline, size: 16, color: c.textMuted),
            const SizedBox(width: 2),
            Icon(Ion.chevronForward, size: 14, color: c.textMuted),
          ]),
        ),
      ));
    }

    Widget body;
    if (_schedule.loading && _schedule.data == null) {
      body = const RnSpinner(vertical: 60);
    } else if (_schedule.data == null) {
      body = Padding(
        padding: const EdgeInsets.all(Gaps.xl),
        child: ErrorState(message: _schedule.error ?? "Couldn't load training times.", onRetry: _schedule.reload),
      );
    } else if (shown.isEmpty && _failed.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(Ion.calendarOutline, size: 44, color: c.textMuted),
          const SizedBox(height: 10),
          Text(all.isEmpty ? 'No training times at your centres.' : 'No classes match these filters.',
              textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 14)),
        ]),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ScreenHeader(
          title: 'Training Schedule',
          subtitle: _schedule.data == null
              ? null
              : '${inCentre.length} class${inCentre.length == 1 ? '' : 'es'} · $centreCount centre${centreCount == 1 ? '' : 's'}',
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectField(
              label: 'Training Center',
              placeholder: 'All Centers',
              value: _centreId,
              options: centreOptions,
              loading: _schedule.loading && _schedule.data == null,
              onChange: (id, _) => setState(() {
                _centreId = id;
                _day = -1;
              }),
            ),
            if (days.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 32,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  chip('All days', _day < 0, () => setState(() => _day = -1)),
                  for (final d in days) ...[
                    const SizedBox(width: 6),
                    chip(d == 0 ? 'Other' : _dayLabels[d].substring(0, 3), _day == d, () => setState(() => _day = d)),
                  ],
                ]),
              ),
            ],
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _schedule.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, 120),
              children: [body],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Students registered at one centre. The club system has no list per training time, so a
/// class opens its centre's roster and says so.
class CentreRosterPage extends StatefulWidget {
  final Object centreId;
  final String centreName;
  final String? classLabel;
  const CentreRosterPage({super.key, required this.centreId, required this.centreName, this.classLabel});
  @override
  State<CentreRosterPage> createState() => _CentreRosterPageState();
}

class _CentreRosterPageState extends State<CentreRosterPage> with UseApi<CentreRosterPage> {
  final _search = TextEditingController();
  late final _roster = useApi(() => RnApi.studentListByTcId(RnApi.number(widget.centreId).toInt()));

  @override
  void initState() {
    super.initState();
    _roster;
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final q = _search.text.trim().toLowerCase();
    final all = _roster.data ?? const <Row_>[];
    final shown = q.isEmpty
        ? all
        : all
            .where((s) => '${s['text'] ?? ''}'.toLowerCase().contains(q) || '${s['value'] ?? ''}'.toLowerCase().contains(q))
            .toList();
    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ScreenHeader(
          title: widget.centreName.isEmpty ? 'Class List' : widget.centreName,
          subtitle: _roster.data == null ? null : '${all.length} student${all.length == 1 ? '' : 's'} at this centre',
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.lg)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.classLabel != null) ...[
              Text(widget.classLabel!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
              const SizedBox(height: 4),
            ],
            Text('Everyone registered at this centre. The club system does not list students per training time yet.',
                style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 16 / 11.5)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                  color: c.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.border)),
              child: Row(children: [
                Icon(Ion.searchOutline, size: 15, color: c.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _search,
                    autocorrect: false,
                    style: TextStyle(fontSize: 14, color: c.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      hintText: 'Search name or reg no',
                      hintStyle: TextStyle(color: c.textMuted),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _roster.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, 120),
              children: [
                if (_roster.loading && _roster.data == null)
                  const RnSpinner(vertical: 60)
                else if (_roster.data == null)
                  ErrorState(message: _roster.error ?? "Couldn't load the class list.", onRetry: _roster.reload)
                else if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(all.isEmpty ? 'No students at this centre.' : 'No students match your search.',
                        textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 14)),
                  )
                else
                  for (final s in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RkCard(
                        child: Row(children: [
                          _studentAvatar(s, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _title(context, '${s['text'] ?? ''}', lines: 1),
                              if ('${s['value'] ?? ''}'.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text('${s['value']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
                              ],
                            ]),
                          ),
                        ]),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── r-grading (Grading Schedule / Grade Completed) ─────────────────────────────
class RGradingScreen extends StatefulWidget {
  final String title;
  const RGradingScreen({super.key, this.title = 'Grading Schedule'});
  @override
  State<RGradingScreen> createState() => _RGradingScreenState();
}

class _RGradingScreenState extends State<RGradingScreen> with UseApi<RGradingScreen> {
  DateTime _from = _monthStart();
  DateTime _to = _today();
  Object _examCenterId = '';
  // Snapshot of the filters as of the last Search press.
  ({String centerText, DateTime from, DateTime to})? _applied;

  late final _centers = useApi(() => RnApi.dropdownListByType(2));
  // Fetched once and narrowed here: the route ignores eCenterId/fromDate/toDate.
  late final _report = useApi(() => RnApi.gradingSchedule({'eCenterId': null, 'fromDate': null, 'toDate': null}));

  @override
  void initState() {
    super.initState();
    _centers;
    _report;
  }

  DateTime? _dayOf(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  @override
  Widget build(BuildContext context) {
    final centerOptions = [(id: '', text: 'All centers'), ..._opts(_centers.data)];
    final applied = _applied;
    var rows = <Row_>[];
    if (applied != null) {
      final wanted = applied.centerText.trim().toLowerCase();
      rows = (_report.data ?? const <Row_>[]).where((r) {
        if (wanted.isNotEmpty && '${r['ecName'] ?? ''}'.trim().toLowerCase() != wanted) return false;
        final day = _dayOf(r['examDate']);
        if (day == null) return true; // keep undated rows rather than hide a real exam
        return !day.isBefore(applied.from) && !day.isAfter(applied.to);
      }).toList()
        ..sort((a, b) => (_dayOf(a['examDate']) ?? DateTime(0)).compareTo(_dayOf(b['examDate']) ?? DateTime(0)));
    }
    return ReportScaffold<Row_>(
      title: widget.title,
      subtitle: applied == null ? null : '${rows.length} exam${rows.length == 1 ? '' : 's'} in range',
      loading: _report.loading,
      error: _report.error,
      data: applied == null ? const [] : rows,
      onSearch: () {
        final opt = centerOptions.where((o) => '${o.id}' == '$_examCenterId').firstOrNull;
        setState(() => _applied = (
              centerText: '$_examCenterId'.isEmpty ? '' : (opt?.text ?? ''),
              from: DateTime(_from.year, _from.month, _from.day),
              to: DateTime(_to.year, _to.month, _to.day),
            ));
      },
      emptyText: applied != null ? 'No grading scheduled for these dates.' : 'Choose a date range and press Search.',
      filters: [
        Row(children: [
          Expanded(child: DateField(label: 'From', value: _from, onChange: (d) => setState(() => _from = d))),
          const SizedBox(width: 10),
          Expanded(child: DateField(label: 'To', value: _to, onChange: (d) => setState(() => _to = d))),
        ]),
        SelectField(
          label: 'Exam Center',
          placeholder: 'All centers',
          value: _examCenterId,
          options: centerOptions,
          loading: _centers.loading,
          onChange: (id, _) => setState(() => _examCenterId = id),
        ),
      ],
      renderItem: (r, _) => RkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, '${r['ecName'] ?? ''}', lines: 1, bottom: 2),
          KV('Exam Date', fmtDateGB(r['examDate'])),
          KV('Closing Date', fmtDateGB(r['closingDate'])),
          KV('Exam Time', r['examTime']),
        ]),
      ),
    );
  }
}

// ── r-outstanding ──────────────────────────────────────────────────────────────
class ROutstandingScreen extends StatefulWidget {
  const ROutstandingScreen({super.key});
  @override
  State<ROutstandingScreen> createState() => _ROutstandingScreenState();
}

class _ROutstandingScreenState extends State<ROutstandingScreen> with UseApi<ROutstandingScreen> {
  String _type = '';
  late final _types = useApi(RnApi.invoiceTypes);
  late final _data = useApi<List<Row_>>(() async {
    final d = unwrapData(await Api.outstandingFetch({
      'studentId': null,
      'studentName': null,
      'icNo': null,
      'startDate': null,
      'endDate': null,
      'eCenterId': null,
      'tCenterId': null,
      'sCenterId': null,
      'transactionType': _type.isEmpty ? null : _type,
    }));
    return d is List ? d.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
  });

  @override
  void initState() {
    super.initState();
    _types;
    _data;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final rows = _data.data ?? const <Row_>[];
    final totalDue = rows.fold<num>(0, (s, r) => s + RnApi.number(r['dueAmount']));
    return ReportScaffold<Row_>(
      title: 'Outstanding',
      loading: _data.loading,
      error: _data.error,
      data: rows,
      onRefresh: _data.reload,
      emptyText: 'No outstanding invoices.',
      filters: [
        SelectField(
          label: 'Filter By Transaction Type',
          placeholder: 'All',
          value: _type,
          options: [(id: '', text: 'All'), for (final t in _types.data ?? const <Row_>[]) (id: '${t['id']}', text: '${t['text'] ?? ''}')],
          loading: _types.loading,
          onChange: (id, _) {
            setState(() => _type = '$id');
            _data.reload();
          },
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total Invoice(s): ${rows.length}',
              style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w700)),
          Text('Due Amt: RM ${money2(totalDue)}', style: TextStyle(fontSize: 13, color: c.primary, fontWeight: FontWeight.w800)),
        ]),
      ],
      renderItem: (r, _) => RkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(context, '${r['studentName'] ?? ''}', bottom: 2),
          KV('Type', r['transactionType']),
          KV('Period', r['period']),
          KV('Due Amt', 'RM ${money2(RnApi.number(r['dueAmount']))}', strong: true),
          KV('Classes Attended', r['attendanceCount']),
          KV('Status', r['paymentStatus']),
          KV('Center', r['centerName']),
        ]),
      ),
    );
  }
}

// ── r-attendance ───────────────────────────────────────────────────────────────
String _fmtDateTime(dynamic x) {
  final d = DateTime.tryParse('${x ?? ''}');
  if (d == null) return '${x ?? ''}';
  return '${fmtDateGB(x)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class RAttendanceScreen extends StatefulWidget {
  const RAttendanceScreen({super.key});
  @override
  State<RAttendanceScreen> createState() => _RAttendanceScreenState();
}

class _RAttendanceScreenState extends State<RAttendanceScreen> with UseApi<RAttendanceScreen> {
  Object? _centerId;
  Object? _timeId;
  Object? _studentId;
  DateTime _from = _monthStart();
  DateTime _to = _today();

  late final _centers = useApi(() => RnApi.dropdownListByType(3));
  late final _times = useApi<List<Row_>>(
      () async => _centerId == null ? const <Row_>[] : await RnApi.trainingTimeByTcId(RnApi.number(_centerId).toInt()),
      autoRun: false);
  late final _students = useApi<List<Row_>>(
      () async => _centerId == null ? const <Row_>[] : await RnApi.studentListByTcId(RnApi.number(_centerId).toInt()),
      autoRun: false);
  late final _rows = useApi<List<Row_>>(
      () => RnApi.attendanceReport({
            'tCenterId': _centerId == null ? null : RnApi.number(_centerId).toInt(),
            'tTimeId': _timeId == null ? null : RnApi.number(_timeId).toInt(),
            'sourceKeyId': _studentId == null ? null : RnApi.number(_studentId).toInt(),
            'fromDate': toISODate(_from),
            'toDate': toISODate(_to),
          }),
      autoRun: false);

  @override
  void initState() {
    super.initState();
    _centers;
    _times;
    _students;
    _rows;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return ReportScaffold<Row_>(
      title: 'Attendance Report',
      loading: _rows.loading,
      error: _rows.error,
      data: _rows.data,
      onSearch: _rows.reload,
      emptyText: 'No attendance records.',
      filters: [
        SelectField(
          label: 'Training Center',
          placeholder: 'Select training center',
          value: _centerId,
          options: _opts(_centers.data),
          loading: _centers.loading,
          onChange: (id, _) {
            setState(() {
              _centerId = id;
              _timeId = null;
              _studentId = null;
            });
            _times.reload();
            _students.reload();
          },
        ),
        SelectField(
          label: 'Training Time',
          placeholder: 'Select training time',
          value: _timeId,
          options: _centerId == null ? const [] : _opts(_times.data),
          loading: _times.loading,
          disabled: _centerId == null,
          onChange: (id, _) => setState(() => _timeId = id),
        ),
        Row(children: [
          Expanded(child: DateField(label: 'From', value: _from, onChange: (d) => setState(() => _from = d))),
          const SizedBox(width: 10),
          Expanded(child: DateField(label: 'To', value: _to, onChange: (d) => setState(() => _to = d))),
        ]),
        SelectField(
          label: 'Student',
          placeholder: 'All students',
          value: _studentId,
          options: _centerId == null ? const [] : _opts(_students.data),
          loading: _students.loading,
          disabled: _centerId == null,
          onChange: (id, _) => setState(() => _studentId = id),
        ),
      ],
      renderItem: (r, _) {
        final present = r['attendanceType'] == 'Present';
        return RkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _title(context, '${r['name'] ?? ''}', lines: 1),
            KV('IC No', r['icNo']),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Text('Type', style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('${r['attendanceType'] ?? ''}'.isEmpty ? '—' : '${r['attendanceType']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: present ? c.success : c.danger)),
                ),
              ]),
            ),
            KV('Date/Time', _fmtDateTime(r['recordedTime'])),
            KV('Center', r['trainingCenter']),
          ]),
        );
      },
    );
  }
}

// ── r-receipts ─────────────────────────────────────────────────────────────────
class RReceiptsScreen extends StatefulWidget {
  const RReceiptsScreen({super.key});
  @override
  State<RReceiptsScreen> createState() => _RReceiptsScreenState();
}

class _RReceiptsScreenState extends State<RReceiptsScreen> with UseApi<RReceiptsScreen> {
  static const _modes = <RkOption>[(id: '', text: 'All'), (id: 'Cash', text: 'Cash'), (id: 'Online', text: 'Online'), (id: 'Bank-In', text: 'Bank-In')];
  DateTime _from = _monthStart();
  DateTime _to = _today();
  String _mode = '';
  Object? _centerId;
  bool _searched = false;

  late final _centers = useApi(() => RnApi.dropdownListByType(3));
  late final _report = useApi<List<Row_>>(
      () => RnApi.receipts({
            'tCenterId': _centerId == null ? null : RnApi.number(_centerId).toInt(),
            'reportType': _mode.isEmpty ? null : _mode,
            'fromDate': toISODate(_from),
            'toDate': toISODate(_to),
          }),
      autoRun: false);

  @override
  void initState() {
    super.initState();
    _centers;
    _report;
  }

  @override
  Widget build(BuildContext context) => ReportScaffold<Row_>(
        title: 'Receipt Report',
        loading: _report.loading && _searched,
        error: _report.error,
        data: _searched ? _report.data : const [],
        onSearch: () {
          setState(() => _searched = true);
          _report.reload();
        },
        emptyText: 'No receipts found.',
        filters: [
          Row(children: [
            Expanded(child: DateField(label: 'From', value: _from, onChange: (d) => setState(() => _from = d))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'To', value: _to, onChange: (d) => setState(() => _to = d))),
          ]),
          SelectField(label: 'Payment Mode', placeholder: 'All', value: _mode, options: _modes, onChange: (id, _) => setState(() => _mode = '$id')),
          SelectField(
            label: 'Training Center',
            placeholder: 'Select center',
            value: _centerId,
            options: _opts(_centers.data),
            loading: _centers.loading,
            onChange: (id, _) => setState(() => _centerId = id),
          ),
        ],
        renderItem: (r, _) => RkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _title(context, '${r['name'] ?? ''}', lines: 1, bottom: 2),
            KV('IC No', r['icNo']),
            KV('Receipt No', r['receiptNo']),
            KV('Date', fmtDateGB(r['receiptDate'])),
            KV('Amount', 'RM ${money2(RnApi.number(r['receiptAmount']))}', strong: true),
            KV('Method', r['paymentMethod']),
            KV('Center', r['tcName']),
          ]),
        ),
      );
}

// ── r-purchase-requests / r-payment-slips (same shape) ─────────────────────────
const _statusOptions = <RkOption>[(id: 'Pending', text: 'Pending'), (id: 'Approved', text: 'Approved'), (id: 'Rejected', text: 'Rejected')];

class RPurchaseRequestsScreen extends StatefulWidget {
  const RPurchaseRequestsScreen({super.key});
  @override
  State<RPurchaseRequestsScreen> createState() => _RPurchaseRequestsScreenState();
}

class _RPurchaseRequestsScreenState extends State<RPurchaseRequestsScreen> with UseApi<RPurchaseRequestsScreen> {
  Object? _centerId;
  Object _status = 'Pending';
  late final _centers = useApi(() => RnApi.dropdownListByType(3));
  late final _rows = useApi<List<Row_>>(
      () => RnApi.purchaseRequests({
            'tCenterId': _centerId == null ? null : RnApi.number(_centerId).toInt(),
            'reportType': '$_status',
            'fromDate': null,
            'toDate': null,
          }),
      autoRun: false);

  @override
  void initState() {
    super.initState();
    _centers;
    _rows;
  }

  @override
  Widget build(BuildContext context) => ReportScaffold<Row_>(
        title: 'Purchase Requests',
        onSearch: _rows.reload,
        loading: _rows.loading,
        error: _rows.error,
        data: _rows.data,
        emptyText: 'No purchase requests.',
        filters: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: SelectField(
                label: 'Training Center',
                placeholder: 'Select',
                value: _centerId,
                options: _opts(_centers.data),
                loading: _centers.loading,
                onChange: (id, _) => setState(() => _centerId = id),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectField(label: 'Status', placeholder: 'Select', value: _status, options: _statusOptions, onChange: (id, _) => setState(() => _status = id)),
            ),
          ]),
        ],
        renderItem: (r, _) {
          final itemName = r['item'] ?? r['productName'];
          final center = r['centerName'] ?? r['tcName'];
          return RkCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title(context, '${r['studentName'] ?? r['name'] ?? r['item'] ?? 'Request'}'),
              if (itemName != null) KV('Item', itemName),
              if (r['qty'] != null) KV('Qty', r['qty']),
              if (r['status'] != null) KV('Status', r['status']),
              if (center != null) KV('Center', center),
            ]),
          );
        },
      );
}

class RPaymentSlipsScreen extends StatefulWidget {
  const RPaymentSlipsScreen({super.key});
  @override
  State<RPaymentSlipsScreen> createState() => _RPaymentSlipsScreenState();
}

class _RPaymentSlipsScreenState extends State<RPaymentSlipsScreen> with UseApi<RPaymentSlipsScreen> {
  Object? _centerId;
  Object _status = 'Pending';
  late final _centers = useApi(() => RnApi.dropdownListByType(3));
  late final _rows = useApi<List<Row_>>(
      () => RnApi.paymentSlips({
            'tCenterId': _centerId == null ? null : RnApi.number(_centerId).toInt(),
            'reportType': '$_status',
            'fromDate': null,
            'toDate': null,
          }),
      autoRun: false);

  @override
  void initState() {
    super.initState();
    _centers;
    _rows;
  }

  @override
  Widget build(BuildContext context) => ReportScaffold<Row_>(
        title: 'Payment Slips',
        onSearch: _rows.reload,
        loading: _rows.loading,
        error: _rows.error,
        data: _rows.data,
        emptyText: 'No payment slips.',
        filters: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: SelectField(
                label: 'Training Center',
                placeholder: 'Select',
                value: _centerId,
                options: _opts(_centers.data),
                loading: _centers.loading,
                onChange: (id, _) => setState(() => _centerId = id),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectField(label: 'Status', placeholder: 'Select', value: _status, options: _statusOptions, onChange: (id, _) => setState(() => _status = id)),
            ),
          ]),
        ],
        renderItem: (r, _) => RkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _title(context, '${r['name'] ?? ''}'),
            KV('IC No', r['icNo']),
            KV('Receipt No', r['receiptNo']),
            KV('Date', fmtDateGB(r['receiptDate'])),
            KV('Amount', 'RM ${money2(RnApi.number(r['receiptAmount']))}', strong: true),
            KV('Status', r['status']),
            KV('Center', r['tcName']),
          ]),
        ),
      );
}

// ── r-tournament-summary ───────────────────────────────────────────────────────
/// `/Reports/TournamentSummary` is a date-less medal summary. Expo showed it twice, as
/// "Tournaments (Past)" and "Upcoming Tournaments", with identical rows; this is one report.
class RTournamentScreen extends StatefulWidget {
  const RTournamentScreen({super.key});
  @override
  State<RTournamentScreen> createState() => _RTournamentScreenState();
}

class _RTournamentScreenState extends State<RTournamentScreen> with UseApi<RTournamentScreen> {
  String _name = '';
  // No reportType: the route casts it to int and 400s on a word.
  late final _data = useApi(() => RnApi.tournamentSummary({'fromDate': null, 'toDate': null}));

  @override
  void initState() {
    super.initState();
    _data;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final all = _data.data ?? const <Row_>[];
    final seen = <String>{};
    final nameOptions = <RkOption>[
      (id: '', text: 'All'),
      for (final r in all)
        if ('${r['name'] ?? ''}'.trim().isNotEmpty && seen.add('${r['name']}'.trim()))
          (id: '${r['name']}'.trim(), text: '${r['name']}'.trim()),
    ];
    final rows = _name.isEmpty ? all : all.where((r) => '${r['name'] ?? ''}'.trim() == _name).toList();
    return ReportScaffold<Row_>(
      title: 'Tournament Summary',
      loading: _data.loading,
      error: _data.error,
      data: rows,
      onRefresh: _data.reload,
      emptyText: 'No tournament results were returned for your account.',
      // Rows grouped only by gender carry no name; a filter holding just "All" is noise.
      filters: nameOptions.length > 2
          ? [
              SelectField(label: 'Tournament Name', placeholder: 'All', value: _name, options: nameOptions, onChange: (id, _) => setState(() => _name = '$id')),
            ]
          : null,
      renderItem: (r, _) {
        String t(dynamic v) => '${v ?? ''}'.trim();
        final title = t(r['name']).isNotEmpty ? t(r['name']) : t(r['category']).isNotEmpty ? t(r['category']) : t(r['gender']).isNotEmpty ? t(r['gender']) : 'Tournament';
        return RkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _title(context, title, bottom: 2),
            if (t(r['ageGroup']).isNotEmpty) KV('Age Group', r['ageGroup']),
            if (t(r['gender']).isNotEmpty && t(r['gender']) != title) KV('Gender', r['gender']),
            KV('Players', RnApi.number(r['playerCount']).toInt()),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Gold ${RnApi.number(r['medalGold']).toInt()} · Silver ${RnApi.number(r['medalSilver']).toInt()} · Bronze ${RnApi.number(r['medalBronze']).toInt()}',
                  style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      },
    );
  }
}

// ── r-contribution ─────────────────────────────────────────────────────────────
class RContributionScreen extends StatefulWidget {
  const RContributionScreen({super.key});
  @override
  State<RContributionScreen> createState() => _RContributionScreenState();
}

class _RContributionScreenState extends State<RContributionScreen> with UseApi<RContributionScreen> {
  DateTime _from = _monthStart();
  DateTime _to = _today();
  bool _searched = false;
  // /Reports/Contribution casts reportType to an int server-side (same quirk as
  // /Reports/Reimbursement and /Reports/TournamentSummary — see docs/ARCHITECTURE.md,
  // "Report-route quirks"): a word like 'HQ'/'BRANCH' 400s, so RnApi.contributionReport strips
  // it to null and the server returns every contribution row, undifferentiated. Unlike
  // RReimbursementScreen's status filter, we have no live sample of a Contribution row to know
  // which field (if any) would let us split HQ vs Branch client-side, so the Type filter below
  // is shown disabled rather than pretending to work.
  late final _report = useApi<List<Row_>>(
      () => RnApi.contributionReport({'fromDate': toISODate(_from), 'toDate': toISODate(_to), 'reportType': null}),
      autoRun: false);

  @override
  void initState() {
    super.initState();
    _report;
  }

  @override
  Widget build(BuildContext context) => ReportScaffold<Row_>(
        title: 'Contribution Report',
        loading: _report.loading && _searched,
        error: _report.error,
        data: _searched ? _report.data : const [],
        onSearch: () {
          setState(() => _searched = true);
          _report.reload();
        },
        emptyText: 'No contribution records.',
        filters: [
          Row(children: [
            Expanded(child: DateField(label: 'From', value: _from, onChange: (d) => setState(() => _from = d))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'To', value: _to, onChange: (d) => setState(() => _to = d))),
          ]),
          SelectField(
            label: 'Type',
            placeholder: 'Not available from server',
            value: null,
            options: const [],
            disabled: true,
            onChange: (_, __) {},
          ),
        ],
        renderItem: (r, _) {
          final date = r['date'] ?? r['invoiceDate'];
          final center = r['centerName'] ?? r['tcName'];
          return RkCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title(context, '${r['name'] ?? r['centerName'] ?? r['studentName'] ?? 'Contribution'}', lines: 1, bottom: 2),
              if (r['amount'] != null) KV('Amount', 'RM ${money2(RnApi.number(r['amount']))}', strong: true),
              if (date != null) KV('Date', fmtDateGB(date)),
              if (r['status'] != null) KV('Status', r['status']),
              if (center != null) KV('Center', center),
            ]),
          );
        },
      );
}

// ── r-reimbursement ────────────────────────────────────────────────────────────
class RReimbursementScreen extends StatefulWidget {
  const RReimbursementScreen({super.key});
  @override
  State<RReimbursementScreen> createState() => _RReimbursementScreenState();
}

class _RReimbursementScreenState extends State<RReimbursementScreen> with UseApi<RReimbursementScreen> {
  static const _statuses = <RkOption>[(id: '', text: 'All'), (id: 'Reimbursed', text: 'Reimbursed'), (id: 'Pending', text: 'Pending')];
  DateTime _from = _monthStart();
  DateTime _to = _today();
  String _status = '';
  // Status is narrowed here, not by the API: the route casts reportType to an int.
  late final _rows = useApi<List<Row_>>(() async {
    final all = await RnApi.reimbursementReport({'fromDate': toISODate(_from), 'toDate': toISODate(_to), 'reportType': null});
    final wanted = _status.trim().toLowerCase();
    return wanted.isEmpty ? all : all.where((r) => _statusOf(r).toLowerCase() == wanted).toList();
  }, autoRun: false);

  static String _statusOf(Map r) => '${r['status'] ?? r['reimbursementStatus'] ?? r['paymentStatus'] ?? ''}'.trim();

  @override
  void initState() {
    super.initState();
    _rows;
  }

  @override
  Widget build(BuildContext context) => ReportScaffold<Row_>(
        title: 'Reimbursement Report',
        loading: _rows.loading,
        error: _rows.error,
        data: _rows.data,
        onSearch: _rows.reload,
        emptyText: 'No reimbursement records.',
        filters: [
          Row(children: [
            Expanded(child: DateField(label: 'From', value: _from, onChange: (d) => setState(() => _from = d))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'To', value: _to, onChange: (d) => setState(() => _to = d))),
          ]),
          SelectField(label: 'Status', placeholder: 'Select status', value: _status, options: _statuses, onChange: (id, _) => setState(() => _status = '$id')),
        ],
        renderItem: (r, _) {
          final date = r['date'] ?? r['invoiceDate'];
          final s = _statusOf(r);
          return RkCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _title(context, '${r['name'] ?? r['studentName'] ?? 'Reimbursement'}', lines: 1),
              if (r['amount'] != null) KV('Amount', 'RM ${money2(RnApi.number(r['amount']))}', strong: true),
              if (date != null && '$date'.isNotEmpty) KV('Date', fmtDateGB(date)),
              if (s.isNotEmpty) KV('Status', s),
            ]),
          );
        },
      );
}
