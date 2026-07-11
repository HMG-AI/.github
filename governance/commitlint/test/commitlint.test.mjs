import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const testDirectory = dirname(fileURLToPath(import.meta.url));
const assetDirectory = resolve(testDirectory, '..');
const commitlintBinary = resolve(assetDirectory, 'node_modules/.bin/commitlint');
const trustedConfig = resolve(assetDirectory, 'commitlint.config.mjs');
const lintRange = resolve(assetDirectory, 'lint-range.sh');

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    encoding: 'utf8',
    env: { ...process.env, LC_ALL: 'C' },
    ...options,
  });
}

function lint(message, cwd = assetDirectory) {
  return run(
    commitlintBinary,
    ['--config', trustedConfig, '--cwd', assetDirectory],
    { cwd, input: message },
  );
}

function assertLintFailure(message, expectedRule) {
  const result = lint(message);
  assert.notEqual(result.status, 0, result.stdout || result.stderr);
  assert.match(`${result.stdout}\n${result.stderr}`, new RegExp(expectedRule));
}

test('accepts a conventional English commit message', () => {
  const result = lint('feat(api): add tenant audit endpoint\n');
  assert.equal(result.status, 0, result.stdout || result.stderr);
});

test('rejects Unicode Han script in subject, body, and footer', () => {
  assertLintFailure('fix: 修复 tenant lookup\n', 'subject-no-han');
  assertLintFailure(
    'fix: handle tenant lookup\n\nDescribe 修复 behavior.\n',
    'body-no-han',
  );
  assertLintFailure(
    'fix: handle tenant lookup\n\nBREAKING CHANGE: 删除 legacy field\n',
    'footer-no-han',
  );
});

test('uses Unicode Script=Han rather than a basic CJK block range', () => {
  assertLintFailure('docs: add 㐀 extension character\n', 'subject-no-han');
});

test('does not discover or execute a caller commitlint JavaScript config', async (t) => {
  const callerDirectory = await mkdtemp(resolve(tmpdir(), 'hmg-commitlint-caller-'));
  t.after(() => rm(callerDirectory, { recursive: true, force: true }));

  const marker = resolve(callerDirectory, 'caller-config-executed');
  await writeFile(
    resolve(callerDirectory, 'commitlint.config.mjs'),
    `import { writeFileSync } from 'node:fs';\nwriteFileSync(${JSON.stringify(marker)}, 'unsafe');\nexport default {};\n`,
  );

  const result = lint('feat: trusted configuration only\n', callerDirectory);
  assert.equal(result.status, 0, result.stdout || result.stderr);

  const markerProbe = run('test', ['-e', marker]);
  assert.notEqual(markerProbe.status, 0, 'caller configuration was executed');
});

test('validates SHA inputs and lints each commit in base..head', async (t) => {
  const repository = await mkdtemp(resolve(tmpdir(), 'hmg-commitlint-range-'));
  t.after(() => rm(repository, { recursive: true, force: true }));

  assert.equal(run('git', ['init', '-q', repository]).status, 0);
  assert.equal(run('git', ['-C', repository, 'config', 'user.name', 'HMG Test']).status, 0);
  assert.equal(
    run('git', ['-C', repository, 'config', 'user.email', 'test@hmg.invalid']).status,
    0,
  );

  assert.equal(
    run('git', ['-C', repository, 'commit', '-q', '--allow-empty', '-m', 'chore: initialize fixture']).status,
    0,
  );
  const baseSha = run('git', ['-C', repository, 'rev-parse', 'HEAD']).stdout.trim();

  assert.equal(
    run('git', ['-C', repository, 'commit', '-q', '--allow-empty', '-m', 'feat: add first fixture']).status,
    0,
  );
  assert.equal(
    run('git', ['-C', repository, 'commit', '-q', '--allow-empty', '-m', 'fix: add second fixture']).status,
    0,
  );
  const validHeadSha = run('git', ['-C', repository, 'rev-parse', 'HEAD']).stdout.trim();

  const validRange = run('bash', [lintRange, repository, baseSha, validHeadSha]);
  assert.equal(validRange.status, 0, validRange.stdout || validRange.stderr);
  assert.equal((validRange.stdout.match(/Linting commit /g) ?? []).length, 2);

  assert.equal(
    run('git', ['-C', repository, 'commit', '-q', '--allow-empty', '-m', 'fix: 修复 third fixture']).status,
    0,
  );
  const invalidHeadSha = run('git', ['-C', repository, 'rev-parse', 'HEAD']).stdout.trim();
  const invalidRange = run('bash', [lintRange, repository, validHeadSha, invalidHeadSha]);
  assert.notEqual(invalidRange.status, 0);
  assert.match(`${invalidRange.stdout}\n${invalidRange.stderr}`, /subject-no-han/);

  const invalidSha = run('bash', [lintRange, repository, 'HEAD', invalidHeadSha]);
  assert.equal(invalidSha.status, 2);
  assert.match(invalidSha.stderr, /full 40-character lowercase hexadecimal commit SHA/);
});
