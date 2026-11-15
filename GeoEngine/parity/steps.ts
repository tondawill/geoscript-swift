// Regenerates Tests/GeoEngineTests/steps-parity.json: every typed step from the web test suite, run through
// the TypeScript engine, for the Swift tests to match. Run from the web repo: npx vite-node <this file>
// With a path argument it instead checks .geoscript files written by the Swift tests.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { emptyConstruction, resolve, setExercise } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/construction';
import { exportFile, importFile } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/file';
import { buildProtocol } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/protocol';
import { applyStep, editStep, insertStep } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/typing/apply';
import { autocorrect } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/typing/autocorrect';
import { suggest } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/typing/suggest';
import type { Construction } from '/Users/tondacode/repos/claude-code/geoscript/src/engine/types';

const root = '/Users/tondacode/repos/claude-code/geoscript/src/engine/';
const fmt = (n: number) => String(Math.round(n * 100) / 100);
const f = { dim: fmt, deg: fmt };
const ctx = { center: { x: 0, y: 0 } };

const dump = (c: Construction) => ({
  texts: buildProtocol(c, f).map((s) => [s.objectId, s.text, s.objects.join(','), s.exercise ? 'x' : '']),
  positions: Object.fromEntries([...resolve(c)].map(([id, v]) => [id, [v.x, v.y]])),
  objects: c.objects.map((o) => [o.id, o.kind, o.name ?? '']),
});

const swiftDir = process.argv[2];
if (swiftDir && !swiftDir.endsWith('.ts')) {
  let checked = 0;
  for (const name of readdirSync(swiftDir).filter((n) => n.endsWith('.geoscript'))) {
    const text = readFileSync(swiftDir + '/' + name, 'utf8');
    const r = importFile(text, ctx);
    if (!r.ok) throw new Error('web could not open ' + name + ': ' + r.error);
    const want = JSON.parse(readFileSync(swiftDir + '/' + name + '.json', 'utf8'));
    if (JSON.stringify(dump(r.construction).texts) !== JSON.stringify(want.texts)) {
      throw new Error('steps differ in ' + name + '\n' + JSON.stringify(dump(r.construction).texts) + '\n' + JSON.stringify(want.texts));
    }
    checked++;
  }
  console.log('web opened', checked, 'files written by Swift');
  process.exit(0);
}

const literal = /'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"/g;
const strings = (src: string) => [...src.matchAll(literal)].map((m) => (m[1] ?? m[2]).replace(/\\'/g, "'"));
const source = readFileSync(root + 'typing/apply.test.ts', 'utf8');
const scenarios: string[][] = [];
for (const m of source.matchAll(/\btype\(((?:\s*(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\s*,?)+)\s*\)/g)) scenarios.push(strings(m[1]));

// Forms the web tests reach through other helpers, plus combinations of everything.
scenarios.push(
  ['A', 'B', 'AB'],
  ['A', 'B', 'C', 'AB', 'BC', 'CA'],
  ['ABCD'],
  ['△ABC'],
  ['AB; |AB| = 6 cm', 'k; k(A, r = 4 cm)', 'l; l(B, r = 5 cm)', 'C; C ∈ k ∩ l', 'AC', 'BC'],
  ['AB; |AB| = 8', 'p; A ∈ p ∧ p ⊥ AB', 'q; B ∈ q ∧ q ∥ p', 'C ∈ p', 'D; D ∈ q ∧ |BD| = 3 cm', 'CD'],
  ['AB; |AB| = 5', 'C; |∠BAC| = 60° ∧ |AC| = 3 cm', 'AC'],
  ['AB', 'CD; CD ⊥ AB', 'E ∈ AB', 'r; E ∈ r ∧ r ∥ CD'],
  ['AB; |AB| = 5', 'p; p ∥ AB ∧ |p AB| = 4 cm', 'q; |q ↦AB| = 2'],
  ['AB; |AB| = 6', 'M ∈ AB', 'CD; CD ⊥ AB ∧ |CD| = 3 cm ∧ |MC| = |MD|'],
  ['A', 'B', 'k; k(A, r = |AB|)', 'C', 'D', 'l; l(C, r = |AB|)', 'E; E ∈ k ∧ AE ⊥ AB'],
  ['↦AB', 'a = CD', 'p = ↔EF', 'q = ↦GH', '↔IJ'],
  ['AB; |AB| = 0', 'nonsense !!', 'k(Z, r = 1)', 'k(Z, r = 2)', 'X ∈ m', 'p ⊥ q', 'AB'],
  ['A1', "B'", 'A1B\'', 'k1; k1(A1, r = 2,5 cm)'],
);

const out = scenarios.map((steps) => {
  let c = emptyConstruction();
  const results = steps.map((text) => {
    const r = applyStep(c, text, ctx);
    if (!r.ok) return { ok: false, error: r.error, name: r.name ?? '', select: '' };
    c = r.construction;
    return { ok: true, error: '', name: '', select: r.select ?? '', ...dump(c) };
  });
  const protocol = buildProtocol(c, f);
  const later: unknown[] = [];
  const record = (label: string, r: ReturnType<typeof applyStep>) =>
    later.push(r.ok ? { label, ok: true, error: '', select: r.select ?? '', ...dump(r.construction) } : { label, ok: false, error: r.error, select: '' });
  protocol.forEach((step, i) => {
    record(`same ${i}`, editStep(c, step, step.text, ctx));
    record(`delete ${i}`, editStep(c, step, '', ctx));
    if (step.text.includes('|') && step.text.includes('cm')) record(`resize ${i}`, editStep(c, step, step.text.replace(/= [0-9,.]+ cm/, '= 7 cm'), ctx));
  });
  record('insert first', insertStep(c, 'Z', ctx, 0));
  record('insert last', insertStep(c, 'Y', ctx));
  const frozen = setExercise(c, c.objects.slice(0, 1).map((o) => o.id), true);
  const file = exportFile(frozen, buildProtocol(frozen, f), { steps: 'Construction', exercise: 'Exercise' }, [{ tool: 'pen', color: 'red', pts: [1, 2, 3, 4] }]);
  const handWritten = file.slice(0, file.indexOf('--- data ---'));
  const opened = importFile(handWritten, ctx);
  return {
    steps,
    results,
    later,
    frozen: dump(frozen),
    file,
    handWritten,
    handResult: opened.ok ? { ok: true, ...dump(opened.construction) } : { ok: false, texts: [], positions: {}, objects: [] },
  };
});

const words = ['A->B', 'A<->B', 'a _|_ b', 'p ^ q', 'p || q', '|AB|', '<BAC = 60deg', '<(AB, p)', 'C e p', 'k n l', 'k1', 'A12', 'x1 e k2', 'deg', 'E e F', 'C E p'];
const corrections = words.map((text) => ({ text, ...autocorrect(text, text.length), input: text.length }));
const names = ['A', 'A₁', 'B', 'k', 'k₁', 'k₂', 'p'];
const suggestions = ['C ∈ k', '|A', '|a', 'k', 'k₁', 'Z', 'C ∈ k ', 'ab'].map((text) => ({ text, ...(suggest(text, text.length, names) ?? { from: -1, to: -1, items: [] }) }));

writeFileSync(
  '/Users/tondacode/repos/xcode/claude-code/GeoScript/GeoEngine/Tests/GeoEngineTests/steps-parity.json',
  JSON.stringify({ scenarios: out, corrections, suggestions }),
);
console.log('scenarios', out.length, 'steps', out.reduce((n, s) => n + s.steps.length, 0));
