// resources.mjs: which resource files each web example needs, written to
// test/web_resources.list. build.zig preloads only those files into the
// example's .data bundle (instead of its whole category's resources/).
//
//   node tools/webdiff/resources.mjs <c-dir> <list-file> <examples-root> <out>
//   (run by `zig build webresources`)
//
// A file is listed when either:
//   - the C example opened it while running the gate's 240 frames (run.mjs
//     with WEBDIFF_FILES), which catches files a model or font pulls in, or
//   - the C source names it as a "resources/..." string literal (with GLSL
//     version %i as 100, the web's), which catches files loaded only on a key
//     press, which the gate never makes.
// The gate then runs C with the whole category and Zig with only the listed
// files: a missing file shows up as a frame difference.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [cDir, listFile, examplesRoot, outPath] = process.argv.slice(2);
if (!cDir || !listFile || !examplesRoot || !outPath) {
  console.error('usage: resources.mjs <c-dir> <list-file> <examples-root> <out>');
  process.exit(2);
}
const here = dirname(fileURLToPath(import.meta.url));
const tmp = mkdtempSync(join(tmpdir(), 'webres-'));

/** Every file under `dir`, as paths relative to it. */
function walk(dir, prefix = '') {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    return statSync(path).isDirectory() ? walk(path, `${prefix}${entry}/`) : [`${prefix}${entry}`];
  });
}

/** Resource paths named in the C source that exist under `resources`. */
function named(source, resources) {
  const found = [];
  for (const [, literal] of source.matchAll(/"resources\/([^"]*)"/g)) {
    const path = literal.replaceAll('%i', '100');
    if (/%/.test(path) || !existsSync(join(resources, path))) continue;
    if (statSync(join(resources, path)).isDirectory()) found.push(...walk(join(resources, path), path.replace(/\/?$/, '/')));
    else found.push(path);
  }
  return found;
}

const lines = [
  '# web_resources.list: the resource files each web example loads, relative to',
  "# its category's resources/ directory. Written by `zig build webresources`",
  '# (tools/webdiff/resources.mjs); do not edit by hand. build.zig preloads only',
  '# these into the Zig builds; the browser gate proves they are enough.',
];
let failed = 0;
for (const entry of readFileSync(listFile, 'utf8').split('\n').filter(Boolean)) {
  const [category, name] = entry.split('/');
  const resources = join(examplesRoot, category, 'resources');
  const filesOut = join(tmp, `${name}.json`);
  try {
    execFileSync('node', [join(here, 'run.mjs'), join(cDir, name), name, join(tmp, `${name}.png`), '240'], {
      env: { ...process.env, WEBDIFF_FILES: filesOut },
      stdio: ['ignore', 'ignore', 'inherit'],
    });
  } catch {
    console.error(`  FAIL  ${name} (the C example did not run)`);
    failed++;
    continue;
  }
  const opened = JSON.parse(readFileSync(filesOut, 'utf8'));
  const source = readFileSync(join(examplesRoot, category, `${name}.c`), 'utf8');
  const files = [...new Set([...opened, ...(existsSync(resources) ? named(source, resources) : [])])].sort();
  lines.push(`${entry}:${files.map((f) => ' ' + f).join('')}`);
  console.log(`  ${String(files.length).padStart(3)}  ${entry}`);
}
writeFileSync(outPath, lines.join('\n') + '\n');
console.log(failed ? `FAIL  ${failed} example(s) did not run` : `wrote ${outPath}`);
process.exit(failed ? 1 : 0);
