import assert from 'node:assert/strict'
import test from 'node:test'
import ts from 'typescript'
import { createHash } from 'node:crypto'
import { access, chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { constants } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
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

async function runBootstrap(mode) {
  const { INSTALL_IIMOD_COMMAND } = await loadInstallExports()
  const root = await mkdtemp(join(tmpdir(), 'install-iimod-bootstrap-test-'))
  const binDir = join(root, 'bin')
  const marker = join(root, 'installer-ran')
  await writeExecutable(join(root, 'setup.sh'), `#!/bin/sh\nmkdir -p "$1"\n`)
  spawnSync('sh', [join(root, 'setup.sh'), binDir], { encoding: 'utf8' })
  await writeExecutable(
    join(binDir, 'curl'),
    `#!/bin/sh
set -eu
case "$MOCK_CURL_MODE" in
  success)
    printf '%s\\n' '#!/bin/sh' 'printf executed > "$INSTALLER_MARKER"'
    ;;
  failure)
    exit 7
    ;;
  empty)
    exit 0
    ;;
  truncated)
    printf '%s\\n' '#!/bin/sh' 'printf executed > "$INSTALLER_MARKER"'
    exit 18
    ;;
  http-error)
    printf '%s\\n' '#!/bin/sh' 'printf executed > "$INSTALLER_MARKER"'
    exit 22
    ;;
  *)
    exit 64
    ;;
esac
`,
  )

  const result = spawnSync('sh', ['-c', INSTALL_IIMOD_COMMAND], {
    encoding: 'utf8',
    env: {
      ...process.env,
      INSTALLER_MARKER: marker,
      MOCK_CURL_MODE: mode,
      PATH: `${binDir}:${process.env.PATH}`,
    },
  })

  return { marker, result, root }
}

async function runInstaller(checksum, platform = { system: 'Linux', machine: 'x86_64' }) {
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
    join(binDir, 'uname'),
    `#!/bin/sh
case "$1" in
  -s) printf '%s\\n' "$MOCK_UNAME_SYSTEM" ;;
  -m) printf '%s\\n' "$MOCK_UNAME_MACHINE" ;;
  *) exit 2 ;;
esac
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
      MOCK_UNAME_MACHINE: platform.machine,
      MOCK_UNAME_SYSTEM: platform.system,
    },
  })

  return { downloadDir, result, root, sudoLog }
}

async function waitForFile(path, child, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    try {
      await access(path, constants.F_OK)
      return
    } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
    if (child.exitCode !== null) {
      throw new Error(`installer exited before reaching blocking point: ${child.exitCode}`)
    }
    await new Promise((resolve) => setTimeout(resolve, 10))
  }
  throw new Error(`timed out waiting for ${path}`)
}

async function runInterruptedInstaller(signal) {
  const root = await mkdtemp(join(tmpdir(), 'install-iimod-signal-test-'))
  const binDir = join(root, 'bin')
  const downloadDir = join(root, 'download')
  const readyMarker = join(root, 'curl-ready')
  const sudoLog = join(root, 'sudo.log')
  await mkdir(binDir)
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
: > "$MOCK_CURL_READY"
sleep 1
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
    join(binDir, 'uname'),
    `#!/bin/sh
case "$1" in
  -s) printf '%s\\n' Linux ;;
  -m) printf '%s\\n' x86_64 ;;
  *) exit 2 ;;
esac
`,
  )
  await writeExecutable(
    join(binDir, 'sudo'),
    `#!/bin/sh
