import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../services/api.dart';
import '../services/api_service.dart';
import '../services/manual_attendance.dart';
import '../services/response_utils.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../utils/qr_content.dart';
import '../widgets/report_kit.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// Port of `frontend/app/update-attendance.tsx` (Expo v2.11.1) — Class Check-In.
///
/// Students check in by scanning the centre QR: `/Attendance/Add` only records the token
/// holder. The tick-and-save register appears only when the server's route table has
/// [ManualAttendance.route] (proposed in docs/specs/2026-09-15-manual-attendance.md), so it
/// goes live with the backend and never offers a Save that cannot work.
class InstructorAttendanceScreen extends StatefulWidget {
  const InstructorAttendanceScreen({super.key});
  @override
  State<InstructorAttendanceScreen> createState() => _InstructorAttendanceScreenState();
}

class _InstructorAttendanceScreenState extends State<InstructorAttendanceScreen>
    with UseApi<InstructorAttendanceScreen> {
  Object? _centerId;
  Object? _timeId;
  bool _poster = false;
  final Set<int> _picked = {};
  Map<int, MarkResult> _results = const {};
  bool _saving = false;

  late final _manual = useApi<bool>(ManualAttendance.isAvailable);

  late final _centers = useApi(RnApi.trainingCentres);
  late final _times = useApi<List<Map<String, dynamic>>>(
      () async => _centerId == null
          ? const <Map<String, dynamic>>[]
          : await RnApi.trainingTimeByTcId(RnApi.number(_centerId).toInt()),
      autoRun: false);
  // The roster is CENTRE-scoped — there is no roster-by-training-time endpoint.
  late final _roster = useApi<List<Map<String, dynamic>>>(
      () async => _centerId == null
          ? const <Map<String, dynamic>>[]
          : await RnApi.studentListByTcId(RnApi.number(_centerId).toInt()),
      autoRun: false);

  @override
  void initState() {
    super.initState();
    _centers;
    _times;
    _roster;
    _manual;
  }

  int? _studentId(Map<String, dynamic> row) => int.tryParse('${row['id'] ?? ''}');

  Future<void> _save(String centerName, String timeName) async {
    final ids = _picked.toList();
    if (ids.isEmpty || _centerId == null || _timeId == null || _saving) return;
    final ok = await confirmDialog(
      context,
      'Mark ${ids.length} present?',
      message: '$centerName · $timeName\nToday, ${fmtDateGB(DateTime.now().toIso8601String())}',
      confirmLabel: 'Mark present',
    );
    if (!ok || !mounted) return;
    final centreAtSave = _centerId;
    setState(() => _saving = true);
    try {
      final results = await ManualAttendance.markPresent(
        tCenterId: RnApi.number(_centerId).toInt(),
        tTimeId: RnApi.number(_timeId).toInt(),
        date: DateTime.now(),
        studentIds: ids,
      );
      if (!mounted) return;
      final marked = results.values.where((r) => r.ok).length;
      // The centre picker stays usable during a save; never paint results on another roster.
      if (_centerId == centreAtSave) {
        setState(() {
          _results = {..._results, ...results};
          _picked.removeWhere((id) => results[id]?.ok ?? false);
        });
      }
      await notify(
        context,
        marked == ids.length ? 'Attendance saved' : 'Some students were not marked',
        '$marked of ${ids.length} marked present.${marked == ids.length ? '' : ' Check the list for details.'}',
      );
    } catch (e) {
      if (mounted) await notify(context, "Couldn't save attendance", friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _centerCode => QrContent.trainingCenter(RnApi.number(_centerId).toInt());

  Future<void> _openPoster() async {
    final clubId = UserSession.instance.authData?['clubId'];
    if (clubId == null || _centerId == null) return;
    setState(() => _poster = true);
    final fname = 'CENTRE_QR_$_centerCode.pdf';
    try {
      final bytes = await ApiService.getPdfSmart(
          '/Utilities/TrainingCenterQRCode/${Uri.encodeComponent('$clubId')}/${Uri.encodeComponent('${RnApi.number(_centerId).toInt()}')}');
      if (kIsWeb) {
        downloadBytesWeb(bytes, fname, 'application/pdf');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fname');
      await file.writeAsBytes(bytes, flush: true);
      final res = await OpenFilex.open(file.path, type: 'application/pdf');
      if (res.type != ResultType.done) await Printing.sharePdf(bytes: bytes, filename: fname);
    } catch (e) {
      if (mounted) await notify(context, "Couldn't open the poster", friendlyError(e));
    } finally {
      if (mounted) setState(() => _poster = false);
    }
  }

  Future<void> _showQr(String centerName) async {
    if (_centerId == null) {
      await notify(context, 'Select a centre', 'Choose a training centre to show its check-in QR.');
      return;
    }
    await Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _CentreQrPage(
        centerName: centerName,
        code: _centerCode,
        content: _centerCode,
        onPoster: _openPoster,
        posterBusy: () => _poster,
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final roster = _roster.data ?? const <Map<String, dynamic>>[];
    final centerOptions = <RkOption>[
      for (final o in _centers.data ?? const <Map<String, dynamic>>[])
        (id: (o['id'] ?? '') as Object, text: '${o['text'] ?? ''}')
    ];
    final timeOptions = <RkOption>[
      for (final o in _times.data ?? const <Map<String, dynamic>>[])
        (id: (o['id'] ?? '') as Object, text: '${o['text'] ?? ''}')
    ];
    final centerName = centerOptions.where((o) => '${o.id}' == '$_centerId').firstOrNull?.text ?? '';
    final timeName = timeOptions.where((o) => '${o.id}' == '$_timeId').firstOrNull?.text ?? '';
    final firstError = _centers.error ?? _times.error ?? _roster.error;
    final hasCenter = _centerId != null;
    final canMark = _manual.data == true;
    final rosterIds = [for (final r in roster) _studentId(r)].whereType<int>().toSet();
    final allPicked = rosterIds.isNotEmpty && rosterIds.every(_picked.contains);

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ScreenHeader(
          title: 'Class Check-In',
          subtitle: hasCenter ? '${roster.length} student${roster.length == 1 ? '' : 's'} at this centre' : null,
        ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: () => Future.wait([_roster.reload(), _times.reload()]),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: 40 + bottom),
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.xl)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SelectField(
                      label: 'Training Centre',
                      placeholder: 'Select centre',
                      value: _centerId,
                      options: centerOptions,
                      loading: _centers.loading,
                      onChange: (id, _) {
                        setState(() {
                          _centerId = id;
                          _timeId = null;
                          // A failed fetch keeps old data; never show another centre's roster.
                          _times.data = null;
                          _roster.data = null;
                          _picked.clear();
                          _results = const {};
                        });
                        _times.reload();
                        _roster.reload();
                      },
                    ),
                    const SizedBox(height: 10),
                    SelectField(
                      label: 'Training Time',
                      placeholder: hasCenter ? 'Select time' : 'Select centre first',
                      value: _timeId,
                      options: timeOptions,
                      loading: _times.loading,
                      disabled: !hasCenter,
                      onChange: (id, _) => setState(() {
                        _timeId = id;
                        _results = const {};
                      }),
                    ),
                  ]),
                ),
                if (firstError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 0),
                    child: ErrorState(
                      message: firstError,
                      onRetry: () {
                        _centers.reload();
                        _times.reload();
                        _roster.reload();
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, 16, Gaps.xl, 0),
                  child: Touchable(
                    activeOpacity: 0.9,
                    onPress: () => _showQr(centerName),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: c.gradient),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: Shadows.strong(c),
                      ),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Ion.qrCode, size: 20, color: Colors.white),
                        SizedBox(width: 10),
                        Text('Show Centre QR',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      ]),
                    ),
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
                          canMark
                              ? 'Tick students who are present, choose the training time, then save. Students can still check in by scanning this QR.'
                              : "Students check in by scanning this QR with their own D-CLIX app. Marking students present from here needs a backend update and switches on automatically once it's live.",
                          style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 17 / 11.5)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, 24, Gaps.xl, 4),
                  child: Row(children: [
                    Expanded(
                      child: Text('Class List',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    ),
                    if (canMark && rosterIds.isNotEmpty && !_roster.loading)
                      Touchable(
                        onPress: () =>
                            setState(() => allPicked ? _picked.removeAll(rosterIds) : _picked.addAll(rosterIds)),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(allPicked ? 'Clear all' : 'Select all',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.primary)),
                        ),
                      ),
                    if (_roster.loading && hasCenter)
                      SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                    else if (hasCenter)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: c.primary.hexA('1A'), borderRadius: BorderRadius.circular(12)),
                        child: Text('${roster.length}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.primary)),
                      ),
                  ]),
                ),
                if (timeName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 10),
                    child: Text('$centerName · $timeName',
                        style: TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                if (roster.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: _roster.loading && hasCenter
                        ? Center(
                            child: SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(strokeWidth: 3, color: c.primary)))
                        : Column(children: [
                            Icon(Ion.peopleOutline, size: 44, color: c.textMuted),
                            const SizedBox(height: 10),
                            Text(
                                !hasCenter
                                    ? 'Select a training centre to load the class list.'
                                    : 'No students at this centre.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.textSecondary, fontSize: 14)),
                          ]),
                  ),
                for (final (i, item) in roster.indexed) _rosterRow(c, i, item, canMark),
              ],
            ),
          ),
        ),
        if (canMark && _picked.isNotEmpty)
          Container(
            padding: EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 12 + bottom),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.borderLight))),
            child: Touchable(
              activeOpacity: 0.9,
              onPress: _timeId == null || _saving ? null : () => _save(centerName, timeName),
              child: Opacity(
                opacity: _timeId == null ? 0.5 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: c.gradient), borderRadius: BorderRadius.circular(999)),
                  child: Center(
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_timeId == null ? 'Select a training time first' : 'Mark ${_picked.length} present',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _rosterRow(AppColors c, int i, Map<String, dynamic> item, bool canMark) {
    final id = _studentId(item);
    final picked = id != null && _picked.contains(id);
    final result = id == null ? null : _results[id];
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
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
          child: Icon(Ion.person, size: 18, color: c.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item['text'] ?? ''}'.isEmpty ? '—' : '${item['text']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
            if ('${item['value'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('${item['value']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.textSecondary)),
            ],
            if (result != null) ...[
              const SizedBox(height: 3),
              Text(result.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: result.ok ? c.success : c.danger)),
            ],
          ]),
        ),
        if (canMark && id != null) ...[
          const SizedBox(width: 10),
          Icon(
            result?.ok == true && !picked
                ? Ion.checkmarkDoneCircle
                : picked
                    ? Ion.checkmarkCircle
                    : Ion.ellipseOutline,
            size: 26,
            color: picked || result?.ok == true ? c.primary : c.textMuted,
            semanticLabel: picked ? 'Selected' : 'Not selected',
          ),
        ],
      ]),
    );
    if (!canMark || id == null) return row;
    return Touchable(
      activeOpacity: 0.8,
      onPress: _saving ? null : () => setState(() => picked ? _picked.remove(id) : _picked.add(id)),
      child: row,
    );
  }
}

