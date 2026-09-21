import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../services/user_session.dart';
import '../theme/app_theme.dart';

// Launch intro. A karate figure bows, punches and throws a roundhouse kick; its own lines
// then morph into the D/CLIX wordmark while the orange kick trail becomes the slash. The
// slash sends out a ring that bursts into the badge, ripples run while the session
// restores, and the badge and word glide into the Login header (or the stage zooms away
// into Home when a saved session was restored).
//
// Everything is drawn in a 100x100 "stage" square, the same units as the approved HTML
// preview, so poses and timings carry over one to one.

// Timeline, in milliseconds from the first frame.
const double kIntroMorphAt = 1480; // the figure's lines start turning into the word
const double kIntroWordAt = 2020; // the word has landed
const double kIntroRevealAt = 2380; // the badge bursts open above the word
const double kIntroExitMin = 2980; // earliest moment the splash may leave
const double kIntroStillAt = 3300; // a settled frame: shown as-is when Reduce Motion is on
const double kIntroGlideMs = 600; // logged out: badge and word glide into the Login header
const double kIntroZoomMs = 450; // logged in: the stage zooms away into Home

const double _rigScale = 1.3; // the figure is drawn 1.3x its rig, about (50, 60)
const double _wordScale = 1.25; // glyphs are designed at 22 units tall, drawn 1.25x
const double _wordSlide = 66; // the word moves down this far to make room for the badge
const double _ringR = 39.5; // the badge's own orange ring
const double _badgeD = 96 / 1.24; // badge diameter
const int _m = 60; // points per morphing stroke

// ---------------------------------------------------------------------------------------
// The figure. Pose = [hipX, hipY, torso, frontUpperArm, frontForearm, backUpperArm,
// backForearm, frontThigh, frontShin, backThigh, backShin]. Angles in degrees, 0 = right,
// 90 = down; the figure faces right.
const _stand = <double>[48, 60, -88, 94, 92, 98, 96, 87, 89, 93, 91];
const _bow = <double>[48, 60, -58, 100, 100, 104, 104, 86, 88, 94, 92];
const _ready = <double>[48, 62, -84, 50, -55, 120, 10, 50, 88, 128, 112];
const _punch = <double>[53, 66, -82, -8, -4, 118, -5, 35, 85, 125, 135];
const _chamber = <double>[46, 61, -100, 35, -65, 150, 110, -15, 75, 100, 90];
const _kick = <double>[44, 60, -115, 30, -70, 160, 120, -40, -50, 100, 88];

class _Key {
  const _Key(this.ms, this.pose, this.belt, [this.curve = Curves.easeInOutCubic]);
  final double ms;
  final List<double> pose;
  final int belt; // index into the belt palette
  final Curve curve; // easing into this key
}

// The belt ranks up with each move: yellow, orange, green, blue, brown.
const _keys = <_Key>[
  _Key(0, _stand, 0),
  _Key(260, _bow, 0),
  _Key(420, _bow, 0),
  _Key(640, _ready, 1),
  _Key(780, _punch, 2, Curves.easeOutCubic),
  _Key(880, _punch, 2),
  _Key(1040, _ready, 2),
  _Key(1200, _chamber, 3),
  _Key(1360, _kick, 4, Curves.easeOutCubic),
  _Key(1480, _kick, 4),
];
const _beltsLight = [Color(0xFFCA8A04), Color(0xFFEA580C), Color(0xFF16A34A), Color(0xFF2563EB), Color(0xFF92400E)];
const _beltsDark = [Color(0xFFFACC15), Color(0xFFFB923C), Color(0xFF4ADE80), Color(0xFF60A5FA), Color(0xFFC08457)];

class _Pose {
  _Pose(this.v, this._from, this._to, this._e);
  final List<double> v;
  final int _from, _to;
  final double _e;
  Color belt(List<Color> palette) => Color.lerp(palette[_from], palette[_to], _e)!;
}

_Pose _poseAt(double t) {
  var i = 0;
  while (i < _keys.length - 1 && t >= _keys[i + 1].ms) {
    i++;
  }
  final a = _keys[i], b = _keys[math.min(i + 1, _keys.length - 1)];
  final e = identical(a, b) ? 0.0 : b.curve.transform(((t - a.ms) / (b.ms - a.ms)).clamp(0.0, 1.0));
  return _Pose([for (var k = 0; k < a.pose.length; k++) a.pose[k] + (b.pose[k] - a.pose[k]) * e], a.belt, b.belt, e);
}