printf '%s\\n' "$*" > "$MOCK_SUDO_LOG"
`,
  )

  const child = spawn('sh', [installerPath], {
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      MOCK_CHECKSUM: createHash('sha256').update(testPayload).digest('hex'),
      MOCK_CURL_READY: readyMarker,
      MOCK_PAYLOAD: testPayload,
      MOCK_SUDO_LOG: sudoLog,
      MOCK_TMP_DIR: downloadDir,
      PATH: `${binDir}:${process.env.PATH}`,
    },
  })
  const stdout = []
  const stderr = []
  child.stdout.on('data', (chunk) => stdout.push(chunk))
  child.stderr.on('data', (chunk) => stderr.push(chunk))

  try {
    await waitForFile(readyMarker, child)
    process.kill(child.pid, signal)
    const result = await new Promise((resolve, reject) => {
      child.once('error', reject)
      child.once('close', (code, closeSignal) => resolve({ code, signal: closeSignal }))
    })
    return {
      downloadDir,
      result: {
        ...result,
        stderr: Buffer.concat(stderr).toString('utf8'),
        stdout: Buffer.concat(stdout).toString('utf8'),
      },
      root,
      sudoLog,
    }
  } catch (error) {
    try {
      process.kill(-child.pid, 'SIGKILL')
    } catch (killError) {
      if (killError.code !== 'ESRCH') throw killError
    }
    await new Promise((resolve) => child.once('close', resolve))
    await rm(root, { recursive: true, force: true })
    throw error
  }
}

test('displayed CLI install command stays concise and uses the first-party HTTPS installer', async () => {
  const { INSTALL_IIMOD_COMMAND } = await loadInstallExports()

  assert.equal(
    INSTALL_IIMOD_COMMAND,
    `sh -c 'script=$(curl --fail --location --silent --show-error https://ii.n1cat.xyz/install-iimod.sh) && [ -n "$script" ] && sh -c "$script"'`,
  )
  assert.equal(INSTALL_IIMOD_COMMAND.split('\n').length, 1)
  assert.match(INSTALL_IIMOD_COMMAND, /^sh -c 'script=\$\(curl --fail --location /)
  assert.doesNotMatch(INSTALL_IIMOD_COMMAND, /\|\s*sh/)
  assert.doesNotMatch(INSTALL_IIMOD_COMMAND, /sudo/)
  assert.doesNotMatch(INSTALL_IIMOD_COMMAND, /downloads\/iimod\/linux-x86_64/)
})

test('bootstrap executes a complete successful HTTPS response', async (t) => {
  const run = await runBootstrap('success')
  t.after(() => rm(run.root, { recursive: true, force: true }))

  assert.equal(run.result.status, 0, run.result.stderr)
  assert.equal(await readFile(run.marker, 'utf8'), 'executed')
})

test('bootstrap rejects failed, empty, truncated, and HTTP error responses before execution', async (t) => {
  for (const mode of ['failure', 'empty', 'truncated', 'http-error']) {
    await t.test(mode, async (t) => {
      const run = await runBootstrap(mode)
      t.after(() => rm(run.root, { recursive: true, force: true }))

      assert.notEqual(run.result.status, 0, `${mode} unexpectedly succeeded`)
      await assert.rejects(access(run.marker, constants.F_OK), `${mode} executed installer content`)
    })
  }
})

test('installer is valid POSIX shell and preserves secure installation stages', async () => {
  const source = await readFile(installerPath, 'utf8')
  const stages = [
    'This will install the official iimod binary to ${destination}.',
    'SHA256 checksum will be verified',
    'sudo may request your password',
    "tmp_dir=\"$(mktemp -d)\"",
    'trap cleanup EXIT',
    "trap 'exit 129' HUP",
    "trap 'exit 130' INT",
    "trap 'exit 143' TERM",
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

test('installer rejects unsupported platforms before download or sudo', async (t) => {
  const checksum = createHash('sha256').update(testPayload).digest('hex')
  const run = await runInstaller(checksum, { system: 'Linux', machine: 'aarch64' })
  t.after(() => rm(run.root, { recursive: true, force: true }))

  assert.notEqual(run.result.status, 0)
  assert.match(run.result.stderr, /Unsupported platform: Linux\/aarch64/)
  await assert.rejects(access(run.sudoLog, constants.F_OK))
  await assert.rejects(access(run.downloadDir, constants.F_OK))
})

test('installer handles HUP, INT, and TERM by cleaning up and stopping before sudo', async (t) => {
  const expectedCodes = { SIGHUP: 129, SIGINT: 130, SIGTERM: 143 }

  for (const [signal, expectedCode] of Object.entries(expectedCodes)) {
    await t.test(signal, async (t) => {
      const run = await runInterruptedInstaller(signal)
      t.after(() => rm(run.root, { recursive: true, force: true }))

      assert.equal(run.result.code, expectedCode, run.result.stderr)
      assert.equal(run.result.signal, null)
      await assert.rejects(access(run.downloadDir, constants.F_OK))
      await assert.rejects(access(run.sudoLog, constants.F_OK))
    })
  }
})

test('Hero uses the shared CLI install command', async () => {
  const source = await readFile(new URL('../src/components/hero.tsx', import.meta.url), 'utf8')

  assert.match(source, /import \{ INSTALL_IIMOD_COMMAND, installCommand \} from '@\/lib\/install'/)
  assert.doesNotMatch(source, /releases\/latest\/download\/iimod-linux-x86_64/)
})

test('bilingual install docs show the shared short command and security tradeoff', async () => {
  const { INSTALL_IIMOD_COMMAND: command } = await loadInstallExports()
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
