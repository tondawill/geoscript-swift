// Regenerates Tests/GeoEngineTests/graphs-parity.json: rows of the graphing calculator run through the
// TypeScript engine (parsing, values, drawn lines, shading, crossings, number formatting), for the
// Swift tests to match. Run from the web repo: npx vite-node <this file>
// With a directory argument it instead checks the .geoscript files with graphs written by the Swift tests.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { emptyConstruction } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/construction';
import { exportFile, importFile } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/file';
import { circleCrossings, circleForm, circleThrough } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/circle';
import { cubicGeneralThrough, cubicInterceptForm, cubicInterceptThrough, inflectionThrough } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/cubic';
import { ellipseThrough } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/ellipse';
import { hyperbolaForm, hyperbolaThrough } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/hyperbola';
import { generalThrough, interceptForm, interceptThrough, vertexThrough } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/quadratic';
import { cosineThrough, piLabel, sineThrough, tangentThrough, trigForm } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/trig';
import { verticalThrough } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/linear';
import { crossingsBetween } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/crossings';
import { compileRows } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/evaluate';
import { fillPolygons } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/implicit';
import { sidewaysCrossings, snapPoints } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/intersect';
import { formatAbs, linearThrough } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/linear';
import { drawnLines } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/sample';
import type { Expr, GraphRow, ParsedRow, Restriction } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/graph/types';
import type { Vec } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/types';

const homer = JSON.parse(
  readFileSync('/Users/tondacode/repos/claude-code/geoscript/docs/feature-docs/images/feature-22/homer-graphs.json', 'utf8'),
) as GraphRow[];

const swiftDir = process.argv[2];
if (swiftDir && !swiftDir.endsWith('.ts')) {
  let checked = 0;
  for (const name of readdirSync(swiftDir).filter((n) => n.startsWith('graphs-') && n.endsWith('.geoscript'))) {
    const r = importFile(readFileSync(swiftDir + '/' + name, 'utf8'), { center: { x: 0, y: 0 } });
    if (!r.ok) throw new Error('web could not open ' + name + ': ' + r.error);
    const want = readFileSync(swiftDir + '/' + name + '.json', 'utf8').trim();
    const got = JSON.stringify(r.graphs.map((g) => [g.id, g.text, g.color, !!g.hidden, g.between ?? null, g.width ?? null, g.dash ?? null, g.fill ?? null]));
    if (got !== want) throw new Error('rows differ in ' + name + '\n' + got + '\n' + want);
    checked++;
  }
  console.log('web opened', checked, 'files with graphs written by Swift');
  process.exit(0);
}

/** An expression as text with every bracket written, numbers as JavaScript prints them. */
const ex = (e: Expr): string => {
  switch (e.k) {
    case 'num': return String(e.v);
    case 'x': return 'x';
    case 'y': return 'y';
    case 'const': return e.name;
    case 'neg': return `(-${ex(e.a)})`;
    case 'bin': return `(${ex(e.a)} ${e.op} ${ex(e.b)})`;
    case 'fn': return `${e.name}[${ex(e.a)}]`;
    case 'call': return `${e.name}<${ex(e.a)}>`;
  }
};
const chain = (r: Restriction) => r.terms.map((t, i) => (i ? ` ${r.ops[i - 1]} ` : '') + ex(t)).join('');
const parsedText = (p: ParsedRow) => {
  const main =
    p.kind === 'y' ? `y${p.bare ? '?' : ''} = ${ex(p.expr)}`
    : p.kind === 'def' ? `${p.name}(x) = ${ex(p.expr)}`
    : p.kind === 'x' ? `x = ${ex(p.expr)}`
    : p.kind === 'circle' ? `circle ${ex(p.lhs)} = ${ex(p.rhs)} @ ${ex(p.m)}, ${ex(p.n)}`
    : p.kind === 'curve' ? `curve ${ex(p.lhs)} = ${ex(p.rhs)}`
    : `region ${chain(p)}`;
  return main + (p.where ?? []).map((r) => ` {${chain(r)}}`).join('');
};

