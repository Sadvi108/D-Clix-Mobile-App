import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api.dart';
import '../services/attendance_outcome.dart';
import '../services/response_utils.dart';
import '../services/rn_api.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../utils/qr_content.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// QR payloads that are obviously NOT a club check-in code — rejected before hitting the
/// API. The backend (`/Attendance/Add` → status -1) is the real D-CLIX validator.
const _foreignPrefixes = ['WIFI:', 'BEGIN:VCARD', 'BEGIN:VEVENT', 'MATMSG:', 'MAILTO:', 'TEL:', 'SMSTO:', 'BTC:'];
bool _looksForeign(String v) {
  final t = v.trim().toUpperCase();
  return _foreignPrefixes.any(t.startsWith);
}

typedef _Result = ({bool ok, String title, String sub});

/// Port of `frontend/app/qr-scan.tsx` (Expo v2.11.1).
class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});
  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> with SingleTickerProviderStateMixin, UseApi<QRScanScreen> {
  late final _info = useApi(RnApi.myInfo);
  late final MobileScannerController _camera =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, facing: CameraFacing.back);
  late final AnimationController _laser =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  final _manual = TextEditingController();

  bool _busy = false;
  bool _cameraFailed = false;
  bool _lock = false;
  _Result? _result;

  /// Set when the server answers "Select your training class time".
  String? _classPickCode;
  List<Map<String, dynamic>> _slots = const [];

  @override
  void initState() {
    super.initState();
    _info;
    _manual.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _laser.dispose();
    _camera.dispose();
    _manual.dispose();
    super.dispose();
  }

  String _stampNow() {
    final d = DateTime.now();
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// One check-in attempt. `tTimeId` is only sent on the retry after the server asked which
  /// class this is for. attendanceType 1 = student self check-in.
  Future<void> _submit(String raw, {int? tTimeId}) async {
    final value = raw.trim();
    if (value.isEmpty || _busy || (_lock && tTimeId == null)) return;
    _lock = true;
    if (_looksForeign(value)) {
      setState(() => _result = (ok: false, title: 'Not a D-CLIX QR', sub: 'Scan the QR poster at your training center.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final resp = await Api.attendanceAdd({'qrCode': value, 'attendanceType': 1, 'tTimeId': tTimeId});
      final outcome = AttendanceOutcome.parse(resp);
      if (!mounted) return;
      if (outcome.success) {
        final center = '${_info.data?['tCenterName'] ?? ''}';
        setState(() {
          _classPickCode = null;
          _result = (
            ok: true,
            title: 'Check-in Successful!',
            sub: '${center.isEmpty ? 'Training Center' : center} · ${_stampNow()}'
          );
        });
        return;
      }
      // The centre QR was understood, but the server can't tell which session this is —
      // ask, then resend the same code with the chosen tTimeId.
      if (outcome.status == 1) {
        final centerId = QrContent.parse(value);
        setState(() {
          _classPickCode = value;
          _slots = outcome.sessions.map((s) => {'id': s.id, 'text': s.text}).toList();
          _result = null;
        });
        if (_slots.isEmpty && centerId != null && centerId.type == QrType.trainingCenter) {
          try {
            final rows = await RnApi.trainingTimeByTcId(centerId.id);
            if (mounted) setState(() => _slots = rows);
          } catch (_) {
            /* the picker falls back to a plain message */
          }
        }
        return;
      }
      final msg = outcome.message ?? '';
      setState(() => _result = (
            ok: false,
            title: 'Invalid QR Code',
            sub: msg.isNotEmpty && msg != 'Invalid QR Code'
                ? msg
                : "Scan the D-CLIX centre poster (its code looks like TC-00001945). Your own student QR won't check you in."
          ));
    } catch (e) {
      if (mounted) setState(() => _result = (ok: false, title: 'Check-in failed', sub: friendlyError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rescan() => setState(() {
        _lock = false;
        _result = null;
        _classPickCode = null;
        _slots = const [];
        _manual.clear();
      });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final result = _result;
    final picking = _classPickCode != null && result == null;
    final frameColor = result?.ok == false ? c.danger : c.primary;

    Widget gradientBtn(String label, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Touchable(
            activeOpacity: 0.9,
            onPress: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
              decoration: BoxDecoration(gradient: LinearGradient(colors: c.gradient), borderRadius: BorderRadius.circular(Radii.md)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 8)],
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
            ),
          ),
        );

    Widget corner(Alignment a) {
      final side = BorderSide(color: frameColor, width: 4);
      return Align(
        alignment: a,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border(
              top: a.y < 0 ? side : BorderSide.none,
              bottom: a.y > 0 ? side : BorderSide.none,
              left: a.x < 0 ? side : BorderSide.none,
              right: a.x > 0 ? side : BorderSide.none,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(a.x < 0 && a.y < 0 ? 12 : 0),
              topRight: Radius.circular(a.x > 0 && a.y < 0 ? 12 : 0),
              bottomLeft: Radius.circular(a.x < 0 && a.y > 0 ? 12 : 0),
              bottomRight: Radius.circular(a.x > 0 && a.y > 0 ? 12 : 0),
            ),
          ),
        ),
      );
    }

    final instruction = result != null
        ? result.title
        : picking
            ? 'Select your training class time'
            : _busy
                ? 'Checking in…'
                : 'Align the QR within the frame';
    final hint = result != null
        ? (result.ok ? 'Attendance marked for today' : 'Make sure you scan the D-CLIX center QR')
        : picking
            ? 'Your academy needs to know which class this check-in is for'
            : 'Make sure the camera has good lighting';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // Live camera; dark gradient when it can't start (no permission / no camera).
        if (!_cameraFailed)
          MobileScanner(
            controller: _camera,
            onDetect: (capture) {
              if (_busy || _result != null || _lock) return;
              final code = capture.barcodes.map((b) => b.rawValue ?? '').firstWhere((v) => v.isNotEmpty, orElse: () => '');
              if (code.isNotEmpty) _submit(code);
            },
            errorBuilder: (_, __) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_cameraFailed) setState(() => _cameraFailed = true);
              });
              return const SizedBox.shrink();
            },
          ),
        if (_cameraFailed)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF000000), Color(0xFF0A0A0B), Color(0xFF1F1610)]),
            ),
          ),
        // Scrim for overlay contrast over the camera feed
        const IgnorePointer(child: ColoredBox(color: Color(0x59000000))),
        Column(children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: EdgeInsets.fromLTRB(Gaps.xl, top + 8 > 56 ? top + 8 : 56, Gaps.xl, 14),
                color: const Color(0x33000000),
                child: Row(children: [
                  Touchable(
                    onPress: () => safeBack(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(color: Color(0x1FFFFFFF), shape: BoxShape.circle),
                      child: const Icon(Ion.close, size: 22, color: Colors.white),
                    ),
                  ),
                  const Expanded(
                    child: Text('Scan to Check-in',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 42),
                ]),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - top - 200),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Text(instruction,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                  if (picking)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340, minHeight: 120),
                      child: _busy
                          ? Center(child: CircularProgressIndicator(color: c.primary))
                          : _slots.isEmpty
                              ? const Text(
                                  'No class times are listed for this centre. Ask your academy to add the training time, then scan again.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xBFFFFFFF), fontSize: 13, height: 19 / 13))
                              : Column(children: [
                                  for (final s in _slots)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Touchable(
                                        activeOpacity: 0.8,
                                        onPress: () => _submit(_classPickCode!, tTimeId: (s['id'] as num?)?.toInt()),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                          decoration: BoxDecoration(
                                              color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(Radii.md)),
                                          child: Row(children: [
                                            Icon(Ion.timeOutline, size: 18, color: c.primary),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text('${s['text'] ?? s['value'] ?? ''}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                                            ),
                                            const Icon(Ion.chevronForward, size: 18, color: Color(0x99FFFFFF)),
                                          ]),
                                        ),
                                      ),
                                    ),
                                ]),
                    )
                  else
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: Stack(children: [
                        corner(Alignment.topLeft),
                        corner(Alignment.topRight),
                        corner(Alignment.bottomLeft),
                        corner(Alignment.bottomRight),
                        if (result == null && !_busy)
                          AnimatedBuilder(
                            animation: _laser,
                            builder: (_, __) => Positioned(
                              top: 10 + _laser.value * 220,
                              left: 10,
                              right: 10,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [c.primary.withAlpha(0), c.primary, c.primary.withAlpha(0)]),
                                ),
                              ),
                            ),
                          ),
                        if (_busy) Center(child: CircularProgressIndicator(color: c.primary)),
                        if (result != null)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(result.ok ? Ion.checkmarkCircle : Ion.closeCircle,
                                    size: 70, color: result.ok ? c.success : c.danger),
                                const SizedBox(height: 12),
                                Text(result.title,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(result.sub,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 12)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: Text(hint,
                        textAlign: TextAlign.center, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12)),
                  ),
                  if (picking && !_busy) gradientBtn('Scan Again', _rescan),
                  // No camera → manual code entry so check-in is still possible
                  if (_cameraFailed && result == null && !picking)
                    Container(
                      margin: const EdgeInsets.only(top: 28),
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('Camera unavailable — enter the centre code shown at reception.',
                              textAlign: TextAlign.center, style: TextStyle(color: Color(0xA6FFFFFF), fontSize: 12)),
                        ),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _manual,
                              enabled: !_busy,
                              autocorrect: false,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              cursorColor: c.primary,
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0x1FFFFFFF),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                hintText: 'Centre code, e.g. TC-00001945',
                                hintStyle: const TextStyle(color: Color(0x73FFFFFF)),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Opacity(
                            opacity: _busy || _manual.text.trim().isEmpty ? 0.5 : 1,
                            child: Touchable(
                              onPress: _busy || _manual.text.trim().isEmpty ? null : () => _submit(_manual.text),
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: c.gradient),
                                    borderRadius: BorderRadius.circular(Radii.md)),
                                child: const Icon(Ion.arrowForward, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  if (result != null) gradientBtn(result.ok ? 'Done' : 'Scan Again', result.ok ? () => safeBack(context) : _rescan),
                ]),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: bottom + 20 > 40 ? bottom + 20 : 40),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Ion.shieldCheckmark, size: 14, color: Color(0x99FFFFFF)),
              SizedBox(width: 6),
              Text('Secure · Verified at the academy',
                  style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ]),
    );
  }
}