Offset _dir(Offset p, double deg, double r) {
  final a = deg * math.pi / 180;
  return p + Offset(math.cos(a) * r, math.sin(a) * r);
}

typedef _Joints = ({
  Offset hip, Offset sh, Offset neck, Offset head, Offset eA, Offset hA, //
  Offset eB, Offset hB, Offset kF, Offset fF, Offset kB, Offset fB,
});

_Joints _joints(List<double> v) {
  final hip = Offset(v[0], v[1]), sh = _dir(hip, v[2], 18), neck = _dir(hip, v[2], 21);
  final eA = _dir(sh, v[3], 12), eB = _dir(sh, v[5], 12), kF = _dir(hip, v[7], 17), kB = _dir(hip, v[9], 17);
  return (
    hip: hip, sh: sh, neck: neck, head: _dir(neck, v[2], 2.5 + 6.2), eA: eA, hA: _dir(eA, v[4], 12), //
    eB: eB, hB: _dir(eB, v[6], 12), kF: kF, fF: _dir(kF, v[8], 17), kB: kB, fB: _dir(kB, v[10], 17),
  );
}

/// Rig coordinates to stage coordinates.
Offset _rig(Offset p) => Offset(50 + (p.dx - 50) * _rigScale, 60 + (p.dy - 60) * _rigScale);

/// Where the kicking foot travels: drawn as the orange trail, then becomes the slash.
final List<Offset> _kickTrail = [
  for (var i = 0; i <= 120; i++) _rig(_joints(_poseAt(1040 + 320 * i / 120).v).fF),
];
final Offset _punchHand = _joints(_poseAt(780).v).hA;
final Offset _kickFoot = _joints(_poseAt(1360).v).fF;

// ---------------------------------------------------------------------------------------
// The word. Each monoline glyph stroke is fed by one line of the figure at the kick.

enum StrokeInk { ink, slash, belt }

class MorphStroke {
  MorphStroke(this.from, this.to, this.delay, this.w0, this.w1, this.ink);
  final List<Offset> from, to;
  final double delay, w0, w1;
  final StrokeInk ink;
  List<Offset> at(double e) => [for (var i = 0; i < to.length; i++) Offset.lerp(from[i], to[i], e)!];
}

Offset _w(Offset p) => Offset(50 + (p.dx - 50) * _wordScale, 52 + (p.dy - 52) * _wordScale);

Path _polyline(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final q in pts.skip(1)) {
    p.lineTo(q.dx, q.dy);
  }
  return p;
}

List<Offset> _sample(Path p, int n) {
  final m = p.computeMetrics().single;
  return [for (var i = 0; i < n; i++) m.getTangentForOffset(m.length * i / (n - 1))!.position];
}

List<Offset> _resample(List<Offset> pts, int n) => _sample(_polyline(pts), n);

double _gap(List<Offset> a, List<Offset> b) {
  var d = 0.0;
  for (var i = 0; i < a.length; i++) {
    d += (a[i] - b[i]).distance;
  }
  return d;
}

/// The eight strokes of D/CLIX, each with the figure line it grows out of.
final List<MorphStroke> wordStrokes = () {
  final pose = _poseAt(kIntroMorphAt), v = pose.v, j = _joints(v);
  final bc = _dir(j.hip, v[2], 3);
  const limb = 6.5 * _rigScale, glyph = 5.5 * _wordScale;
  MorphStroke s(List<Offset> from, Path shape, double delay, double w0, [StrokeInk ink = StrokeInk.ink]) {
    final to = _sample(shape, _m).map(_w).toList();
    var src = _resample(from, _m);
    final flipped = src.reversed.toList();
    if (_gap(flipped, to) < _gap(src, to)) src = flipped;
    return MorphStroke(src, to, delay, w0, glyph, ink);
  }

  List<Offset> rig(List<Offset> pts) => pts.map(_rig).toList();
  final head = [for (var i = 0; i < _m; i++) _rig(_dir(j.head, -45 - 360 * i / (_m - 1), 6.2 / 2))];
  final dBowl = Path()
    ..moveTo(-2, 41)
    ..lineTo(4, 41)
    ..arcToPoint(const Offset(4, 63), radius: const Radius.circular(11))
    ..lineTo(-2, 63);
  final c = Path()
    ..moveTo(50.8, 44.2)
    ..arcToPoint(const Offset(50.8, 59.8), radius: const Radius.circular(11), largeArc: true, clockwise: false);
  return [
    s(rig([j.sh, j.eB, j.hB]), _polyline(const [Offset(-2, 41), Offset(-2, 63)]), 0, limb), // back arm -> D stem
    s(rig([j.hip, j.neck]), dBowl, 0, limb), // torso -> D bowl
    s(_kickTrail, _polyline(const [Offset(22, 58), Offset(28, 46)]), 40, 3, StrokeInk.slash), // trail -> slash
    s(head, c, 80, 6.2 * _rigScale), // head -> C
    s(rig([j.hip, j.kB, j.fB]), _polyline(const [Offset(58, 41), Offset(58, 63), Offset(70, 63)]), 110, limb), // leg -> L
    s(rig([_dir(bc, v[2] - 90, 5.5), _dir(bc, v[2] + 90, 5.5)]), _polyline(const [Offset(78, 41), Offset(78, 63)]), 130,
        3 * _rigScale, StrokeInk.belt), // belt -> I
    s(rig([j.sh, j.eA, j.hA]), _polyline(const [Offset(85, 41), Offset(101, 63)]), 160, limb), // punching arm -> X
    s(rig([j.hip, j.kF, j.fF]), _polyline(const [Offset(101, 41), Offset(85, 63)]), 160, limb), // kicking leg -> X
  ];
}();

