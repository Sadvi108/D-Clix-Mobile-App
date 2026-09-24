import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../services/user_session.dart';
import '../theme/app_theme.dart';

// Launch intro ("dot bloom"). One orange dot pops in the centre and splits into eight, one
// per stroke of the D/CLIX wordmark; each flies to its place and springs open into its
// stroke. The slash then sends out a ring that bursts into the badge above the word,
// ripples run while the session restores, and the badge and word glide into the Login
// header (or the stage zooms away into Home when a saved session was restored).
//
// Everything is drawn in a 100x100 "stage" square, the same units as the approved HTML
// preview, so timings and shapes carry over one to one.

// Timeline, in milliseconds from the first frame.
const double kIntroSplitAt = 220; // the first dot splits and the eight fly apart
const double kIntroGrowAt = 520; // the dots start springing open into strokes
const double kIntroWordAt = 1220; // the word has formed
const double kIntroRevealAt = 1580; // the badge bursts open above the word
const double kIntroExitMin = 2180; // earliest moment the splash may leave
const double kIntroStillAt = 2500; // a settled frame: shown as-is when Reduce Motion is on
const double kIntroGlideMs = 600; // logged out: badge and word glide into the Login header
const double kIntroZoomMs = 450; // logged in: the stage zooms away into Home

const double _wordScale = 1.25; // glyphs are designed at 22 units tall, drawn 1.25x
const double _wordSlide = 66; // the word moves down this far to make room for the badge
const double _ringR = 39.5; // the badge's own orange ring
const double _badgeD = 96 / 1.24; // badge diameter
const Offset _ringCentre = Offset(50, 50);
const int _m = 60; // points per stroke

// ---------------------------------------------------------------------------------------
// The word. Eight monoline strokes, each blooming out of one of the eight dots.

enum StrokeInk { ink, slash }

const Offset _dotFrom = Offset(50, 52); // where the first dot pops, and the eight split
const double _strokeW = 5.5 * _wordScale;

class WordStroke {
  WordStroke(this.to, this.mid, this.delay, this.ink);

  /// The finished glyph stroke, in stage units, and the point it blooms from.
  final List<Offset> to;
  final Offset mid;
  final double delay;
  final StrokeInk ink;

  /// The stroke at time [t], or null while the first dot has not split yet. Until it
  /// opens the points sit on top of each other, which draws as a round dot.
  ({List<Offset> pts, double e, double width})? at(double t) {
    if (t < kIntroSplitAt) return null;
    final fly = Curves.easeOutCubic.transform(_clamp01((t - kIntroSplitAt) / 300));
    final from = Offset.lerp(_dotFrom, mid, fly)!;
    final e = Curves.easeOutBack.transform(_clamp01((t - kIntroGrowAt - delay) / 420));
    return (pts: [for (final p in to) from + (p - mid) * e], e: e, width: _strokeW);
  }
}

Offset _w(Offset p) => Offset(50 + (p.dx - 50) * _wordScale, 52 + (p.dy - 52) * _wordScale);

Path _polyline(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final q in pts.skip(1)) {
    p.lineTo(q.dx, q.dy);
  }
  return p;
}

List<Offset> _sample(Path p) {
  final m = p.computeMetrics().single;
  return [for (var i = 0; i < _m; i++) m.getTangentForOffset(m.length * i / (_m - 1))!.position];
}

Offset _centre(List<Offset> pts) {
  final box = pts.skip(1).fold(Rect.fromPoints(pts.first, pts.first), (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
  return box.center;
}

/// The eight strokes of D/CLIX, left to right, each blooming from its own dot.
final List<WordStroke> wordStrokes = () {
  final dBowl = Path()
    ..moveTo(-2, 41)
    ..lineTo(4, 41)
    ..arcToPoint(const Offset(4, 63), radius: const Radius.circular(11))
    ..lineTo(-2, 63);
  final c = Path()
    ..moveTo(50.8, 44.2)
    ..arcToPoint(const Offset(50.8, 59.8), radius: const Radius.circular(11), largeArc: true, clockwise: false);
  final glyphs = <(Path, StrokeInk)>[
    (_polyline(const [Offset(-2, 41), Offset(-2, 63)]), StrokeInk.ink), // D stem
    (dBowl, StrokeInk.ink), // D bowl
    (_polyline(const [Offset(22, 58), Offset(28, 46)]), StrokeInk.slash),
    (c, StrokeInk.ink),
    (_polyline(const [Offset(58, 41), Offset(58, 63), Offset(70, 63)]), StrokeInk.ink), // L
    (_polyline(const [Offset(78, 41), Offset(78, 63)]), StrokeInk.ink), // I
    (_polyline(const [Offset(85, 41), Offset(101, 63)]), StrokeInk.ink), // X
    (_polyline(const [Offset(101, 41), Offset(85, 63)]), StrokeInk.ink), // X
  ];
  return [
    for (var i = 0; i < glyphs.length; i++)
      () {
        final to = _sample(glyphs[i].$1).map(_w).toList();
        return WordStroke(to, _centre(to), i * 40.0, glyphs[i].$2);
      }(),
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
    final glow = Rect.fromCircle(center: px(_ringCentre), radius: 150 / 1.24 * u);
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
      final mid = px(_ringCentre);
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
    final r = Rect.fromCircle(center: _ringCentre, radius: 85 / 1.24 * s);
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
      canvas.drawCircle(_ringCentre, _badgeD / 2 * (1 + e),
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
    var rect = Rect.fromCircle(center: px(_ringCentre), radius: _badgeD * u / 2 * scale);
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

  /// Once the word has formed, the slash sends out a ring that settles on the badge.
  void _ring(Canvas canvas, double t) {
    if (t < kIntroWordAt) return;
    final e = Curves.easeOutCubic.transform(_clamp01((t - kIntroWordAt) / (kIntroRevealAt - kIntroWordAt)));
    final fade = 1 - _clamp01((t - kIntroRevealAt - 250) / 200);
    if (fade <= 0) return;
    canvas.drawCircle(Offset.lerp(_slashAt, _ringCentre, e)!, _lerp(3, _ringR, e),
        _stroke(colors.primary.withValues(alpha: fade), 3 - .4 * _clamp01((t - kIntroWordAt) / 360)));
  }

  void _word(Canvas canvas, double t, Offset Function(Offset) px, double u, double glide, double fade) {
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
    // the first dot, before it splits into one per stroke
    if (t < kIntroSplitAt) {
      canvas.drawCircle(_dotFrom, _strokeW / 2 * Curves.easeOutBack.transform(_clamp01(t / 200)),
          Paint()..color = colors.primary);
    }
    for (final s in wordStrokes) {
      final st = s.at(t);
      if (st == null) continue;
      // the dots take the word's ink as they fly apart; the slash keeps the brand orange
      final ink = s.ink == StrokeInk.slash
          ? colors.primary
          : Color.lerp(colors.primary, colors.textPrimary, _clamp01((t - kIntroSplitAt) / 150))!;
      if (st.e <= 0) {
        canvas.drawCircle(st.pts.first, st.width / 2, Paint()..color = ink);
      } else {
        canvas.drawPath(_polyline(st.pts), _stroke(ink, st.width));
      }
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
