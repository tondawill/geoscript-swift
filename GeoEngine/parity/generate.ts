// Regenerates Tests/GeoEngineTests/parity.json from the TypeScript engine.
// Run from the web repo: npx vite-node <path to this file>
import { writeFileSync } from 'node:fs';
import {
  addCircle, addCircleSpan, addCircleThrough, addDirectionPoint, addDistancePoint, addFreePoint,
  addIntersectionPoint, addLine, addPointOn, addSegment, emptyConstruction, movePoint,
  removeKeepingPoints, removeObject, resolve,
} from '/Users/tondacode/repos/claude-code/geoscript/src/engine/construction';

let c = emptyConstruction();
const out: unknown[] = [];
const snap = () => {
  const r = resolve(c);
  out.push({
    positions: Object.fromEntries([...r].map(([id, v]) => [id, [v.x, v.y]])),
    objects: c.objects.map((o) => [o.id, o.kind, o.name ?? '']),
  });
};
const add = (result: [typeof c, string]) => {
  c = result[0];
  return result[1];
};

const A = add(addFreePoint(c, { x: 0, y: 0 }));
const B = add(addFreePoint(c, { x: 6, y: 0 }));
const s = add(addSegment(c, A, B));
const k = add(addCircle(c, A, 4));
const k1 = add(addCircle(c, B, 5));
const C = add(addIntersectionPoint(c, k, k1, 0));
const D = add(addPointOn(c, s, 0.5));
const E = add(addPointOn(c, k, 1));
const F = add(addDirectionPoint(c, D, s, Math.PI / 2, 3, false));
add(addDirectionPoint(c, D, s, 0.3, 1, false, { id: k, index: 1 }));
const p = add(addLine(c, 'line', A, C));
add(addLine(c, 'ray', B, C));
const H = add(addDistancePoint(c, C, 2.5, 1.2));
add(addCircleThrough(c, H, A));
const k3 = add(addCircleSpan(c, F, [A, B]));
add(addIntersectionPoint(c, p, k3, 0));
add(addSegment(c, E, F));
snap();

for (const [id, x, y] of [
  [A, 1, -0.5], [F, 3, 5], [D, 2, 1], [H, 9, 9], [E, -3, 2], [A, -20, 0], [A, 0.5, 0.25],
] as [string, number, number][]) {
  c = movePoint(c, id, { x, y });
  snap();
}
c = removeKeepingPoints(c, [C]);
snap();
c = removeObject(c, D);
snap();

writeFileSync('/Users/tondacode/repos/xcode/claude-code/GeoScript/GeoEngine/Tests/GeoEngineTests/parity.json', JSON.stringify(out));
console.log('snapshots', out.length);