const num = (v: number) => (Number.isFinite(v) ? v : null);
const XS = [-7.3, -2.5, -1, -0.5, 0, 0.3, 1, 2, 3.7, 6.1];
const PTS: [number, number][] = [[0, 0], [1, 2], [-2, 1], [3, -1.5], [0.5, 4], [-4, -3], [2.2, 0.7], [-0.6, 3.4]];
const pts = (lines: Vec[][]) => lines.map((l) => ({ n: l.length, every: l.filter((_, i) => i % 10 === 0 || i === l.length - 1).map((p) => [p.x, p.y]) }));
const area = (polys: Vec[][]) =>
  polys.reduce((sum, p) => sum + p.reduce((s, a, i) => {
    const b = p[(i + 1) % p.length];
    return s + (a.x * b.y - b.x * a.y) / 2;
  }, 0), 0);
const sorted = (ps: Vec[]) => [...ps].sort((a, b) => a.x - b.x || a.y - b.y).map((p) => [p.x, p.y]);

const VIEW = { xMin: -8, xMax: 8, yMin: -5, yMax: 6 };
const SCALE = 40;

function dumpCase(rows: GraphRow[], pairs: boolean) {
  const compiled = compileRows(rows);
  const out = compiled.map((c) => ({
    parsed: c.parsed ? parsedText(c.parsed) : null,
    error: c.error ? [c.error.key, c.error.name ?? ''] : null,
    fn: c.fn ? XS.map((x) => num(c.fn!(x))) : null,
    fnOfY: c.fnOfY ? XS.map((y) => num(c.fnOfY!(y))) : null,
    circle: c.circle ? [c.circle.m, c.circle.n, c.circle.r, ...PTS.map(([x, y]) => (c.circle!.inside ? c.circle!.inside(x, y) : true))] : null,
    implicit: c.implicit ? PTS.map(([x, y]) => num(c.implicit!.f(x, y))) : null,
    margin: c.region ? PTS.map(([x, y]) => num(c.region!.margin(x, y))) : null,
    strict: c.region ? c.region.edges.map((e) => e.strict) : null,
    area: c.region ? area(fillPolygons(c.region.margin, VIEW, SCALE)) : null,
    lines: c.error ? null : pts(drawnLines(c, VIEW, SCALE)),
  }));
  const ok = compiled.filter((c) => !c.error);
  const between: [number, number, number[][]][] = [];
  if (pairs) {
    for (let i = 0; i < compiled.length; i++) {
      for (let j = i + 1; j < compiled.length; j++) {
        const [a, b] = [compiled[i], compiled[j]];
        if (a.error || b.error || !a.parsed || !b.parsed) continue;
        const ps = crossingsBetween(a, b, VIEW, SCALE);
        if (ps.length) between.push([i, j, ps.map((p) => [p.x, p.y])]);
      }
    }
  }
  const fns = ok.flatMap((c) => (c.fn ? [c.fn] : []));
  const circles = ok.flatMap((c) => (c.circle ? [c.circle] : []));
  const gs = ok.flatMap((c) => (c.fnOfY ? [c.fnOfY] : []));
  return {
    texts: rows.map((r) => r.text),
    rows: out,
    between,
    snap: sorted(snapPoints(fns, VIEW.xMin, VIEW.xMax, 640)),
    circles: sorted(circleCrossings(circles, fns, SCALE)),
    sideways: sorted(sidewaysCrossings(gs, fns, circles, VIEW.yMin, VIEW.yMax, 440)),
  };
}

const rows = (...texts: string[]): GraphRow[] => texts.map((text, i) => ({ id: 'g' + (i + 1), text, color: 'red' }));

