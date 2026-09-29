"""Traces the D/CLIX letterforms out of assets/branding/app-icon.png.

Prints Dart point lists for lib/screens/splash_screen.dart, so the launch intro draws
the logo's own lettering. Run from flutter_app/ with: python3 tool/trace_wordmark.py
"""
from PIL import Image
im = Image.open('/Users/sadvi/Projects/Dclix/flutter_app/assets/branding/app-icon.png').convert('RGB')
px = im.load()
Y0, Y1 = 316, 444
CAP_TOP, CAP_H = 328, 106.0
UNIT = CAP_H / 22.0
X0 = 224

def white(x, y):
    r, g, b = px[x, y]
    return r > 150 and g > 150 and b > 150

SEGS = {1:[('l','b')], 2:[('b','r')], 3:[('l','r')], 4:[('r','t')], 5:[('l','t'),('r','b')],
        6:[('b','t')], 7:[('l','t')], 8:[('t','l')], 9:[('t','b')], 10:[('t','r'),('b','l')],
        11:[('t','r')], 12:[('r','l')], 13:[('r','b')], 14:[('b','l')]}

def loops(x0, x1):
    inside = lambda x, y: x0 <= x <= x1 and Y0 <= y <= Y1 and white(x, y)
    links = {}
    for y in range(Y0 - 1, Y1 + 1):
        for x in range(x0 - 1, x1 + 1):
            tl, tr = inside(x, y), inside(x + 1, y)
            bl, br = inside(x, y + 1), inside(x + 1, y + 1)
            v = tl * 8 + tr * 4 + br * 2 + bl
            pt = {'t': (x + .5, y), 'r': (x + 1, y + .5), 'b': (x + .5, y + 1), 'l': (x, y + .5)}
            for a, b in SEGS.get(v, []):
                links.setdefault(pt[a], []).append(pt[b])
    out = []
    while links:
        start = next(iter(links))
        loop, cur = [start], start
        while True:
            nxts = links.get(cur)
            if not nxts:
                break
            nxt = nxts.pop()
            if not nxts:
                del links[cur]
            cur = nxt
            if cur == start:
                break
            loop.append(cur)
        if len(loop) > 8:
            out.append(loop)
    return out

def area(p):
    return abs(sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))) / 2

def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1
    n = (dx * dx + dy * dy) ** .5 or 1
    worst, idx = 0, 0
    for i, (x, y) in enumerate(pts[1:-1], 1):
        d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / n
        if d > worst:
            worst, idx = d, i
    if worst <= eps:
        return [pts[0], pts[-1]]
    return rdp(pts[:idx + 1], eps)[:-1] + rdp(pts[idx:], eps)

def fmt(loop, eps):
    # a closed loop has no endpoints, so cut it at the point farthest from the start
    far = max(range(len(loop)), key=lambda i: (loop[i][0] - loop[0][0]) ** 2 + (loop[i][1] - loop[0][1]) ** 2)
    simple = rdp(loop[:far + 1], eps)[:-1] + rdp(loop[far:] + [loop[0]], eps)[:-1]
    return simple, ', '.join('Offset(%.2f, %.2f)' % ((x - X0) / UNIT, (y - CAP_TOP) / UNIT) for x, y in simple)

for name, (a, b), eps in [('D', (224, 340), .9), ('C', (413, 522), .9), ('L', (538, 623), .9),
                          ('I', (641, 669), .9), ('X', (684, 800), .9)]:
    ls = sorted(loops(a, b), key=area, reverse=True)
    print('// %s: %d loop(s), sizes %s' % (name, len(ls), [len(l) for l in ls]))
    for i, l in enumerate(ls):
        pts, code = fmt(l, eps)
        print('const _%s%d = [%s]; // %d pts' % (name.lower(), i, code, len(pts)))
    print()
