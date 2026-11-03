#!/usr/bin/env node
/* Write every drawing in art.js to art/<name>.svg as a standalone file (currentColor set to Ink, the tier variables
   to their light values), so the set can be read as files (the helm council's tools/make_art.js; helm-ui S10).
   Run from anywhere: node modules/keel/ui/make_art.js [<out dir>] — `keel ui check` writes them to a scratch folder
   and compares them with art/, so an edit of art.js that forgets this run fails the suite. */
'use strict';
var fs = require('fs'), path = require('path');
var root = path.dirname(__filename), out = process.argv[2] || path.join(root, 'art');
global.window = {};
new Function(fs.readFileSync(path.join(root, 'art.js'), 'utf8'))();
var A = global.window.ART;
var VARS = { '--flag': '#0000AA', '--fire': '#D97757', '--hue-violet': '#5A3FD6', '--hue-teal': '#0B7480', '--hue': '#0B7480' };
function standalone(s) {
  s = s.replace(/var\((--[a-z-]+)(?:, ?[^)]+)?\)/g, function (m, v) { return VARS[v] || '#15171C'; });
  s = s.replace(/currentColor/g, '#15171C').replace(/<svg /, '<svg xmlns="http://www.w3.org/2000/svg" ');
  return s + '\n';
}
var files = {};
A.TIERS.forEach(function (t) { files['buoy-' + t] = A.buoy(t, t, 48); });
files['buoy-taken'] = A.buoy('safe', 'taken', 48); files['buoy-picked'] = A.buoy('safe', 'picked', 48);
files.pennant = A.pennant(48); files.flag = A.flag(48); files['due-flag'] = A.dueFlag(32);
files.sloop = A.sloop(48); files['burst-mark'] = A.burstMark(48); files.waves = A.waves();
files['quiet-night'] = A.quietNight(96); files['finish-line'] = A.finishLine(96); files['nothing-later'] = A.nothingLater(48); files['no-skippers'] = A.noSkippers(48); files.memo = A.memo(48);
files.fireworks = A.fireworks('#0B7480', 720, 260);
fs.mkdirSync(out, { recursive: true });
Object.keys(files).forEach(function (k) { fs.writeFileSync(path.join(out, k + '.svg'), standalone(files[k])); });
console.log(Object.keys(files).length + ' drawings written to ' + out);