const cases = [
  // Parsing and the school way of writing.
  rows('y = 2x', 'x^2 + 2x + 3', 'y = x² + 2x + 3', 'y = 3(x + 1)', 'y = 3,5x', 'y = 0.5x', 'y = 2 · x − 1', 'y = 2π'),
  rows('y = -x^2', 'y = 2^3^2', 'y = 2^-x', 'y = 1/2x', 'y = 6/(2x)', 'y = x - 3', 'y = x³ − 4x', 'y = 2 × x ÷ 3', 'y = 4 : x'),
  rows('y = sin x', 'y = sin(2x)', 'y = sin x cos x', 'y = xsinx', 'y = sin^2 x + cos^2 x', 'y = √x', 'y = √(x + 7)', 'y = sqrt(x)'),
  rows('y = |x - 5|', 'y = |x||x|', 'y = abs(x)', 'y = ln e', 'y = log 100', 'y = exp(x)', 'y = tan x', 'y = x^(1/3)', 'y = ln|x|', 'y = 1/x', 'y = sin²x', 'y = √2x', 'y = ln 2x'),
  rows('f(x) = sin x', 'y = 2f(x) - 3', 'y = g(x + 1)', 'h(x) = x^2', 'g(x) = h(x) + 1', 'k(x) = x {x > 0}', 'y = k(x) + 1'),
  rows('y = 3x +', 'y = (x + 1', 'y = x )', 'y = 2a', 'x(x) = 2', '2 = 3', 'y ≤ x = 2', 'y = x # 2', 'y = q(x)', 'f(x) = g(x)', 'g(x) = f(x)', '{x > 1}', 'y = x {x}', 'y = x {x > 1', 'y = x {x > 1} 2', 'x = x + 1', 'y = y + 1', '(x - 1)^2 + (y - 2)^2 = -4', 'y = x {q(x) > 1}'),
  rows('m(x) = x', 'm(x) = 2x', 'y = m(x)', '', '   '),
  // Restrictions, sideways rows, circles, curves and shading.
  rows('y = x^2 {0 ≤ x ≤ 3}', 'y = x {x >= 1}', 'y = x {x<=1}', 'y = 2x {x > 0}{y < 4}', 'y = x {5 > x > 2}', 'x = y^2 - 1 {-2 ≤ y ≤ 2}', 'x = 0 {-3 ≤ y ≤ 4}', 'x = 2y + 1'),
  rows('(x - 5)^2 + (y - 1)^2 = 25 {y ≥ 1}', 'x^2 + y^2 = 1 {x ≥ 0}', 'x^2 + y^2 = 4 {y ≥ 0}', '(y + 1)^2 + (x - 2)^2 = 3^2', 'x^2 + y^2 = 5^2', '(x - 8)^2 + y^2 = 5^2', 'y = 3'),
  rows('(x - 1)^2/3^2 + y^2/2^2 = 1', 'x^2/4 + y^2 = 1 {y ≥ 0}', '2y = x', 'x y = 1', 'y^2 = x^3 - x'),
  rows('(x - 1)^2 + y^2 ≤ 4', '-1 ≤ y < 2', 'y ≤ x^2 {0 ≤ x ≤ 2}{y ≥ 0}', 'x ≥ y^2', 'x^2/4 + y^2 < 1', 'y ≤ 4 - x^2 {y ≥ 0}', 'y > sin x'),
  // Crossings.
  rows('y = 2x + 1', 'y = -x + 4', 'y = 1.25x + 0.5', 'y = 0.5(x - 1)^2 - 2', 'y = x^2', 'y = 2x - 1'),
  rows('y = x', 'y = -x', 'y = 2', 'y = 1/x', 'y = 0', 'y = tan x', 'y = x + 1', 'y = x + x'),
  rows('y = x^2 - 4', 'x = y^2 - 4', 'x = 5', 'x^2 + y^2 = 4^2 {y ≥ 0}', 'y = x + 1.5', 'x = 2', 'y = x^2 {x ≥ 0}'),
  homer.map((r) => ({ ...r })),
];

const values = [0, 1, 2, 0.5, 1.25, 1 / 3, 2 / 3, 7 / 8, 0.1 + 0.2, 7.1023456789, 12.3456789012, 1e-7, 3.14159, 100 / 7, 0.005, 123456.5, 1 / 99, 0.30000000000000004];
const format = {
  values,
  cs: values.map((v) => formatAbs(v, 'cs')),
  en: values.map((v) => formatAbs(v, 'en')),
  strings: [...values, -2.5, 1e21, 1.5e-7, 123e-10, 5e-324, 1e300, -0.000001, 0.000001].map((v) => [v, String(v)]),
  lines: [
    [[0, 1], [1, 3]], [[0, 0], [3, 1]], [[-1, 2], [2, 2]], [[0, 0], [1, -1]], [[2, 1], [2, 5]], [[0.1, 0.2], [0.4, 1.1]], [[-3, 4], [5, -2]],
  ].map(([a, b]) => [a, b, linearThrough({ x: a[0], y: a[1] }, { x: b[0], y: b[1] }, 'cs')]),
};

