import 'package:flutter/material.dart';

import '../services/manual_attendance.dart';
import '../services/response_utils.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/member_avatar.dart';
import '../widgets/report_kit.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// Manual Attendance — the portal's Mark Attendance page.
///
/// A student who missed their own class and trained with another section gets that day's
/// attendance here: the instructor picks students or instructors, the date, the student's own
/// centre and class time, ticks one, several or all, and saves.
class ManualAttendanceScreen extends StatefulWidget {
  const ManualAttendanceScreen({super.key});
  @override
  State<ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<ManualAttendanceScreen> with UseApi<ManualAttendanceScreen> {
  String _type = ManualAttendance.student;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  int? _centreId;
  int? _timeId;
  final Set<int> _picked = {};
  String _query = '';
  bool _saving = false;

  late final _centres = useApi(ManualAttendance.centres);
  late final _times = useApi<List<Map<String, dynamic>>>(
      () async => _centreId == null ? const [] : await ManualAttendance.trainingTimes(_centreId!, _date),
      autoRun: false);
  late final _people = useApi<List<AttendancePerson>>(
      () async => _centreId == null || _timeId == null
          ? const []
          : await ManualAttendance.people(type: _type, centreId: _centreId!, timeId: _timeId!, date: _date),
      autoRun: false);

  @override
  void initState() {
    super.initState();
    _centres;
    _times;
    _people;
  }

  bool get _isStudent => _type == ManualAttendance.student;

  /// Anything upstream changed: never keep ticks or a list that belong to another class.
  void _reloadPeople() {
    _picked.clear();
    _people.data = null;
    if (_timeId != null) _people.reload();
  }

  void _reloadTimes() {
    _timeId = null;
    _times.data = null;
    _reloadPeople();
    if (_centreId != null) _times.reload();
  }

  List<RkOption> _options(List<Map<String, dynamic>>? rows) => [
        for (final o in rows ?? const <Map<String, dynamic>>[])
          if (o['id'] != null) (id: o['id'] as Object, text: '${o['text'] ?? ''}')
      ];

  Future<void> _pickDate(DateTime d) async {
    if (d.isAfter(DateUtils.dateOnly(DateTime.now()))) {
      await notify(
          context, 'Pick today or an earlier day', "Attendance can't be marked for a day that hasn't happened yet.");
      return;
    }
    setState(() {
      _date = d;
      _reloadTimes();
    });
  }

  Future<void> _save(String centreName, String timeName) async {
    final ids = [
      for (final p in _people.data ?? const <AttendancePerson>[])
        if (_picked.contains(p.id)) p.id
    ];
    if (ids.isEmpty || _centreId == null || _timeId == null || _saving) return;
    final who = '${ids.length} ${_isStudent ? 'student' : 'instructor'}${ids.length == 1 ? '' : 's'}';
    final ok = await confirmDialog(context, 'Mark $who present?',
        message: '$centreName · $timeName\n${fmtDateGB(_date.toIso8601String())}', confirmLabel: 'Save');
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final r =
          await ManualAttendance.add(type: _type, centreId: _centreId!, timeId: _timeId!, date: _date, personIds: ids);
      if (!mounted) return;
      setState(_reloadPeople);
      await notify(
        context,
        r.added > 0 ? 'Attendance saved' : 'Nothing new saved',
        [
          '${r.added} of ${ids.length} marked present.',
          if (r.alreadyMarkedIds.isNotEmpty) '${r.alreadyMarkedIds.length} already had attendance for this class.',
        ].join(' '),
      );
    } catch (e) {
      if (mounted) await notify(context, "Couldn't save attendance", friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final centreOptions = _options(_centres.data);
    final timeOptions = _options(_times.data);
    final centreName = centreOptions.where((o) => '${o.id}' == '$_centreId').firstOrNull?.text ?? '';
    final timeName = timeOptions.where((o) => '${o.id}' == '$_timeId').firstOrNull?.text ?? '';
    final people = _people.data ?? const <AttendancePerson>[];
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? people : people.where((p) => p.name.toLowerCase().contains(q)).toList();
    final open = {
      for (final p in shown)
        if (!p.alreadyMarked) p.id
    };
    final allPicked = open.isNotEmpty && open.every(_picked.contains);
    final error = _centres.error ?? _times.error ?? _people.error;
    final noun = _isStudent ? 'Students' : 'Instructors';

    Widget typePill(String type) {
      final on = _type == type;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: Touchable(
            onPress: on
                ? null
                : () => setState(() {
                      _type = type;
                      _reloadPeople();
                    }),
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.primary : c.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? c.primary : c.border),
              ),
              child: Text(type,
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? Colors.white : c.textSecondary)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ScreenHeader(
          title: 'Manual Attendance',
          subtitle: timeName.isEmpty ? 'Mark attendance for a class' : '$centreName · $timeName',
        ),
        Expanded(
          child: AbsorbPointer(
            absorbing: _saving,
            child: RefreshIndicator(
              color: c.primary,
              onRefresh: () =>
                  Future.wait([_centres.reload(), if (_centreId != null) _times.reload(), _people.reload()]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: 40 + bottom),
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.xl)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const RkLabel('Attendance Type'),
                      Row(children: [
                        typePill(ManualAttendance.student),
                        const SizedBox(width: 10),
                        typePill(ManualAttendance.instructor),
                      ]),
                      const SizedBox(height: 12),
                      const RkLabel('Attendance Date'),
                      DateField(value: _date, onChange: _pickDate),
                      const SizedBox(height: 12),
                      SelectField(
                        label: 'Training Centre',
                        placeholder: 'Select centre',
                        value: _centreId,
                        options: centreOptions,
                        loading: _centres.loading,
                        onChange: (id, _) => setState(() {
                          _centreId = int.tryParse('$id');
                          _reloadTimes();
                        }),
                      ),
                      const SizedBox(height: 12),
                      SelectField(
                        label: 'Training Time',
                        placeholder: _centreId == null
                            ? 'Select centre first'
                            : _times.data != null && timeOptions.isEmpty
                                ? 'No classes on this day'
                                : 'Select time',
                        value: _timeId,
                        options: timeOptions,
                        loading: _times.loading,
                        disabled: _centreId == null || timeOptions.isEmpty,
                        onChange: (id, _) => setState(() {
                          _timeId = int.tryParse('$id');
                          _reloadPeople();
                        }),
                      ),
                    ]),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 0),
                      child: ErrorState(
                        message: error,
                        onRetry: () {
                          _centres.reload();
                          if (_centreId != null) _times.reload();
                          if (_timeId != null) _people.reload();
                        },
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(Gaps.xl, 14, Gaps.xl, 0),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.lg)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Ion.informationCircleOutline, size: 17, color: c.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            "For a student who trained with another section, choose the student's own centre and class time and the day they trained.",
                            style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 17 / 11.5)),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gaps.xl, 24, Gaps.xl, 10),
                    child: Row(children: [
                      Expanded(
                        child: Text(noun,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary)),
                      ),
                      if (open.isNotEmpty && !_people.loading)
                        Touchable(
                          onPress: () => setState(() => allPicked ? _picked.removeAll(open) : _picked.addAll(open)),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text(allPicked ? 'Clear all' : 'Select all',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.primary)),
                          ),
                        ),
                      if (_people.loading)
                        SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                      else if (_people.data != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration:
                              BoxDecoration(color: c.primary.hexA('1A'), borderRadius: BorderRadius.circular(12)),
                          child: Text('${people.length}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.primary)),
                        ),
                    ]),
                  ),
                  if (people.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
                      child: Row(children: [
                        Icon(Ion.search, size: 16, color: c.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            autocorrect: false,
                            onChanged: (v) => setState(() => _query = v),
                            cursorColor: c.primary,
                            style: TextStyle(color: c.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              hintText: 'Search by name',
                              hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: _people.loading
                          ? Center(
                              child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(strokeWidth: 3, color: c.primary)))
                          : Column(children: [
                              Icon(Ion.peopleOutline, size: 44, color: c.textMuted),
                              const SizedBox(height: 10),
                              Text(
                                  _timeId == null
                                      ? 'Choose a training centre and class time to load the list.'
                                      : people.isEmpty
                                          ? 'No ${noun.toLowerCase()} in this class.'
                                          : 'No one matches "${_query.trim()}".',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: c.textSecondary, fontSize: 14)),
                            ]),
                    ),
                  for (final (i, p) in shown.indexed) _row(c, i, p),
                ],
              ),
            ),
          ),
        ),
        if (_picked.isNotEmpty)
          Container(
            padding: EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 12 + bottom),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.borderLight))),
            child: Touchable(
              activeOpacity: 0.9,
              onPress: _saving ? null : () => _save(centreName, timeName),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: c.gradient), borderRadius: BorderRadius.circular(999)),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Save attendance (${_picked.length})',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _row(AppColors c, int i, AttendancePerson p) {
    final picked = _picked.contains(p.id);
    final row = Container(
      margin: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 8),
      padding: const EdgeInsets.all(12),
      decoration: picked ? rnCard(c).copyWith(border: Border.all(color: c.primary, width: 1.5)) : rnCard(c),
      child: Row(children: [
        SizedBox(
          width: 20,
          child: Text('${i + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMuted)),
        ),
        const SizedBox(width: 10),
        MemberAvatar(name: p.name, size: 40, radius: 20, foreground: c.primary, background: c.surfaceAlt),
        const SizedBox(width: 10),
        Expanded(
          child: Text(p.name.isEmpty ? '—' : p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
        ),
        const SizedBox(width: 10),
        if (p.alreadyMarked)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: c.success.hexA('1F'), borderRadius: BorderRadius.circular(999)),
            child:
                Text('Already marked', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.success)),
          )
        else
          Icon(picked ? Ion.checkmarkCircle : Ion.ellipseOutline,
              size: 26, color: picked ? c.primary : c.textMuted, semanticLabel: picked ? 'Selected' : 'Not selected'),
      ]),
    );
    if (p.alreadyMarked) return row;
    return Touchable(
      activeOpacity: 0.8,
      onPress: () => setState(() => picked ? _picked.remove(p.id) : _picked.add(p.id)),
      child: row,
    );
  }
}
