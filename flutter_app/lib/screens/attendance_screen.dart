import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// `toLocaleDateString("en-GB", {weekday: "short", day: "2-digit", month: "short", year: "numeric"})`.
String _fmtDate(dynamic iso) {
  final s = '${iso ?? ''}';
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[d.weekday - 1]}, ${fmtDateGB(s)}';
}

/// Presence is decided by the attendanceType STRING only.
bool _isPresent(dynamic t) => RegExp('present', caseSensitive: false).hasMatch('${t ?? ''}');

/// Port of `frontend/app/attendance.tsx` (Expo v2.11.1).
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with UseApi<AttendanceScreen> {
  final _range = RnApi.defaultRange();
  late final _att = useApi(() => RnApi.attendanceReport({
        'sourceKeyId': UserSession.instance.currentStudentId,
        'fromDate': _range.fromDate,
        'toDate': _range.toDate,
      }));

  @override
  void initState() {
    super.initState();
    _att;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final records = session.scopedRows(_att.data).whereType<Map>().toList();
    final total = records.length;
    final present = records.where((r) => _isPresent(r['attendanceType'])).length;
    final missed = total - present;
    final percentage = total > 0 ? (present / total * 100).round() : 0;
    final absent = records.where((r) => !_isPresent(r['attendanceType'])).toList();

    Widget miniStat(String n, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(Radii.sm)),
            child: Column(children: [
              Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(l, style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 9)),
            ]),
          ),
        );

    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
        );

    String center(Map r) {
      final t = '${r['trainingCenter'] ?? ''}';
      final s = '${r['sCenterName'] ?? ''}';
      return t.isNotEmpty ? t : (s.isNotEmpty ? s : 'Class');
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RnHeader(
          title: 'Attendance',
          trailing: RnCircleButton(
            icon: Ion.qrCodeOutline,
            iconSize: 20,
            iconColor: c.primary,
            onPress: () => context.push('/qr-scan'),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 120),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(Radii.xxl),
                  boxShadow: Shadows.strong(c),
                ),
                child: Row(children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CustomPaint(
                      painter: _RingPainter(),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('$percentage%',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                          const Text('Attended',
                              style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 9, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(percentage >= 80 ? 'Great Discipline!' : 'Keep Going!',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('Keep it above 80% to qualify for events',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 11)),
                      const SizedBox(height: 12),
                      Row(children: [
                        miniStat('$present', 'Present'),
                        const SizedBox(width: 8),
                        miniStat('$missed', 'Absent'),
                        const SizedBox(width: 8),
                        miniStat('$total', 'Total'),
                      ]),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Touchable(
                onPress: () => context.push('/qr-scan'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: c.gradient),
                    borderRadius: BorderRadius.circular(Radii.xl),
                    boxShadow: Shadows.strong(c),
                  ),
                  child: const Row(children: [
                    Icon(Ion.qrCode, size: 22, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Scan QR to Check In',
                            maxLines: 1,
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text("Mark attendance for today's class",
                            maxLines: 1,
                            style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 11)),
                      ]),
                    ),
                    Icon(Ion.arrowForward, size: 18, color: Colors.white),
                  ]),
                ),
              ),
              section('Recent Attendance'),
              if (_att.loading) const RnSpinner(vertical: 20),
              if (_att.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_att.error!, style: TextStyle(color: c.danger, fontSize: 13)),
                ),
              if (!_att.loading && total == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('No attendance records found.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                ),
              for (final r in records.take(60))
                Builder(builder: (context) {
                  final ok = _isPresent(r['attendanceType']);
                  final tone = ok ? c.success : c.danger;
                  final type = '${r['attendanceType'] ?? ''}';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(13),
                    decoration: rnCard(c, radius: Radii.md),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: tone.hexA(c.isDark ? '33' : '1A')),
                        child: Icon(ok ? Ion.checkmarkCircle : Ion.closeCircle, size: 20, color: tone),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(center(r),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          const SizedBox(height: 2),
                          Text(_fmtDate(r['recordedTime']),
                              maxLines: 1, style: TextStyle(fontSize: 11, color: c.textSecondary)),
                        ]),
                      ),
                      const SizedBox(width: Gaps.sm),
                      Text(type.isNotEmpty ? type : (ok ? 'Present' : 'Absent'),
                          maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone)),
                    ]),
                  );
                }),
              if (absent.isNotEmpty) ...[
                section('Missed Class History'),
                for (final m in absent.take(20))
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: rnCard(c, radius: Radii.md),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: c.isDark ? const Color(0xFF3F1212) : const Color(0xFFFEE2E2)),
                        child: Icon(Ion.closeCircle, size: 20, color: c.danger),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(center(m),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          const SizedBox(height: 2),
                          Text('${_fmtDate(m['recordedTime'])} · ${m['attendanceType'] ?? ''}',
                              maxLines: 1, style: TextStyle(fontSize: 11, color: c.textSecondary)),
                        ]),
                      ),
                    ]),
                  ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/// The RN hero ring: a 6px translucent outer ring, and an inner ring whose top half is bright
/// and bottom half dim (a border-coloured circle rotated -45°).
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0x38FFFFFF);
    canvas.drawCircle(center, 60 - 3, outer);
    final rect = Rect.fromCircle(center: center, radius: 50 - 3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawArc(rect, math.pi, math.pi, false, paint..color = const Color(0xFFFFF7ED));
    canvas.drawArc(rect, 0, math.pi, false, paint..color = const Color(0x66FFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
