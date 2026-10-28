// Parity + usage check: every tr("...") key in the QML must exist in BOTH
// language tables, and both tables must have the same key set.
const fs = require('fs');
const dir = require('path').resolve(__dirname, '..');

let src = fs.readFileSync(dir + '/Model.js', 'utf8').replace('.pragma library', '');
// expose the tables
src += '\n;globalThis.__EN = STRINGS.en; globalThis.__RU = STRINGS.ru;';
eval(src);
const EN = globalThis.__EN, RU = globalThis.__RU;
const enKeys = Object.keys(EN), ruKeys = Object.keys(RU);

let fail = 0;
for (const k of enKeys) if (!(k in RU)) { console.log('missing in ru:', k); fail = 1 }
for (const k of ruKeys) if (!(k in EN)) { console.log('missing in en:', k); fail = 1 }
console.log('key parity:', enKeys.length, 'en /', ruKeys.length, 'ru');

// every tr("key") used in QML
const qml = fs.readdirSync(dir).filter(f => f.endsWith('.qml'));
const used = new Set();
for (const f of qml) {
  const t = fs.readFileSync(dir + '/' + f, 'utf8');
  for (const m of t.matchAll(/tr\((?:"|')([\w.]+)(?:"|')/g)) used.add(m[1]);
  for (const m of t.matchAll(/Model\.t\((?:"|')([\w.]+)(?:"|')/g)) used.add(m[1]);
}
let miss = 0;
for (const k of used) {
  if (!(k in EN)) { console.log('used but MISSING:', k); miss = 1 }
  if (!(k in RU)) { console.log('used (no ru):', k); miss = 1 }
}
console.log('keys used in QML:', used.size, 'missing:', miss ? 'YES' : 'no');
// daemon.sh + control.sh
for (const f of ['daemon.sh', 'control.sh']) {
  const t = fs.readFileSync(dir + '/' + f, 'utf8');
  for (const m of t.matchAll(/tr (?:"|')([\w.]+)/g)) {}
}
process.exit(fail || miss ? 1 : 0);
