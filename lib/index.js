/**
 * dsh-print-task-complete
 *
 * Registers the `print-task-complete` skill into the DeepSeek Harness skill
 * registry. Installing this bundle by package name therefore makes the skill
 * discoverable without touching the filesystem skill roots.
 *
 * The skill body and its scripts travel with the package under `skill/`, and
 * are advertised through `resourceBase` so the agent can resolve
 * `scripts/print-done.ps1` relative to the installed location.
 *
 * @module dsh-print-task-complete
 */
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const PROVIDER_NAME = 'print-task-complete';
const SKILL_BODY_URL = new URL('../skill/SKILL.md', import.meta.url);
const RESOURCE_BASE = {
  kind: 'directory',
  path: fileURLToPath(new URL('../skill/', import.meta.url))
};

const DESCRIPTION = [
  'Print a physical "task complete" receipt: stamp the next cell of a 30-cell A4 grid,',
  'so one sheet of paper serves 30 completions instead of one. The bundled script',
  'auto-detects the physical printer and remembers the grid position. Use it every time',
  'a tracked todo item, shared team task, goal, or the user request reaches completion.'
].join(' ');

const WHEN_TO_USE = [
  'A unit of tracked work has just finished: a todo item marked completed, a shared team',
  'task completed, a goal marked complete, or the user request delivered.'
].join(' ');

const CANDIDATE = {
  name: PROVIDER_NAME,
  description: DESCRIPTION,
  whenToUse: WHEN_TO_USE,
  invocation: {
    modelInvocable: true,
    userInvocable: true
  },
  provider: PROVIDER_NAME,
  source: 'bundled',
  resourceBase: RESOURCE_BASE,
  rank: 600,
  locator: SKILL_BODY_URL
};

const provider = {
  name: PROVIDER_NAME,
  list: () => Promise.resolve([CANDIDATE]),
  async get() {
    return {
      name: CANDIDATE.name,
      description: CANDIDATE.description,
      whenToUse: CANDIDATE.whenToUse,
      invocation: CANDIDATE.invocation,
      provider: PROVIDER_NAME,
      source: CANDIDATE.source,
      resourceBase: RESOURCE_BASE,
      content: await readFile(SKILL_BODY_URL, 'utf8')
    };
  }
};

/** Cordis plugin name. */
export const name = 'skill-print-task-complete';
/** Service required by the bundled provider. */
export const inject = ['skills'];
/** Register the bundled `print-task-complete` provider on `ctx.skills`. */
export function apply(ctx) {
  ctx.skills.registerProvider(() => provider);
}