// Rows the function cards write, through points on a grid (with some halves, thirds and π), both languages.
let seed = 7;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
const STEPS = [1, 0.5, 0.25, 1 / 3, Math.PI / 4];
const coord = () => {
  const step = STEPS[Math.floor(rand() * STEPS.length)];
  return Math.round((rand() * 12 - 6) / step) * step;
};
const pt = (): Vec => ({ x: coord(), y: coord() });
// Points as text: JSONSerialization reads some numbers a bit off.
const forms: [string, string[][], (string | null)[]][] = [];
for (let i = 0; i < 160; i++) {
  const ps = [pt(), pt(), pt(), pt()];
  // Sometimes the same x or y, to hit the refusals.
  if (i % 7 === 0) ps[1].x = ps[0].x;
  if (i % 11 === 0) ps[1].y = ps[0].y;
  const [a, b, c, d] = ps;
  const r1 = { x: a.x, y: 0 }, r2 = { x: b.x, y: 0 }, r3 = { x: c.x, y: 0 };
  const out = (lang: 'cs' | 'en') => [
    linearThrough(a, b, lang), verticalThrough(a, lang),
    vertexThrough(a, b, lang), interceptThrough(r1, r2, c, lang), generalThrough(a, b, c, lang), interceptForm(1, a.x, b.x, lang),
    inflectionThrough(a, b, lang), cubicInterceptThrough([r1, r2, r3], d, lang), cubicGeneralThrough([a, b, c, d], lang), cubicInterceptForm(1, [a.x, b.x, c.x], lang),
    sineThrough(a, b, lang), cosineThrough(a, b, lang), tangentThrough(a, b.x, c, lang), trigForm('tan', 1, Math.abs(b.x - a.x) > 1e-9 ? Math.PI / (2 * Math.abs(b.x - a.x)) : 1, a.x, a.y, lang),
    hyperbolaThrough(a, b, lang), hyperbolaForm(1, a.x, a.y, lang),
    circleThrough(a, b, lang), circleForm(a.x, a.y, (b.x - a.x) ** 2 + 0.37, lang),
    ellipseThrough(a, { x: b.x, y: a.y }, { x: a.x, y: c.y }, lang),
    piLabel(a.x),
  ];
  forms.push(['cs', ps.map((q) => [String(q.x), String(q.y)]), out('cs')]);
  forms.push(['en', ps.map((q) => [String(q.x), String(q.y)]), out('en')]);
}

// A file written by the web: the Swift tests open it and expect these rows.
const fileRows: GraphRow[] = [
  ...homer.slice(0, 6),
  { id: 'g40', text: 'y = x^2', color: 'blue', hidden: true, dash: 'dotted', width: 1.5 },
  { id: 'g41', text: 'y ≤ x', color: '#123abc', fill: 0.25 },
  { id: 'g42', text: '', color: 'green', between: ['g40', 'g41'] },
  { id: 'g43', text: '   ', color: 'red' },
];
const webFile = exportFile(emptyConstruction(), [], { steps: 'Construction steps', exercise: 'Exercise', graphs: 'Graphs' }, [], fileRows);
const webRows = importFile(webFile, { center: { x: 0, y: 0 } });

writeFileSync(
  '/Users/tondacode/repos/xcode/claude-code/GeoScript/GeoEngine/Tests/GeoEngineTests/graphs-parity.json',
  JSON.stringify({
    view: VIEW,
    scale: SCALE,
    xs: XS,
    pts: PTS,
    cases: cases.map((c, i) => dumpCase(c, i !== cases.length - 1 || true)),
    format,
    forms,
    file: webFile,
    fileRows: webRows.ok ? webRows.graphs.map((g) => [g.id, g.text, g.color, !!g.hidden, g.between ?? null, g.width ?? null, g.dash ?? null, g.fill ?? null]) : null,
    handFile: 'GeoScript 1\n\nGraphs:\n- y = x^2\n- y = 2x + 1\n- ∩ 1, 2\n- ∩ 1, 5\n- x^2 + y^2 = 9\n',
    handRows: (() => {
      const r = importFile('GeoScript 1\n\nGraphs:\n- y = x^2\n- y = 2x + 1\n- ∩ 1, 2\n- ∩ 1, 5\n- x^2 + y^2 = 9\n', { center: { x: 0, y: 0 } });
      return r.ok ? r.graphs.map((g) => [g.id, g.text, g.color, !!g.hidden, g.between ?? null, g.width ?? null, g.dash ?? null, g.fill ?? null]) : null;
    })(),
  }),
);
console.log('wrote graphs-parity.json:', cases.length, 'cases');
