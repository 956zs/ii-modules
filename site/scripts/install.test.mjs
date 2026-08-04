import assert from 'node:assert/strict'
import test from 'node:test'
import ts from 'typescript'
import { createHash } from 'node:crypto'
import { access, chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { constants } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import vm from 'node:vm'

const installerPath = fileURLToPath(new URL('../public/install-iimod.sh', import.meta.url))
const testPayload = 'verified iimod test binary\n'

async function loadInstallExports() {
  const source = await readFile(new URL('../src/lib/install.ts', import.meta.url), 'utf8')
  const transpiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2023 },
  }).outputText
  const body = transpiled.replaceAll('export ', '')
  const context = vm.createContext({})
  vm.runInContext(
    `${body}; globalThis.installExports = { INSTALL_IIMOD_COMMAND, installCommand }`,
    context,
  )
  return context.installExports
}

async function writeExecutable(path, source) {
  await writeFile(path, source)
  await chmod(path, 0o755)
}

async function runInstaller(checksum) {
  const root = await mkdtemp(join(tmpdir(), 'install-iimod-test-'))
  const binDir = join(root, 'bin')
  const downloadDir = join(root, 'download')
  const sudoLog = join(root, 'sudo.log')
  await writeExecutable(
    join(root, 'setup.sh'),
    `#!/bin/sh\nmkdir -p "$1"\n`,
  )
  spawnSync('sh', [join(root, 'setup.sh'), binDir], { encoding: 'utf8' })
  await writeExecutable(
    join(binDir, 'curl'),
    `#!/bin/sh
set -eu
output=''
url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  *.sha256) printf '%s\\n' "$MOCK_CHECKSUM" > "$output" ;;
  *) printf '%s' "$MOCK_PAYLOAD" > "$output" ;;
esac
`,
  )
  await writeExecutable(
    join(binDir, 'mktemp'),
    `#!/bin/sh
set -eu
[ "$1" = '-d' ]
mkdir "$MOCK_TMP_DIR"
printf '%s\\n' "$MOCK_TMP_DIR"
`,
  )
  await writeExecutable(
    join(binDir, 'sudo'),
    `#!/bin/sh
printf '%s\\n' "$*" > "$MOCK_SUDO_LOG"
`,
  )

  const result = spawnSync('sh', [installerPath], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${binDir}:${process.env.PATH}`,
      MOCK_CHECKSUM: checksum,
      MOCK_PAYLOAD: testPayload,
      MOCK_SUDO_LOG: sudoLog,
      MOCK_TMP_DIR: downloadDir,
    },
  })

  return { downloadDir, result, root, sudoLog }
}

test('displayed CLI install command is short and uses the first-party HTTPS installer', async () => {
  const { INSTALL_IIMOD_COMMAND } = await loadInstallExports()

  assert.equal(
    INSTALL_IIMOD_COMMAND,
    "curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 https://ii.n1cat.xyz/install-iimod.sh | sh",
  )
  assert.equal(INSTALL_IIMOD_COMMAND.split('\n').length, 1)
  assert.doesNotMatch(INSTALL_IIMOD_COMMAND, /sudo/)
  assert.doesNotMatch(INSTALL_IIMOD_COMMAND, /downloads\/iimod\/linux-x86_64/)
})

test('installer is valid POSIX shell and preserves secure installation stages', async () => {
  const source = await readFile(installerPath, 'utf8')
  const stages = [
    'This will install the official iimod binary to ${destination}.',
    'SHA256 checksum will be verified',
    'sudo may request your password',
    "tmp_dir=\"$(mktemp -d)\"",
    "trap 'rm -rf \"$tmp_dir\"' EXIT HUP INT TERM",
    'Downloading iimod and checksum',
    "checksum=\"$(cat \"$checksum_path\")\"",
    'sha256sum --check --status',
    'Checksum verified.',
    'sudo install -m 0755 "$binary_path" "$destination"',
  ]

  let previousIndex = -1
  for (const stage of stages) {
    const stageIndex = source.indexOf(stage)
    assert.ok(stageIndex > previousIndex, `${stage} must appear after the previous stage`)
    previousIndex = stageIndex
  }

  assert.equal(spawnSync('sh', ['-n', installerPath]).status, 0)
  assert.match(source, /download_url='https:\/\/ii\.n1cat\.xyz\/downloads\/iimod\/linux-x86_64'/)
  assert.match(source, /curl --fail --location --proto '=https' --tlsv1\.2/)
  assert.match(source, /\[ "\$\{#checksum\}" -ne 64 \]/)
  assert.doesNotMatch(source, /curl[^|\n]*\|\s*sudo/)
})

test('installer verifies a valid download before invoking sudo and cleans up', async (t) => {
  const checksum = createHash('sha256').update(testPayload).digest('hex')
  const run = await runInstaller(checksum)
  t.after(() => rm(run.root, { recursive: true, force: true }))

  assert.equal(run.result.status, 0, run.result.stderr)
  assert.match(run.result.stdout, /Checksum verified\./)
  assert.match(run.result.stdout, /Installing iimod to \/usr\/local\/bin\/iimod; sudo may now request your password/)
  assert.equal(
    await readFile(run.sudoLog, 'utf8'),
    `install -m 0755 ${run.downloadDir}/iimod /usr/local/bin/iimod\n`,
  )
  await assert.rejects(access(run.downloadDir, constants.F_OK))
})

test('installer fails closed and never invokes sudo when checksum mismatches', async (t) => {
  const run = await runInstaller('0'.repeat(64))
  t.after(() => rm(run.root, { recursive: true, force: true }))

  assert.notEqual(run.result.status, 0)
  assert.match(run.result.stderr, /Checksum verification failed; installation stopped\./)
  await assert.rejects(access(run.sudoLog, constants.F_OK))
  await assert.rejects(access(run.downloadDir, constants.F_OK))
})

test('Hero uses the shared CLI install command', async () => {
  const source = await readFile(new URL('../src/components/hero.tsx', import.meta.url), 'utf8')

  assert.match(source, /import \{ INSTALL_IIMOD_COMMAND, installCommand \} from '@\/lib\/install'/)
  assert.doesNotMatch(source, /releases\/latest\/download\/iimod-linux-x86_64/)
})

test('bilingual install docs show the shared short command and security tradeoff', async () => {
  const command = "curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 https://ii.n1cat.xyz/install-iimod.sh | sh"
  const docs = await Promise.all([
    readFile(new URL('../docs/guide/install.md', import.meta.url), 'utf8'),
    readFile(new URL('../docs/en/guide/install.md', import.meta.url), 'utf8'),
  ])

  for (const source of docs) {
    assert.match(source, new RegExp(command.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
    assert.match(source, /\/usr\/local\/bin\/iimod/)
    assert.match(source, /SHA256/)
    assert.match(source, /sudo/)
    assert.match(source, /TLS/)
  }
})

test('installCommand adds patch consent only for Tier B modules', async () => {
  const { installCommand } = await loadInstallExports()
  assert.equal(installCommand('https://example.test/a.iimod', false), 'iimod install https://example.test/a.iimod')
  assert.equal(
    installCommand('https://example.test/b.iimod', true),
    'iimod install https://example.test/b.iimod --allow-patches',
  )
})