/// The finished word in stage units, after it has moved down under the badge.
final Rect _wordRest = () {
  final pts = [for (final s in wordStrokes) ...s.to];
  final box = pts.skip(1).fold(Rect.fromPoints(pts.first, pts.first), (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
  return box.inflate(5.5 * _wordScale / 2).translate(0, _wordSlide);
}();
final Offset _slashAt = _w(const Offset(25, 52));

// ---------------------------------------------------------------------------------------
// Where the Login header draws its logo and "D-CLIX" (see LoginScreen's top row: page
// padding Gaps.xl, 4 above the row, a 38pt logo, a 10pt gap, then the word).

Rect loginLogoRect(EdgeInsets safe) => Rect.fromLTWH(Gaps.xl, safe.top + Gaps.xl + 4, 38, 38);

Rect loginWordRect(EdgeInsets safe, TextStyle base) {
  final tp = TextPainter(
    text: TextSpan(text: 'D-CLIX', style: base.merge(const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 14))),
    textDirection: TextDirection.ltr,
  )..layout();
  return Rect.fromLTWH(Gaps.xl + 38 + 10, safe.top + Gaps.xl + 4 + (38 - tp.height) / 2, tp.width, tp.height);
}

// ---------------------------------------------------------------------------------------

class IntroClock extends ChangeNotifier {
  double t = 0;
  double? exitAt;
  bool toLogin = true;

  void tick(double ms) {
    t = ms;
    notifyListeners();
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final _clock = IntroClock();
  late final Ticker _ticker = createTicker(_tick);
  ImageStream? _logoStream;
  late final _logoListener = ImageStreamListener((info, _) {
    if (!mounted) return info.dispose();
    setState(() {
      _logo?.dispose();
      _logo = info.image;
    });
  });
  ui.Image? _logo;
  bool? _restored; // null until the saved session has been checked
  bool _left = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _logoStream ??= const AssetImage(kLogoAssetPath).resolve(createLocalImageConfiguration(context))
      ..addListener(_logoListener);
  }

  Future<void> _bootstrap() async {
    var restored = false;
    try {
      restored = await UserSession.instance.restoreSession();
    } catch (_) {
      restored = false;
    }
    if (mounted) _restored = restored;
  }

  void _tick(Duration elapsed) {
    final t = (_reduceMotion ? kIntroStillAt : 0) + elapsed.inMicroseconds / 1000;
    if (_clock.exitAt == null && _restored != null && t >= kIntroExitMin) {
      if (_reduceMotion) return _leave();
      _clock
        ..exitAt = t
        ..toLogin = !_restored!;
    }
    final exit = _clock.exitAt;
    if (exit != null && t >= exit + (_clock.toLogin ? kIntroGlideMs : kIntroZoomMs)) return _leave();
    _clock.tick(t);
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    _ticker.stop();
    context.go(_restored! ? (UserSession.instance.isInstructor ? '/instructor/home' : '/home') : '/login');
  }

  @override
  void dispose() {
    _ticker.dispose();
    _logoStream?.removeListener(_logoListener);
    _logo?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors, safe = MediaQuery.paddingOf(context);
    final text = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return Scaffold(
      backgroundColor: c.background,
      body: Semantics(
        label: 'D-Clix',
        image: true,
        child: SizedBox.expand(
          child: CustomPaint(
            painter: IntroPainter(
              clock: _clock,
              colors: c,
              logo: _logo,
              logoTarget: loginLogoRect(safe),
              wordTarget: loginWordRect(safe, text),
              text: text,
              bottomInset: safe.bottom,
              reduceMotion: _reduceMotion,
            ),
          ),
        ),
      ),
    );
  }
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

double _lerp(double a, double b, double e) => a + (b - a) * e;
double _clamp01(double x) => x.clamp(0.0, 1.0);
const _emphasized = Cubic(.2, 0, 0, 1);

class IntroPainter extends CustomPainter {
  IntroPainter({
    required this.clock,
    required this.colors,
    required this.logo,
    required this.logoTarget,
    required this.wordTarget,
    required this.text,
    this.bottomInset = 0,
    this.reduceMotion = false,
  }) : super(repaint: clock);

  final IntroClock clock;
  final AppColors colors;
  final ui.Image? logo;
  final Rect logoTarget, wordTarget;
  final TextStyle text;
  final double bottomInset;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.t, c = colors;
    final u = math.min(size.width, 440) * 1.24 / 218;
    final origin = Offset(size.width / 2 - 50 * u, size.height * .45 - 50 * u);
    Offset px(Offset p) => origin + p * u;
    final exitAt = clock.exitAt;
    final since = exitAt == null ? 0.0 : t - exitAt;
    final gliding = exitAt != null && clock.toLogin, zooming = exitAt != null && !clock.toLogin;
    final exitFade = exitAt == null ? 1.0 : 1 - _clamp01(since / 150);

    final full = Offset.zero & size;
    canvas.drawRect(
      full,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: c.isDark
              ? const [Color(0xFF000000), Color(0xFF0A0A0B), Color(0xFF1F1F23)]
              : const [Color(0xFFFFFFFF), Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
        ).createShader(full),
    );
    final glow = Rect.fromCircle(center: px(const Offset(50, 50)), radius: 150 / 1.24 * u);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: [c.primary.withValues(alpha: c.isDark ? .2 : .14), c.primary.withValues(alpha: 0)],
          stops: const [0, .65],
        ).createShader(glow),
    );

    canvas.save();
    if (zooming) {
      final e = const Cubic(.5, 0, .75, 0).transform(_clamp01(since / kIntroZoomMs));
      final mid = px(const Offset(50, 50));
      canvas
        ..translate(mid.dx, mid.dy)
        ..scale(1 + .9 * e)
        ..translate(-mid.dx, -mid.dy)
        ..saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - e));
    }

    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(u);
    _bloom(canvas, t, exitFade);
    if (!reduceMotion) _ripples(canvas, t, exitFade);
    canvas.restore();

    _badge(canvas, t, px, u, gliding ? _emphasized.transform(_clamp01(since / 560)) : 0);

    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(u);
    if (t < kIntroMorphAt) _figure(canvas, t);
    _ring(canvas, t);
    canvas.restore();

    _word(canvas, t, px, u, gliding ? _emphasized.transform(_clamp01((since - 40) / 560)) : 0, exitFade);

    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(u);
    _sparks(canvas, t);
    canvas.restore();

    _foot(canvas, size, t, exitFade);
    if (zooming) canvas.restore();
    canvas.restore();
  }

  void _bloom(Canvas canvas, double t, double fade) {
    if (t < kIntroRevealAt) return;
    final p = _clamp01((t - kIntroRevealAt) / 900);
    double op, s;
    if (p < .4) {
      final q = Curves.easeOut.transform(p / .4);
      op = q;
      s = _lerp(.5, 1.12, q);
    } else {
      final q = Curves.easeOut.transform((p - .4) / .6);
      op = _lerp(1, .35, q);
      s = _lerp(1.12, 1, q);
    }
    final r = Rect.fromCircle(center: const Offset(50, 50), radius: 85 / 1.24 * s);
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [colors.primary.withValues(alpha: (colors.isDark ? .45 : .35) * op * fade), colors.primary.withValues(alpha: 0)],
          stops: const [0, .65],
        ).createShader(r),
    );
  }

  void _ripples(Canvas canvas, double t, double fade) {
    for (final delay in const [600.0, 1300, 2000]) {
      final start = kIntroRevealAt + delay;
      if (t < start) continue;
      final e = const Cubic(.2, .6, .35, 1).transform(((t - start) % 2100) / 2100);
      canvas.drawCircle(const Offset(50, 50), _badgeD / 2 * (1 + e),
          _stroke(colors.primary.withValues(alpha: .6 * (1 - e) * fade), 2 / 1.24 * (1 + e)));
    }
  }

  void _badge(Canvas canvas, double t, Offset Function(Offset) px, double u, double glide) {
    final img = logo;
    if (img == null || t < kIntroRevealAt) return;
    final p = _clamp01((t - kIntroRevealAt) / 550);
    const curve = Cubic(.2, .8, .2, 1);
    double clip, scale;
    if (p < .6) {
      final q = curve.transform(p / .6);
      clip = q;
      scale = _lerp(.92, 1.05, q);
    } else {
      clip = 1;
      scale = _lerp(1.05, 1, curve.transform((p - .6) / .4));
    }
    if (!reduceMotion && t > kIntroRevealAt + 900) {
      final b = math.sin(math.pi * (t - kIntroRevealAt - 900) / 2100);
      scale *= 1 + .035 * b * b;
    }
    var rect = Rect.fromCircle(center: px(const Offset(50, 50)), radius: _badgeD * u / 2 * scale);
    if (glide > 0) rect = Rect.lerp(rect, logoTarget, glide)!;
    canvas.drawCircle(
      rect.center + Offset(0, rect.height * .06),
      rect.width / 2 * .92,
      Paint()
        ..color = Colors.black.withValues(alpha: .3 * clip * (1 - glide))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rect.width * .08),
    );
    canvas
      ..save()
      ..clipPath(Path()..addOval(Rect.fromCircle(center: rect.center, radius: rect.width / 2 * clip)));
    paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
    canvas.restore();
  }

  void _figure(Canvas canvas, double t) {
    final a = Curves.easeOutCubic.transform(_clamp01(t / 220));
    final pose = _poseAt(t), v = pose.v, j = _joints(v);
    final ink = colors.textPrimary.withValues(alpha: a);
    final s = .9 + .1 * a;
    canvas
      ..save()
      ..translate(50, 60)
      ..scale(_rigScale)
      ..translate(-50, -60)
      ..translate(50, 50)
      ..scale(s)
      ..translate(-50, -50);
    final limbs = Path()
      ..addPath(_polyline([j.sh, j.eB, j.hB]), Offset.zero)
      ..addPath(_polyline([j.hip, j.kB, j.fB]), Offset.zero)
      ..addPath(_polyline([j.hip, j.neck]), Offset.zero)
      ..addPath(_polyline([j.hip, j.kF, j.fF]), Offset.zero)
      ..addPath(_polyline([j.sh, j.eA, j.hA]), Offset.zero);
    canvas
      ..drawPath(limbs, _stroke(ink, 6.5))
      ..drawCircle(j.head, 6.2, Paint()..color = ink);
    final bc = _dir(j.hip, v[2], 3), knot = _dir(bc, v[2] + 90, 3.8);
    final belt = pose.belt(colors.isDark ? _beltsDark : _beltsLight).withValues(alpha: a);
    canvas
      ..drawLine(_dir(bc, v[2] - 90, 5.5), _dir(bc, v[2] + 90, 5.5), _stroke(belt, 3))
      ..drawLine(knot, _dir(knot, 70, 7), _stroke(belt, 2.2))
      ..drawLine(knot, _dir(knot, 98, 6.5), _stroke(belt, 2.2));
    _hit(canvas, t, 780, _punchHand, 0);
    _hit(canvas, t, 1360, _kickFoot, -45);
    canvas.restore();
  }

  /// Three short impact marks that burst out from a punch or kick.
  void _hit(Canvas canvas, double t, double at, Offset p, double aim) {
    if (t < at || t >= at + 180) return;
    final pr = (t - at) / 180, q = Curves.easeOutCubic.transform(pr);
    final paint = _stroke(colors.primary.withValues(alpha: 1 - pr), 2.4);
    for (final d in const [-35.0, 0, 35]) {
      canvas.drawLine(_dir(p, aim + d, 4 + 6 * q), _dir(p, aim + d, 6 + 11 * q), paint);
    }
  }

  void _ring(Canvas canvas, double t) {
    if (t >= 1040 && t < kIntroMorphAt) {
      final n = math.max(2, (120 * _clamp01((t - 1040) / 320)).round() + 1);
      canvas.drawPath(_polyline(_kickTrail.sublist(0, n)), _stroke(colors.primary, 3));
    } else if (t >= kIntroWordAt) {
      final e = Curves.easeOutCubic.transform(_clamp01((t - kIntroWordAt) / (kIntroRevealAt - kIntroWordAt)));
      final fade = 1 - _clamp01((t - kIntroRevealAt - 250) / 200);
      if (fade <= 0) return;
      canvas.drawCircle(Offset.lerp(_slashAt, const Offset(50, 50), e)!, _lerp(3, _ringR, e),
          _stroke(colors.primary.withValues(alpha: fade), 3 - .4 * _clamp01((t - kIntroWordAt) / 360)));
    }
  }

  void _word(Canvas canvas, double t, Offset Function(Offset) px, double u, double glide, double fade) {
    if (t < kIntroMorphAt) return;
    final slide = _wordSlide * Curves.easeInOutCubic.transform(_clamp01((t - kIntroWordAt) / 360));
    final bounce = 1 + .05 * math.sin(math.pi * _clamp01((t - kIntroWordAt) / 220));
    canvas.save();
    if (glide > 0) {
      final rest = Rect.fromPoints(px(_wordRest.topLeft), px(_wordRest.bottomRight));
      final mid = Offset.lerp(rest.center, wordTarget.center, glide)!;
      canvas
        ..translate(mid.dx, mid.dy)
        ..scale(_lerp(1, wordTarget.width / rest.width, glide))
        ..translate(-rest.center.dx, -rest.center.dy);
    }
    final o = px(Offset.zero);
    canvas
      ..translate(o.dx, o.dy)
      ..scale(u)
      ..translate(0, slide)
      ..translate(50, 52)
      ..scale(bounce)
      ..translate(-50, -52);
    for (final s in wordStrokes) {
      final e = Curves.easeInOutCubic.transform(_clamp01((t - kIntroMorphAt - s.delay) / 380));
      final color = switch (s.ink) {
        StrokeInk.slash => colors.primary,
        StrokeInk.belt => Color.lerp(colors.isDark ? _beltsDark[4] : _beltsLight[4], colors.textPrimary, e)!,
        StrokeInk.ink => colors.textPrimary,
      };
      canvas.drawPath(_polyline(s.at(e)), _stroke(color, _lerp(s.w0, s.w1, e)));
    }
    final a = _clamp01((t - kIntroWordAt - 60) / 300) * fade;
    if (a > 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'SPORTS TECHNOLOGY PLATFORM',
          style: text.copyWith(
              fontSize: 4.6, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: colors.primary.withValues(alpha: a)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(50 - tp.width / 2, 52 + 11 * _wordScale + 9 - tp.height * .8));
    }
    canvas.restore();
  }

  void _sparks(Canvas canvas, double t) {
    if (t < kIntroRevealAt) return;
    final tint = [colors.primary, const Color(0xFFFACC15), const Color(0xFFFDBA74)];
    for (var i = 0; i < 14; i++) {
      final p = (t - kIntroRevealAt - (i % 4) * 15) / 650;
      if (p <= 0 || p >= 1) continue;
      final e = const Cubic(.1, .7, .3, 1).transform(p);
      final angle = (i * 360 / 14 + (i % 3) * 7).roundToDouble() * math.pi / 180;
      canvas
        ..save()
        ..translate(50, 50)
        ..rotate(angle)
        ..translate(0, -46 / 1.24 - (26 + (i * 7) % 20) / 1.24 * e)
        ..scale(1, _lerp(1, .3, e))
        ..drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 3 / 1.24, height: 9 / 1.24), const Radius.circular(1)),
          Paint()..color = tint[i % 3].withValues(alpha: 1 - e),
        )
        ..restore();
    }
  }

  void _foot(Canvas canvas, Size size, double t, double fade) {
    final a = _clamp01((t - kIntroRevealAt - 700) / 400) * fade;
    if (a <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
        text: 'Preparing your dojo…',
        style: text.copyWith(fontSize: 11, letterSpacing: 1, color: colors.textSecondary.withValues(alpha: a)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height - bottomInset - 56 - tp.height));
  }

  @override
  bool shouldRepaint(IntroPainter old) =>
      old.logo != logo ||
      !identical(old.colors, colors) ||
      old.logoTarget != logoTarget ||
      old.wordTarget != wordTarget ||
      old.reduceMotion != reduceMotion;
}
