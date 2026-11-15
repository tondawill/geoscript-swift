// Regenerates GeoScript/State/Messages.swift from the web translations.
// Run from the web repo: npx vite-node <path to this file>
import { writeFileSync } from 'node:fs';
import { en } from '/Users/tondacode/repos/claude-code/geoscript/src/i18n/en';
import { cs } from '/Users/tondacode/repos/claude-code/geoscript/src/i18n/cs';

const dict = (m: Record<string, string>) =>
  Object.entries(m)
    .map(([k, v]) => `        ${JSON.stringify(k)}: ${JSON.stringify(v)},`)
    .join('\n');

writeFileSync(
  '/Users/tondacode/repos/xcode/claude-code/GeoScript/GeoScript/State/Messages.swift',
  `// Generated from the web app's translations by GeoEngine/parity/messages.ts. Do not edit by hand.\nenum Messages {\n    static let en: [String: String] = [\n${dict(en)}\n    ]\n\n    static let cs: [String: String] = [\n${dict(cs)}\n    ]\n}\n`,
);