/// Full-screen centre QR — held up for the class to scan.
class _CentreQrPage extends StatefulWidget {
  final String centerName;
  final String code;
  final String content;
  final Future<void> Function() onPoster;
  final bool Function() posterBusy;
  const _CentreQrPage({
    required this.centerName,
    required this.code,
    required this.content,
    required this.onPoster,
    required this.posterBusy,
  });

  @override
  State<_CentreQrPage> createState() => _CentreQrPageState();
}

class _CentreQrPageState extends State<_CentreQrPage> {
  Uint8List? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Api.utilitiesQRCodeBytes(width: 600, height: 600, content: widget.content).then((b) {
      if (mounted) setState(() => _bytes = b);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gaps.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.centerName.isEmpty ? 'Training Centre' : widget.centerName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.textPrimary)),
              const SizedBox(height: 6),
              Text('Scan with the D-CLIX app to check in', style: TextStyle(fontSize: 13, color: c.textSecondary)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(Radii.xl), boxShadow: Shadows.card(c)),
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: _bytes == null
                      ? Center(child: CircularProgressIndicator(color: c.primary))
                      : Image.memory(_bytes!, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
              const SizedBox(height: 20),
              Text(widget.code,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text("Can't scan? Students can type this code on their check-in screen.",
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textSecondary)),
              const SizedBox(height: 26),
              Touchable(
                onPress: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await widget.onPoster();
                        if (mounted) setState(() => _busy = false);
                      },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.primary.hexA('55'), width: 1.5),
                    color: c.primary.hexA('12'),
                  ),
                  child: _busy
                      ? Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Ion.printOutline, size: 16, color: c.primary),
                          const SizedBox(width: 8),
                          Text('Open printable poster',
                              style: TextStyle(color: c.primary, fontWeight: FontWeight.w800, fontSize: 13.5)),
                        ]),
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          top: 54,
          right: 20,
          child: RnCircleButton(icon: Ion.close, iconSize: 26, size: 44, onPress: () => Navigator.of(context).pop()),
        ),
      ]),
    );
  }
}
