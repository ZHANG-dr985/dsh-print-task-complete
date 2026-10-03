/**
 * Pre-publish gate for dsh-print-task-complete.
 *
 * Runs automatically via `prepublishOnly`, and can be run by hand with
 * `npm run verify`. It exists because shipping a stale payload is easy: the
 * skill folder, the plugin entry and the package manifest can drift apart, and
 * every one of those mistakes still produces an installable package.
 *
 * No external dependencies: this must run in a bare checkout.
 */
import { access, readFile, readdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const problems = [];
const ok = [];

function check(condition, message) {
  if (condition) ok.push(message);
  else problems.push(message);
}

async function readJson(p) {
  return JSON.parse(await readFile(p, 'utf8'));
}

async function walk(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await walk(full)));
    else out.push(full);
  }
  return out;
}

const pkgPath = path.join(root, 'package.json');
const pkg = await readJson(pkgPath);

check(typeof pkg.name === 'string' && pkg.name.length > 0, `package name: ${pkg.name}`);
check(
  /^\d+\.\d+\.\d+$/.test(pkg.version ?? ''),
  `version is a plain semver release (${pkg.version}) - bump it before publishing`
);

// 1. the bundle must point at a patch that mounts this exact package name
const patchRel = pkg.dsh?.bundle?.patch;
check(Boolean(patchRel), `dsh.bundle.patch declared (${patchRel})`);
if (patchRel) {
  const patchPath = path.join(root, patchRel.replace(/^\.\//, ''));
  let patch = '';
  try {
    patch = await readFile(patchPath, 'utf8');
    ok.push(`patch file exists: ${patchRel}`);
  } catch {
    problems.push(`patch file missing: ${patchRel}`);
  }
  check(patch.includes(pkg.name), `patch mounts this package by name (${pkg.name})`);
}

// 2. the plugin entry must load and satisfy the cordis contract
const entryRel = (pkg.main ?? './lib/index.js').replace(/^\.\//, '');
const entryPath = path.join(root, entryRel);
try {
  await access(entryPath);
  const mod = await import(pathToFileURL(entryPath).href);
  check(typeof mod.apply === 'function', 'lib entry exports apply()');
  check(Array.isArray(mod.inject) && mod.inject.includes('skills'), 'lib entry injects ["skills"]');
  check(typeof mod.name === 'string' && mod.name.length > 0, `lib entry exports a plugin name (${mod.name})`);

  // 3. the registered provider must actually yield the skill, with its body on disk
  let provider = null;
  mod.apply({ skills: { registerProvider: (f) => { provider = f(); return () => {}; } } });
  check(Boolean(provider), 'apply() registers a provider');
  if (provider) {
    const candidates = await provider.list();
    check(candidates.length === 1, `provider lists exactly one skill (${candidates.length})`);
    const def = await provider.get(candidates[0]);
    check(Boolean(def?.content && def.content.length > 100), `skill body loads (${def?.content?.length} chars)`);
    check(def.content.startsWith('---'), 'skill body starts with YAML frontmatter');
    const fm = def.content.slice(3, def.content.indexOf('\n---', 3));
    check(/^name:\s*\S+/m.test(fm), 'frontmatter declares name');
    check(/^description:\s*\S+/m.test(fm), 'frontmatter declares description');
    check(def.name === candidates[0].name, 'provider returns the candidate it listed');
    const script = path.join(def.resourceBase.path, 'scripts', 'print-done.ps1');
    try {
      await access(script);
      ok.push('resourceBase resolves scripts/print-done.ps1');
    } catch {
      problems.push('resourceBase does NOT resolve scripts/print-done.ps1');
    }
  }
} catch (error) {
  problems.push(`lib entry failed to load: ${error.message}`);
}

// 4. every PowerShell payload must stay 100% ASCII
//    (Windows PowerShell 5.1 decodes BOM-less .ps1 as ANSI on a GB2312 host and
//     would silently corrupt any non-ASCII literal)
const skillDir = path.join(root, 'skill');
let ps1Count = 0;
try {
  for (const file of await walk(skillDir)) {
    if (!file.toLowerCase().endsWith('.ps1')) continue;
    ps1Count++;
    const bytes = await readFile(file);
    const bad = bytes.reduce((n, b) => (b > 127 ? n + 1 : n), 0);
    check(bad === 0, `${path.relative(root, file)} is pure ASCII (${bad} non-ASCII bytes)`);
  }
  check(ps1Count > 0, `found ${ps1Count} PowerShell payload(s) to check`);
} catch (error) {
  problems.push(`could not scan skill/: ${error.message}`);
}

// 5. the easter-egg asset the code defaults to must be present
try {
  await access(path.join(skillDir, 'assets', 'easter-egg.png'));
  ok.push('easter egg asset present');
} catch {
  problems.push('skill/assets/easter-egg.png is missing');
}

console.log(`verify ${pkg.name}@${pkg.version}`);

if (problems.length > 0) {
  console.error('\nFAILED checks:');
  for (const p of problems) console.error(`  x ${p}`);
  console.error(`\n${problems.length} problem(s). Refusing to publish.`);
  process.exit(1);
}

console.log(`\n${ok.length} checks passed.`);
for (const o of ok) console.log(`  + ${o}`);
console.log('\nThis package is consistent and safe to publish.');
