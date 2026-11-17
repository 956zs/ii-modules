import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const moduleRoot = new URL('../', import.meta.url)

async function manifest() {
  return JSON.parse(await readFile(new URL('module.json', moduleRoot), 'utf8'))
}

test('inhibitor is re-created once its surface has mapped', async () => {
  const m = await manifest()
  const rearm = m.patches.find((patch) => patch.anchor === '        id: idleInhibitor')
  assert.ok(rearm, 'Idle.qml rearm patch is present')
  assert.equal(rearm.file, 'services/Idle.qml')
  assert.equal(rearm.op, 'insert-after')
  assert.ok(
    m.compat.probes.some((probe) => probe.pattern === rearm.anchor),
    'the rearm anchor is probed',
  )

  // Hyprland only checks visibility when the inhibitor is created, so it must
  // be toggled off and on after the surface maps.
  assert.match(rearm.content, /idleInhibitor\.enabled = false;\s+idleInhibitor\.enabled = true;/)
  assert.match(rearm.content, /if \(!idleInhibitor\.enabled\)\s+return;/)

  // Toggling enabled re-emits windowChanged; a timer whose running state is
  // bound through idleInhibitor.window restarts itself forever.
  assert.match(rearm.content, /function onBackingWindowVisibleChanged\(\)/)
  assert.match(rearm.content, /idleModesRearm\.restart\(\)/)
  assert.doesNotMatch(rearm.content, /running:/)
  assert.doesNotMatch(rearm.content, /repeat: true/)
})

test('modes keep the stock persisted inhibit flag in sync', async () => {
  const m = await manifest()
  const state = m.patches.find((patch) => patch.anchor === 'inhibit: false')
  assert.match(state.content, /root\.inhibit = next === "full";/)
  assert.match(state.content, /Persistent\.states\.idle\.inhibit = root\.inhibit;/)
  assert.match(state.content, /\["off", "half", "full"\]\.includes\(mode\) \? mode : "off"/)
})

// ---- idle-mode-gate.sh: androlink keep-awake ----
//
// Every run uses its own temporary HOME, XDG dirs and power-supply tree, and a
// PATH whose first entry holds fake systemctl/loginctl that only record their
// argv, so no test can suspend this machine. A fake hyprctl reports the
// screens (all off unless a test says otherwise) and a fake sleep returns at
// once, counting the gate's waits and running the test's changes for that
// wait; with a `sleep.block` file it really sleeps, so a test can stop it.

const gate = fileURLToPath(new URL('idle-mode-gate.sh', moduleRoot))
const which = (tool) => spawnSync('sh', ['-c', `command -v ${tool}`], { encoding: 'utf8' }).stdout.trim()
const hasJq = spawnSync('jq', ['--version']).status === 0
const hasFlock = which('flock') !== ''
const realSleep = which('sleep')
// gateTest(name, [options], fn)
const gateTest = (name, ...rest) => {
  const fn = rest.pop()
  return test(name, { ...rest[0], skip: hasJq && hasFlock ? false : 'jq or flock is not installed' }, fn)
}

function sandbox() {
  const root = mkdtempSync(join(tmpdir(), 'idle-modes-gate-'))
  const dirs = {
    root,
    bin: join(root, 'bin'),
    config: join(root, 'config'),
    runtime: join(root, 'runtime'),
    power: join(root, 'power'),
  }
  for (const dir of [dirs.bin, join(dirs.config, 'illogical-impulse/modules'), join(dirs.runtime, 'androlink'), dirs.power])
    mkdirSync(dir, { recursive: true })
  for (const tool of ['systemctl', 'loginctl']) {
    const fake = join(dirs.bin, tool)
    writeFileSync(fake, `#!/bin/sh\nprintf '%s %s\\n' "${tool}" "$*" >> "${join(root, 'suspend.log')}"\n[ -f "${join(root, `${tool}.fail`)}" ] && exit 1\nexit 0\n`)
    chmodSync(fake, 0o755)
  }
  writeFileSync(join(dirs.bin, 'hyprctl'), [
    '#!/bin/sh',
    `[ -f "${root}/hyprctl.fail" ] && exit 1`,
    `if [ -f "${root}/monitors.json" ]; then cat "${root}/monitors.json"; else echo '[{"name":"eDP-1","dpmsStatus":false}]'; fi`,
    '',
  ].join('\n'), { mode: 0o755 })
  writeFileSync(join(dirs.bin, 'sleep'), [
    '#!/bin/sh',
    `n=$(( $(cat "${root}/sleeps" 2>/dev/null || echo 0) + 1 ))`,
    `echo "$n" > "${root}/sleeps"`,
    `printf '%s\\n' "$1" >> "${root}/sleep.log"`,
    `echo "$$" >> "${root}/sleep.pids"`,
    `[ -x "${root}/on-sleep-$n" ] && "${root}/on-sleep-$n"`,
    `[ -f "${root}/sleep.block" ] && exec "${realSleep}" 20`,
    'exit 0',
    '',
  ].join('\n'), { mode: 0o755 })
  return dirs
}

const statusFile = (box) => join(box.runtime, 'androlink/status.json')
const configFile = (box) => join(box.config, 'illogical-impulse/modules/idle_modes.json')
const holdFile = (box) => join(box.runtime, 'idle-mode-gate.pid')
const monitorsFile = (box) => join(box.root, 'monitors.json')

// Changes made by the fake sleep of the gate's n-th wait, before it checks
// again: { path: content } writes the file, { path: null } removes it.
function onSleep(box, n, changes) {
  const lines = ['#!/bin/sh']
  Object.entries(changes).forEach(([dest, content], i) => {
    if (content === null) {
      lines.push(`rm -f '${dest}'`)
      return
    }
    const staged = join(box.root, `stage-${n}-${i}`)
    writeFileSync(staged, typeof content === 'string' ? content : JSON.stringify(content))
    lines.push(`cp '${staged}' '${dest}'`)
  })
  writeFileSync(join(box.root, `on-sleep-${n}`), `${lines.join('\n')}\n`, { mode: 0o755 })
}

function sleepLog(box) {
  try {
    return readFileSync(join(box.root, 'sleep.log'), 'utf8')
  } catch {
    return ''
  }
}

const lines = (out) => out.stdout.split('\n').filter(Boolean)

function cleanup(box) {
  rmSync(box.root, { recursive: true, force: true })
}

function setConfig(box, options) {
  writeFileSync(join(box.config, 'illogical-impulse/modules/idle_modes.json'), typeof options === 'string' ? options : JSON.stringify(options))
}

function setStatus(box, status) {
  writeFileSync(join(box.runtime, 'androlink/status.json'), typeof status === 'string' ? status : JSON.stringify(status))
}

const nowSecs = () => Math.floor(Date.now() / 1000)

function status(fields = {}) {
  return { version: 1, updated: nowSecs(), running: true, keep_awake: ['mic'], phones: [], ...fields }
}

// files: { name: { type, online, capacity, scope } }; a null value skips that file.
function setPower(box, supplies) {
  for (const [name, files] of Object.entries(supplies)) {
    const dir = join(box.power, name)
    mkdirSync(dir, { recursive: true })
    for (const [file, value] of Object.entries(files)) {
      if (value !== null)
        writeFileSync(join(dir, file), `${value}\n`)
    }
  }
}

const onAc = { ADP1: { type: 'Mains', online: 1 }, BAT0: { type: 'Battery', capacity: 50 } }
const onBattery = (capacity) => ({ ADP1: { type: 'Mains', online: 0 }, BAT0: { type: 'Battery', capacity } })

function gateEnv(box, env) {
  return {
    PATH: `${box.bin}:${dirname(which('jq'))}:/usr/bin:/bin`,
    HOME: box.root,
    XDG_CONFIG_HOME: box.config,
    XDG_RUNTIME_DIR: box.runtime,
    IDLE_MODES_POWER_SUPPLY_DIR: box.power,
    ...env,
  }
}

function readSuspendLog(box) {
  try {
    return readFileSync(join(box.root, 'suspend.log'), 'utf8')
  } catch {
    return ''
  }
}

// A gate run in the background; `done` resolves once it and every process
// holding its output (a sleep it left behind) have exited.
function startGate(box, args = ['suspend'], env = {}) {
  const child = spawn('bash', [gate, ...args], { env: gateEnv(box, env) })
  let stdout = ''
  let stderr = ''
  child.stdout.on('data', (chunk) => { stdout += chunk })
  child.stderr.on('data', (chunk) => { stderr += chunk })
  const done = new Promise((resolve) => child.on('close', (status) => resolve({ status, stdout, stderr })))
  return { child, done, stdout: () => stdout }
}

async function waitFor(what, predicate, ms = 5000) {
  const deadline = Date.now() + ms
  while (!predicate()) {
    if (Date.now() > deadline)
      throw new Error(`timed out waiting for ${what}`)
    await new Promise((resolve) => setTimeout(resolve, 20))
  }
}

function readHold(box) {
  try {
    return readFileSync(holdFile(box), 'utf8').trim()
  } catch {
    return ''
  }
}

// Resolves with the result, or rejects when the gate is still running after ms.
function within(ms, promise, what) {
  let timer
  return Promise.race([
    promise.finally(() => clearTimeout(timer)),
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${what} still running after ${ms} ms`)), ms) }),
  ])
}

function runGate(box, args = ['suspend', '--dry-run'], env = {}) {
  const out = spawnSync('bash', [gate, ...args], { encoding: 'utf8', env: gateEnv(box, env), timeout: 30000 })
  return { status: out.status, stdout: out.stdout, stderr: out.stderr, suspendLog: readSuspendLog(box) }
}

function decide(box, args) {
  const out = runGate(box, args)
  assert.equal(out.status, 0, out.stderr)
  assert.equal(out.stdout.split('\n').filter(Boolean).length, 1, `one log line: ${out.stdout}`)
  return out.stdout.trim()
}

gateTest('gate: half and full never suspend, whatever androlink says', () => {
  const box = sandbox()
  try {
    setPower(box, onBattery(5))
    setStatus(box, status({ keep_awake: [] }))
    for (const mode of ['half', 'full']) {
      setConfig(box, { mode })
      assert.equal(decide(box), `idle-mode-gate: mode ${mode}, not suspending`)
      assert.equal(decide(box, ['suspend']), `idle-mode-gate: mode ${mode}, not suspending`)
    }
    assert.equal(runGate(box, ['suspend']).suspendLog, '')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: a fresh keep_awake on AC holds the idle suspend', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status({ keep_awake: ['transfer', 'mic'] }))
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink keep_awake mic,transfer, on AC, not suspending')
    assert.equal(sleepLog(box), '', 'a dry run never waits')
    assert.equal(existsSync(holdFile(box)), false)
    // A real run waits; here the screen comes on before the first check.
    onSleep(box, 1, { [monitorsFile(box)]: [{ name: 'eDP-1', dpmsStatus: true }] })
    const out = runGate(box, ['suspend'])
    assert.equal(out.status, 0, out.stderr)
    assert.deepEqual(lines(out), [
      'idle-mode-gate: mode off, androlink keep_awake mic,transfer, on AC, not suspending, checking again every 60 s for up to 120 min',
      'idle-mode-gate: a screen is on, not suspending',
    ])
    assert.equal(out.suspendLog, '', 'never calls systemctl while held')
    assert.equal(existsSync(holdFile(box)), false, 'the hold file is removed')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: on battery the floor decides, at the floor still holds', () => {
  const box = sandbox()
  try {
    setStatus(box, status({ keep_awake: ['webcam'] }))
    setPower(box, onBattery(35))
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink keep_awake webcam, battery 35% (floor 20%), not suspending')
    setPower(box, onBattery(20))
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink keep_awake webcam, battery 20% (floor 20%), not suspending')
    setPower(box, onBattery(19))
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink keep_awake webcam, battery 19% below floor 20%, would suspend')
    setPower(box, onBattery(0))
    assert.match(decide(box), /battery 0% below floor 20%, would suspend$/)
  } finally {
    cleanup(box)
  }
})

gateTest('gate: the battery floor option is read, rounded and clamped', () => {
  const box = sandbox()
  try {
    setStatus(box, status())
    setPower(box, onBattery(35))
    setConfig(box, { mode: 'off', keepAwakeBatteryFloor: 40 })
    assert.match(decide(box), /battery 35% below floor 40%, would suspend$/)
    setConfig(box, { keepAwakeBatteryFloor: 34.6 })
    assert.match(decide(box), /battery 35% \(floor 35%\), not suspending$/)
    setConfig(box, { keepAwakeBatteryFloor: 0 })
    setPower(box, onBattery(0))
    assert.match(decide(box), /battery 0% \(floor 0%\), not suspending$/)
    setConfig(box, { keepAwakeBatteryFloor: -5 })
    assert.match(decide(box), /\(floor 0%\), not suspending$/)
    setPower(box, onBattery(100))
    setConfig(box, { keepAwakeBatteryFloor: 150 })
    assert.match(decide(box), /battery 100% \(floor 100%\), not suspending$/)
    setPower(box, onBattery(99))
    assert.match(decide(box), /battery 99% below floor 100%, would suspend$/)
    for (const junk of [{ keepAwakeBatteryFloor: '40' }, { keepAwakeBatteryFloor: null }, { keepAwakeBatteryFloor: true }, '[1,2]', 'not json', '']) {
      setConfig(box, junk)
      assert.match(decide(box), /battery 99% \(floor 20%\), not suspending$/, JSON.stringify(junk))
    }
  } finally {
    cleanup(box)
  }
})

gateTest('gate: missing, invalid and stopped status files keep the plain mode behaviour', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink status missing, would suspend')
    const invalid = [
      '', 'not json', '[]', 'null', '42', '{"version":1}',
      JSON.stringify(status({ version: 2 })), JSON.stringify(status({ version: '1' })),
      JSON.stringify(status({ updated: 'now' })), JSON.stringify(status({ updated: -1 })),
      JSON.stringify(status({ updated: 1e12 })), JSON.stringify(status({ keep_awake: 'mic' })),
      JSON.stringify(status({ keep_awake: { mic: true } })),
      `${JSON.stringify(status())}\n${JSON.stringify(status())}`,
      JSON.stringify(status({ padding: 'x'.repeat(70000) })),
    ]
    for (const text of invalid) {
      setStatus(box, text)
      assert.equal(decide(box), 'idle-mode-gate: mode off, androlink status invalid, would suspend', text.slice(0, 80))
    }
    for (const running of [false, 'true', 1]) {
      setStatus(box, status({ running }))
      assert.equal(decide(box), 'idle-mode-gate: mode off, androlink status stopped, would suspend', String(running))
    }
  } finally {
    cleanup(box)
  }
})

gateTest('gate: a relative XDG_RUNTIME_DIR reads no status file', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status())
    for (const runtime of ['relative/dir', '']) {
      const out = runGate(box, ['suspend', '--dry-run'], { XDG_RUNTIME_DIR: runtime })
      assert.equal(out.stdout.trim(), 'idle-mode-gate: mode off, androlink status missing, would suspend')
    }
  } finally {
    cleanup(box)
  }
})

gateTest('gate: only a fresh status file counts', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    // Margins of several seconds: the script reads the clock a moment later.
    setStatus(box, status({ updated: nowSecs() - 80 }))
    assert.match(decide(box), /keep_awake mic, on AC, not suspending$/)
    setStatus(box, status({ updated: nowSecs() - 100 }))
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink status stale, would suspend')
    // A clock behind androlink's by up to one heartbeat (a third) is fine.
    setStatus(box, status({ updated: nowSecs() + 20 }))
    assert.match(decide(box), /not suspending$/)
    setStatus(box, status({ updated: nowSecs() + 40 }))
    assert.match(decide(box), /androlink status stale, would suspend$/)
    // Fractional seconds are fine.
    setStatus(box, status({ updated: nowSecs() - 5.5 }))
    assert.match(decide(box), /not suspending$/)
    // A longer window from the module option, clamped to 15–3600 s.
    setConfig(box, { keepAwakeMaxAgeSecs: 300 })
    setStatus(box, status({ updated: nowSecs() - 200 }))
    assert.match(decide(box), /not suspending$/)
    setConfig(box, { keepAwakeMaxAgeSecs: 1 })
    setStatus(box, status({ updated: nowSecs() - 10 }))
    assert.match(decide(box), /not suspending$/, 'clamped up to 15 s')
    setStatus(box, status({ updated: nowSecs() - 25 }))
    assert.match(decide(box), /androlink status stale, would suspend$/)
  } finally {
    cleanup(box)
  }
})

gateTest('gate: an empty, missing or null keep_awake never holds the suspend', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    const { keep_awake: _unused, ...withoutField } = status()
    for (const text of [status({ keep_awake: [] }), withoutField, status({ keep_awake: null }), status({ keep_awake: [5, '', 'Mic', 'a b', 'x'.repeat(33)] })]) {
      setStatus(box, text)
      assert.equal(decide(box), 'idle-mode-gate: mode off, androlink keep_awake none, would suspend', JSON.stringify(text.keep_awake))
    }
  } finally {
    cleanup(box)
  }
})

gateTest('gate: reason codes are sorted, unique and code-shaped in the log', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status({ keep_awake: ['transfer', 'mic', 'mic', 'webcam', 'mic\n', 'a\nb', 'Evil Code', '\u001b[31m', 7, null] }))
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink keep_awake mic,transfer,webcam, on AC, not suspending')
    setStatus(box, status({ keep_awake: Array.from({ length: 12 }, (_, i) => `r${String(i).padStart(2, '0')}`) }))
    assert.match(decide(box), /keep_awake r00,r01,r02,r03,r04,r05,r06,r07, on AC/, 'at most 8 codes')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: power sources are read from the power supply class', () => {
  const box = sandbox()
  try {
    setStatus(box, status())
    // No supply at all: a desktop on mains.
    assert.match(decide(box), /keep_awake mic, no battery, not suspending$/)
    // Peripheral batteries and USB-C partner supplies don't count.
    setPower(box, {
      'hid-mouse-battery': { type: 'Battery', scope: 'Device', capacity: 90 },
      'ucsi-source-psy-USBC000:001': { type: 'USB', scope: 'Device', online: 1 },
    })
    assert.match(decide(box), /no battery, not suspending$/)
    setPower(box, { BAT1: { type: 'Battery', capacity: 10 } })
    assert.match(decide(box), /battery 10% below floor 20%, would suspend$/, 'the mouse at 90% is ignored')
    // A Mains supply going online wins over a low battery.
    setPower(box, { ACAD: { type: 'Mains', online: 1 } })
    assert.match(decide(box), /on AC, not suspending$/)
  } finally {
    cleanup(box)
  }
})

gateTest('gate: several batteries average; unreadable and type-less supplies are handled', () => {
  const box = sandbox()
  try {
    setStatus(box, status())
    setPower(box, { BAT0: { type: 'Battery', capacity: 30 }, BAT1: { type: 'Battery', capacity: 5 } })
    assert.match(decide(box), /battery 17% below floor 20%, would suspend$/)
    setPower(box, { BAT1: { capacity: 15 } })
    assert.match(decide(box), /battery 22% \(floor 20%\)/, 'the mean of 30 and 15, floored')
  } finally {
    cleanup(box)
  }
  const box2 = sandbox()
  try {
    setStatus(box2, status())
    // Unreadable or out-of-range capacity: the level is unknown, so the floor can't be met.
    setPower(box2, { BAT0: { type: 'Battery', capacity: null } })
    assert.equal(decide(box2), 'idle-mode-gate: mode off, androlink keep_awake mic, battery level unknown, would suspend')
    setPower(box2, { BAT0: { capacity: 'full' } })
    assert.match(decide(box2), /battery level unknown, would suspend$/)
    setPower(box2, { BAT0: { capacity: 101 } })
    assert.match(decide(box2), /battery level unknown, would suspend$/)
    // No `type` file: names decide (ADP*, AC*, ACAD* are AC; BAT* a battery).
    setPower(box2, { BAT0: { type: null, capacity: 60 } })
    rmSync(join(box2.power, 'BAT0/type'))
    assert.match(decide(box2), /battery 60% \(floor 20%\), not suspending$/)
    setPower(box2, { ADP0: { online: 1 } })
    assert.match(decide(box2), /on AC, not suspending$/)
    setPower(box2, { ADP0: { online: 0 } })
    assert.match(decide(box2), /battery 60%/)
  } finally {
    cleanup(box2)
  }
})

// ---- II-GATE-2: a power supply class that can't be read is not a desktop ----

gateTest('gate: an unreadable or missing power supply class is unknown and lets the suspend run', () => {
  const box = sandbox()
  try {
    setStatus(box, status())
    const run = (dir) => runGate(box, ['suspend', '--dry-run'], { IDLE_MODES_POWER_SUPPLY_DIR: dir }).stdout.trim()
    // Read and empty: no battery and no mains, a desktop.
    assert.equal(run(box.power), 'idle-mode-gate: mode off, androlink keep_awake mic, no battery, not suspending')
    writeFileSync(join(box.root, 'a-file'), 'x\n')
    for (const dir of [join(box.root, 'no-such-dir'), join(box.root, 'a-file')])
      assert.equal(run(dir), 'idle-mode-gate: mode off, androlink keep_awake mic, battery level unknown, would suspend', dir)
    if (process.getuid?.() !== 0) {
      chmodSync(box.power, 0o000)
      try {
        assert.equal(run(box.power), 'idle-mode-gate: mode off, androlink keep_awake mic, battery level unknown, would suspend', 'unreadable')
      } finally {
        chmodSync(box.power, 0o755)
      }
      chmodSync(box.power, 0o644)
      try {
        assert.match(run(box.power), /battery level unknown, would suspend$/, 'readable but not searchable')
      } finally {
        chmodSync(box.power, 0o755)
      }
    }
  } finally {
    cleanup(box)
  }
})

gateTest('gate: an offline mains supply with no battery in sight is unknown', () => {
  const box = sandbox()
  try {
    setStatus(box, status())
    setPower(box, { ADP1: { type: 'Mains', online: 0 } })
    assert.equal(decide(box), 'idle-mode-gate: mode off, androlink keep_awake mic, battery level unknown, would suspend')
    setPower(box, { 'hid-mouse-battery': { type: 'Battery', scope: 'Device', capacity: 90 } })
    assert.match(decide(box), /battery level unknown, would suspend$/, 'a peripheral battery is no system battery')
    setPower(box, { ADP1: { online: null } })
    rmSync(join(box.power, 'ADP1/online'))
    assert.match(decide(box), /battery level unknown, would suspend$/, 'no online file')
    setPower(box, { ADP1: { online: 1 } })
    assert.match(decide(box), /on AC, not suspending$/, 'online mains with no battery is AC')
  } finally {
    cleanup(box)
  }
})

// ---- II-GATE-3: freshness follows the file's own heartbeat ----

gateTest("gate: the status file's heartbeat_s widens the freshness window to three heartbeats", () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    const check = (fields, expected, label) => {
      setStatus(box, status(fields))
      assert.match(decide(box), expected, label)
    }
    const held = /keep_awake mic, on AC, not suspending$/
    const stale = /androlink status stale, would suspend$/
    // 120 s heartbeats: 360 s old is still fresh, and up to one heartbeat ahead.
    check({ heartbeat_s: 120, updated: nowSecs() - 300 }, held, '300 s old, 120 s heartbeat')
    check({ heartbeat_s: 120, updated: nowSecs() - 370 }, stale, '370 s old, 120 s heartbeat')
    check({ heartbeat_s: 120, updated: nowSecs() + 110 }, held, '110 s ahead')
    check({ heartbeat_s: 120, updated: nowSecs() + 130 }, stale, '130 s ahead')
    // The top of androlink's range.
    check({ heartbeat_s: 3600, updated: nowSecs() - 10700 }, held, '3600 s heartbeat')
    check({ heartbeat_s: 3600, updated: nowSecs() - 10900 }, stale, 'past three 3600 s heartbeats')
    // Shorter heartbeats never narrow the option's window.
    check({ heartbeat_s: 10, updated: nowSecs() - 80 }, held, '10 s heartbeat keeps 90 s')
    check({ heartbeat_s: 1, updated: nowSecs() - 100 }, stale, '1 s heartbeat, past 90 s')
    check({ heartbeat_s: 31.5, updated: nowSecs() - 92 }, held, 'fractional: ceil(94.5) = 95 s')
    // Anything outside 1–3600, or not a number, is ignored: 90 s.
    for (const heartbeat of [0, 0.5, -30, 3601, 1e9, '120', null, true, [120], { s: 120 }]) {
      check({ heartbeat_s: heartbeat, updated: nowSecs() - 80 }, held, `ignored ${JSON.stringify(heartbeat)}, 80 s`)
      check({ heartbeat_s: heartbeat, updated: nowSecs() - 100 }, stale, `ignored ${JSON.stringify(heartbeat)}, 100 s`)
    }
    // A longer option wins over three short heartbeats.
    setConfig(box, { keepAwakeMaxAgeSecs: 300 })
    check({ heartbeat_s: 30, updated: nowSecs() - 200 }, held, 'option 300 s')
    check({ heartbeat_s: 30, updated: nowSecs() - 310 }, stale, 'past the 300 s option')
  } finally {
    cleanup(box)
  }
})

// ---- II-GATE-1 / F1: a hold is checked again while the PC stays idle ----

gateTest('gate: a held suspend checks again and suspends once keep_awake stays empty through the grace', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status({ keep_awake: ['transfer'] }))
    onSleep(box, 2, { [statusFile(box)]: status({ keep_awake: [] }) })
    const out = runGate(box, ['suspend'])
    assert.equal(out.status, 0, out.stderr)
    assert.deepEqual(lines(out), [
      'idle-mode-gate: mode off, androlink keep_awake transfer, on AC, not suspending, checking again every 60 s for up to 120 min',
      'idle-mode-gate: mode off, androlink keep_awake none for 45 s, suspending',
    ])
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    assert.equal(sleepLog(box), '60\n60\n45\n', 'held through the first check, empty at the second, suspended 45 s later')
    assert.equal(existsSync(holdFile(box)), false, 'the hold file is removed before the suspend')
  } finally {
    cleanup(box)
  }
})

// ---- N-GATE-1: a short keep_awake gap (a stream reconnecting) is no release ----

// Runs a held gate whose status file the fake sleep of each listed wait
// changes: steps[n] is the keep_awake list (or a whole status object) from
// wait n on. A screen on at wait `end` stops a gate that keeps holding.
function runSteps(box, steps, { options = {}, end } = {}) {
  setPower(box, onAc)
  setStatus(box, status({ keep_awake: ['mic'], heartbeat_s: 3600 }))
  setConfig(box, { mode: 'off', ...options })
  for (const [n, step] of Object.entries(steps))
    onSleep(box, Number(n), { [statusFile(box)]: Array.isArray(step) ? status({ keep_awake: step, heartbeat_s: 3600 }) : step })
  if (end)
    onSleep(box, end, { ...(steps[end] ? { [statusFile(box)]: status({ keep_awake: steps[end], heartbeat_s: 3600 }) } : {}), [monitorsFile(box)]: [{ name: 'eDP-1', dpmsStatus: true }] })
  const out = runGate(box, ['suspend'])
  assert.equal(out.status, 0, out.stderr)
  return { out, rest: lines(out).slice(1), sleeps: sleepLog(box).split('\n').filter(Boolean).map(Number) }
}

gateTest('gate: keep_awake empty at one check and back at the next does not suspend', () => {
  const box = sandbox()
  try {
    // The mic stream reconnects across the first check and is back for the
    // second (45 s later); the user comes back at the third.
    const { out, rest, sleeps } = runSteps(box, { 1: [], 2: ['mic'] }, { end: 3 })
    assert.deepEqual(rest, ['idle-mode-gate: a screen is on, not suspending'])
    assert.equal(out.suspendLog, '')
    assert.deepEqual(sleeps, [60, 45, 60], 'the grace check comes 45 s after the empty one, then the normal interval')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: a reason back during the grace starts the grace anew', () => {
  const box = sandbox()
  try {
    const { out, rest, sleeps } = runSteps(box, { 1: [], 2: ['webcam'], 3: [] })
    assert.deepEqual(rest, ['idle-mode-gate: mode off, androlink keep_awake none for 45 s, suspending'])
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    assert.deepEqual(sleeps, [60, 45, 60, 45])
  } finally {
    cleanup(box)
  }
})

gateTest('gate: with a grace longer than the interval, every check in it must be empty', () => {
  const box = sandbox()
  try {
    // 15 s checks, 45 s grace: empty at 15, 30, 45 and 60 s, suspended at 60.
    let r = runSteps(box, { 1: [] }, { options: { keepAwakeRecheckSecs: 15 } })
    assert.deepEqual(r.rest, ['idle-mode-gate: mode off, androlink keep_awake none for 45 s, suspending'])
    assert.deepEqual(r.sleeps, [15, 15, 15, 15])
    cleanup(box)
    // A reason back at the third check of the grace: no suspend at its end.
    Object.assign(box, sandbox())
    r = runSteps(box, { 1: [], 3: ['transfer'] }, { options: { keepAwakeRecheckSecs: 15 }, end: 5 })
    assert.deepEqual(r.rest, ['idle-mode-gate: a screen is on, not suspending'])
    assert.equal(r.out.suspendLog, '')
    assert.deepEqual(r.sleeps, [15, 15, 15, 15, 15])
    cleanup(box)
    // A grace that the interval does not divide: the last wait ends at it.
    Object.assign(box, sandbox())
    r = runSteps(box, { 1: [] }, { options: { keepAwakeReleaseGraceSecs: 100 } })
    assert.deepEqual(r.rest, ['idle-mode-gate: mode off, androlink keep_awake none for 100 s, suspending'])
    assert.deepEqual(r.sleeps, [60, 60, 40])
  } finally {
    cleanup(box)
  }
})

gateTest('gate: a stale, stopped, missing or invalid file or a low battery during the grace suspends at once', () => {
  const cases = [
    [status({ updated: nowSecs() - 1000 }), 'androlink status stale'],
    [status({ running: false, keep_awake: [] }), 'androlink status stopped'],
    [null, 'androlink status missing'],
    ['{"version":', 'androlink status invalid'],
  ]
  for (const [next, why] of cases) {
    const box = sandbox()
    try {
      const { out, rest, sleeps } = runSteps(box, { 1: [], 2: next })
      assert.deepEqual(rest, [`idle-mode-gate: mode off, ${why}, suspending`], why)
      assert.equal(out.suspendLog, 'systemctl suspend\n', why)
      assert.deepEqual(sleeps, [60, 45], why)
    } finally {
      cleanup(box)
    }
  }
  // keep_awake empties as the power stops allowing a hold: a reason coming
  // back could not hold again, so there is no grace.
  for (const [capacity, power] of [['19\n', 'battery 19% below floor 20%'], ['unknown\n', 'battery level unknown']]) {
    const box = sandbox()
    try {
      setStatus(box, status({ keep_awake: ['mic'] }))
      setPower(box, onBattery(30))
      onSleep(box, 1, { [join(box.power, 'BAT0/capacity')]: capacity, [statusFile(box)]: status({ keep_awake: [] }) })
      const out = runGate(box, ['suspend'])
      assert.deepEqual(lines(out).slice(1), [`idle-mode-gate: mode off, androlink keep_awake none, ${power}, suspending`], power)
      assert.equal(out.suspendLog, 'systemctl suspend\n', power)
      assert.equal(sleepLog(box), '60\n', `${power}: at once`)
    } finally {
      cleanup(box)
    }
  }
  // The battery drops below the floor during the grace: at once too.
  const box = sandbox()
  try {
    setStatus(box, status({ keep_awake: ['mic'] }))
    setPower(box, onBattery(30))
    onSleep(box, 1, { [statusFile(box)]: status({ keep_awake: [] }) })
    onSleep(box, 2, { [join(box.power, 'BAT0/capacity')]: '19\n' })
    const out = runGate(box, ['suspend'])
    assert.deepEqual(lines(out).slice(1), ['idle-mode-gate: mode off, androlink keep_awake none, battery 19% below floor 20%, suspending'])
    assert.equal(sleepLog(box), '60\n45\n', 'the grace check is the first to see the low battery')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: an empty keep_awake on battery at or above the floor gets the grace', () => {
  const box = sandbox()
  try {
    setStatus(box, status({ keep_awake: ['mic'] }))
    setPower(box, onBattery(20))
    onSleep(box, 1, { [statusFile(box)]: status({ keep_awake: [] }) })
    onSleep(box, 2, { [statusFile(box)]: status({ keep_awake: ['mic'] }) })
    onSleep(box, 3, { [monitorsFile(box)]: [{ name: 'eDP-1', dpmsStatus: true }] })
    const out = runGate(box, ['suspend'])
    assert.deepEqual(lines(out).slice(1), ['idle-mode-gate: a screen is on, not suspending'])
    assert.equal(out.suspendLog, '')
    assert.equal(sleepLog(box), '60\n45\n60\n')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: the hold limit cuts a grace short', () => {
  const box = sandbox()
  try {
    const { out, rest, sleeps } = runSteps(box, { 2: [] }, { options: { keepAwakeRecheckSecs: 15, keepAwakeMaxHoldMins: 1, keepAwakeReleaseGraceSecs: 600 } })
    assert.deepEqual(rest, ['idle-mode-gate: mode off, androlink keep_awake none, held 1 min (the limit), suspending'])
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    assert.deepEqual(sleeps, [15, 15, 15, 15])
  } finally {
    cleanup(box)
  }
})

gateTest('gate: the first decision has no grace, so an idle PC with nothing to hold suspends at once', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status({ keep_awake: [] }))
    let out = runGate(box, ['suspend'])
    assert.deepEqual(lines(out), ['idle-mode-gate: mode off, androlink keep_awake none, suspending'])
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    assert.equal(sleepLog(box), '')
    // Below the floor the log says so.
    setPower(box, onBattery(10))
    out = runGate(box, ['suspend', '--dry-run'])
    assert.deepEqual(lines(out), ['idle-mode-gate: mode off, androlink keep_awake none, battery 10% below floor 20%, would suspend'])
  } finally {
    cleanup(box)
  }
})

gateTest('gate: the release grace option is rounded and clamped to 15-600 s', () => {
  for (const [options, grace, sleeps] of [
    [{}, 45, [60, 45]],
    [{ keepAwakeReleaseGraceSecs: 15 }, 15, [60, 15]],
    [{ keepAwakeReleaseGraceSecs: 1 }, 15, [60, 15]],
    [{ keepAwakeReleaseGraceSecs: -30 }, 15, [60, 15]],
    [{ keepAwakeReleaseGraceSecs: 29.6 }, 30, [60, 30]],
    [{ keepAwakeReleaseGraceSecs: 600 }, 600, [60, ...Array(10).fill(60)]],
    [{ keepAwakeReleaseGraceSecs: 5000 }, 600, [60, ...Array(10).fill(60)]],
    [{ keepAwakeReleaseGraceSecs: '120' }, 45, [60, 45]],
    [{ keepAwakeReleaseGraceSecs: null }, 45, [60, 45]],
    [{ keepAwakeReleaseGraceSecs: true }, 45, [60, 45]],
  ]) {
    const box = sandbox()
    try {
      const label = JSON.stringify(options)
      const r = runSteps(box, { 1: [] }, { options })
      assert.deepEqual(r.rest, [`idle-mode-gate: mode off, androlink keep_awake none for ${grace} s, suspending`], label)
      assert.deepEqual(r.sleeps, sleeps, label)
    } finally {
      cleanup(box)
    }
  }
})

gateTest('gate: a held suspend runs once the battery drops below the floor, or the floor rises', () => {
  const box = sandbox()
  try {
    setStatus(box, status({ keep_awake: ['mic'] }))
    setPower(box, onBattery(30))
    onSleep(box, 1, { [join(box.power, 'BAT0/capacity')]: '25\n' })
    onSleep(box, 2, { [join(box.power, 'BAT0/capacity')]: '19\n' })
    const out = runGate(box, ['suspend'])
    assert.deepEqual(lines(out), [
      'idle-mode-gate: mode off, androlink keep_awake mic, battery 30% (floor 20%), not suspending, checking again every 60 s for up to 120 min',
      'idle-mode-gate: mode off, androlink keep_awake mic, battery 19% below floor 20%, suspending',
    ])
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    assert.equal(sleepLog(box), '60\n60\n')
  } finally {
    cleanup(box)
  }
  const box2 = sandbox()
  try {
    setStatus(box2, status({ keep_awake: ['mic'] }))
    setPower(box2, onBattery(50))
    onSleep(box2, 1, { [configFile(box2)]: { mode: 'off', keepAwakeBatteryFloor: 60 } })
    const out = runGate(box2, ['suspend'])
    assert.equal(lines(out)[1], 'idle-mode-gate: mode off, androlink keep_awake mic, battery 50% below floor 60%, suspending')
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    // The battery level going unreadable ends the hold too.
    rmSync(join(box2.root, 'suspend.log'))
    rmSync(join(box2.root, 'sleeps'))
    setConfig(box2, { mode: 'off' })
    onSleep(box2, 1, { [join(box2.power, 'BAT0/capacity')]: 'unknown\n' })
    assert.equal(lines(runGate(box2, ['suspend']))[1], 'idle-mode-gate: mode off, androlink keep_awake mic, battery level unknown, suspending')
  } finally {
    cleanup(box2)
  }
})

gateTest('gate: a held suspend runs once the status file goes stale, stops or disappears', () => {
  for (const [next, why] of [
    [status({ updated: nowSecs() - 1000 }), 'androlink status stale'],
    [status({ running: false, keep_awake: [] }), 'androlink status stopped'],
    [null, 'androlink status missing'],
    ['not json', 'androlink status invalid'],
  ]) {
    const box = sandbox()
    try {
      setPower(box, onAc)
      setStatus(box, status())
      onSleep(box, 1, { [statusFile(box)]: next })
      const out = runGate(box, ['suspend'])
      assert.deepEqual(lines(out).slice(1), [`idle-mode-gate: mode off, ${why}, suspending`], why)
      assert.equal(out.suspendLog, 'systemctl suspend\n', why)
    } finally {
      cleanup(box)
    }
  }
})

gateTest('gate: a wait ends without a suspend when the mode leaves off', () => {
  for (const mode of ['half', 'full']) {
    const box = sandbox()
    try {
      setPower(box, onAc)
      setStatus(box, status())
      onSleep(box, 2, { [configFile(box)]: { mode } })
      const out = runGate(box, ['suspend'])
      assert.deepEqual(lines(out).slice(1), [`idle-mode-gate: mode ${mode}, not suspending`])
      assert.equal(out.suspendLog, '')
      assert.equal(sleepLog(box), '60\n60\n')
      assert.equal(existsSync(holdFile(box)), false)
    } finally {
      cleanup(box)
    }
  }
})

gateTest('gate: a wait ends without a suspend when a screen is on or hyprctl cannot tell', () => {
  const cases = [
    ['one of two screens on', (box) => writeFileSync(monitorsFile(box), JSON.stringify([{ dpmsStatus: false }, { dpmsStatus: true }]))],
    ['no screens', (box) => writeFileSync(monitorsFile(box), '[]')],
    ['not a list', (box) => writeFileSync(monitorsFile(box), '{"dpmsStatus":false}')],
    ['no dpmsStatus', (box) => writeFileSync(monitorsFile(box), '[{"name":"eDP-1"}]')],
    ['junk', (box) => writeFileSync(monitorsFile(box), 'Couldn\'t connect')],
    ['hyprctl fails', (box) => writeFileSync(join(box.root, 'hyprctl.fail'), '')],
  ]
  for (const [label, setUp] of cases) {
    const box = sandbox()
    try {
      setPower(box, onAc)
      setStatus(box, status())
      setUp(box)
      const out = runGate(box, ['suspend'])
      assert.equal(out.status, 0, out.stderr)
      assert.deepEqual(lines(out).slice(1), ['idle-mode-gate: a screen is on, not suspending'], label)
      assert.equal(out.suspendLog, '', label)
      assert.equal(sleepLog(box), '60\n', label)
    } finally {
      cleanup(box)
    }
  }
})

gateTest('gate: a hold lasts at most keepAwakeMaxHoldMins, whatever the reasons', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status())
    setConfig(box, { mode: 'off', keepAwakeRecheckSecs: 15, keepAwakeMaxHoldMins: 1 })
    let out = runGate(box, ['suspend'])
    assert.deepEqual(lines(out), [
      'idle-mode-gate: mode off, androlink keep_awake mic, on AC, not suspending, checking again every 15 s for up to 1 min',
      'idle-mode-gate: mode off, androlink keep_awake mic, on AC, held 1 min (the limit), suspending',
    ])
    assert.equal(sleepLog(box), '15\n15\n15\n15\n', 'four 15 s checks make the minute')
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    // A check interval that does not divide the limit: the last wait is cut
    // short, so the hold ends at the limit and never past it (N-GATE-3).
    const again = (options) => {
      rmSync(join(box.root, 'sleep.log'), { force: true })
      rmSync(join(box.root, 'sleeps'), { force: true })
      setConfig(box, options)
      return runGate(box, ['suspend'])
    }
    out = again({ keepAwakeRecheckSecs: 45, keepAwakeMaxHoldMins: 1 })
    assert.match(lines(out)[1], /held 1 min \(the limit\), suspending$/)
    assert.equal(sleepLog(box), '45\n15\n')
    // A check interval longer than the limit: one wait of exactly the limit.
    out = again({ keepAwakeRecheckSecs: 600, keepAwakeMaxHoldMins: 1 })
    assert.match(lines(out)[1], /held 1 min \(the limit\), suspending$/)
    assert.equal(sleepLog(box), '60\n')
    assert.equal(readSuspendLog(box), 'systemctl suspend\n'.repeat(3), 'one suspend per run')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: the waits add up to the hold limit exactly, whatever the interval', () => {
  for (const [recheck, maxHold] of [[15, 1], [45, 1], [59, 1], [60, 1], [61, 1], [600, 1], [600, 2], [600, 11], [17, 3], [600, 120]]) {
    const box = sandbox()
    try {
      setPower(box, onAc)
      setStatus(box, status({ heartbeat_s: 3600 }))
      // Keep the status file fresh at the long holds (the fake sleep is instant).
      setConfig(box, { mode: 'off', keepAwakeRecheckSecs: recheck, keepAwakeMaxHoldMins: maxHold })
      const out = runGate(box, ['suspend'])
      const label = `${recheck} s, ${maxHold} min`
      assert.match(lines(out)[1], new RegExp(`held ${maxHold} min \\(the limit\\), suspending$`), label)
      const waits = sleepLog(box).split('\n').filter(Boolean).map(Number)
      assert.equal(waits.reduce((a, b) => a + b, 0), maxHold * 60, label)
      assert.ok(waits.every((w) => w >= 1 && w <= recheck), label)
      assert.ok(waits.slice(0, -1).every((w) => w === recheck), `${label}: only the last wait is shorter`)
    } finally {
      cleanup(box)
    }
  }
})

gateTest('gate: the check interval and hold limit options are rounded and clamped', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status())
    writeFileSync(join(box.root, 'hyprctl.fail'), '')
    const first = (options) => {
      setConfig(box, options)
      const out = runGate(box, ['suspend'])
      assert.equal(out.suspendLog, '')
      return lines(out)[0].replace(/^.* not suspending, /, '')
    }
    assert.equal(first({}), 'checking again every 60 s for up to 120 min')
    assert.equal(first({ keepAwakeRecheckSecs: 1, keepAwakeMaxHoldMins: 0 }), 'checking again every 15 s for up to 1 min')
    assert.equal(first({ keepAwakeRecheckSecs: 15, keepAwakeMaxHoldMins: 1 }), 'checking again every 15 s for up to 1 min')
    assert.equal(first({ keepAwakeRecheckSecs: 600, keepAwakeMaxHoldMins: 1440 }), 'checking again every 600 s for up to 1440 min')
    assert.equal(first({ keepAwakeRecheckSecs: 5000, keepAwakeMaxHoldMins: 99999 }), 'checking again every 600 s for up to 1440 min')
    assert.equal(first({ keepAwakeRecheckSecs: 29.6, keepAwakeMaxHoldMins: 30.4 }), 'checking again every 30 s for up to 30 min')
    for (const junk of [{ keepAwakeRecheckSecs: '30', keepAwakeMaxHoldMins: '5' }, { keepAwakeRecheckSecs: null, keepAwakeMaxHoldMins: false }, 'not json'])
      assert.equal(first(junk), 'checking again every 60 s for up to 120 min', JSON.stringify(junk))
  } finally {
    cleanup(box)
  }
})

gateTest('gate: it waits only in a private XDG_RUNTIME_DIR with a hold file of its own', () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status())
    for (const mode of [0o777, 0o770, 0o757]) {
      chmodSync(box.runtime, mode)
      const out = runGate(box, ['suspend'])
      assert.deepEqual(lines(out), ['idle-mode-gate: mode off, androlink keep_awake mic, on AC, not suspending (no private XDG_RUNTIME_DIR to wait in)'], mode.toString(8))
      assert.equal(sleepLog(box), '')
      assert.equal(existsSync(holdFile(box)), false)
    }
    chmodSync(box.runtime, 0o700)
    // A symlink in place of the hold file is never followed.
    const target = join(box.root, 'elsewhere')
    writeFileSync(target, 'keep me\n')
    symlinkSync(target, holdFile(box))
    let out = runGate(box, ['suspend'])
    assert.deepEqual(lines(out), ["idle-mode-gate: mode off, androlink keep_awake mic, on AC, not suspending (the hold file is not the gate's)"])
    assert.equal(readFileSync(target, 'utf8'), 'keep me\n')
    rmSync(holdFile(box))
    mkdirSync(holdFile(box))
    out = runGate(box, ['suspend'])
    assert.match(lines(out)[0], /not suspending \(the hold file is not the gate's\)$/, 'a directory')
    assert.equal(out.suspendLog, '')
    assert.equal(sleepLog(box), '')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: a wait ends without a suspend once the hold file no longer names it', () => {
  for (const [label, next] of [['removed', null], ['another PID', '4194304\n'], ['emptied', '']]) {
    const box = sandbox()
    try {
      setPower(box, onAc)
      setStatus(box, status())
      // The status also clears, so only the hold file stops the suspend.
      onSleep(box, 1, { [holdFile(box)]: next, [statusFile(box)]: status({ keep_awake: [] }) })
      const out = runGate(box, ['suspend'])
      assert.deepEqual(lines(out).slice(1), ['idle-mode-gate: wait cancelled, not suspending'], label)
      assert.equal(out.suspendLog, '', label)
    } finally {
      cleanup(box)
    }
  }
})

gateTest('gate: resume stops a waiting gate at once', { timeout: 20000 }, async () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status())
    writeFileSync(join(box.root, 'sleep.block'), '')
    const held = startGate(box)
    await waitFor('the hold file', () => readHold(box) === String(held.child.pid))
    await waitFor('the first wait', () => sleepLog(box) === '60\n')
    assert.equal(statSync(holdFile(box)).mode & 0o777, 0o600, 'the hold file is private')
    const resumed = runGate(box, ['resume'])
    assert.equal(resumed.status, 0, resumed.stderr)
    assert.equal(resumed.stdout, 'idle-mode-gate: resume, stopped the waiting gate\n')
    const out = await within(5000, held.done, 'the stopped gate')
    assert.equal(out.status, 0, out.stderr)
    assert.deepEqual(lines(out), [
      'idle-mode-gate: mode off, androlink keep_awake mic, on AC, not suspending, checking again every 60 s for up to 120 min',
      'idle-mode-gate: input, not suspending',
    ])
    assert.equal(readSuspendLog(box), '')
    assert.equal(existsSync(holdFile(box)), false)
    // Nothing waits any more.
    assert.equal(runGate(box, ['resume']).stdout, 'idle-mode-gate: resume, nothing waiting\n')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: a new idle period replaces a gate that still waits', { timeout: 20000 }, async () => {
  const box = sandbox()
  try {
    setPower(box, onAc)
    setStatus(box, status())
    writeFileSync(join(box.root, 'sleep.block'), '')
    const first = startGate(box)
    await waitFor('the first hold', () => readHold(box) === String(first.child.pid))
    const second = startGate(box)
    const out = await within(8000, first.done, 'the replaced gate')
    assert.equal(lines(out).at(-1), 'idle-mode-gate: input, not suspending')
    await waitFor('the second hold', () => readHold(box) === String(second.child.pid))
    assert.equal(runGate(box, ['resume']).stdout, 'idle-mode-gate: resume, stopped the waiting gate\n')
    const out2 = await within(5000, second.done, 'the second gate')
    assert.equal(lines(out2).at(-1), 'idle-mode-gate: input, not suspending')
    assert.equal(readSuspendLog(box), '')
  } finally {
    cleanup(box)
  }
})

// ---- N-GATE-4: the background sleep never holds the lock ----

gateTest('gate: a killed gate leaves no lock behind, so the next idle period can wait', { timeout: 20000 }, async () => {
  const box = sandbox()
  const sleepPids = () => {
    try {
      return readFileSync(join(box.root, 'sleep.pids'), 'utf8').split('\n').filter(Boolean).map(Number)
    } catch {
      return []
    }
  }
  const cmdline = (pid) => {
    try {
      return readFileSync(`/proc/${pid}/cmdline`, 'utf8').split('\0')
    } catch {
      return []
    }
  }
  const openFiles = (pid) => readdirSync(`/proc/${pid}/fd`).map((fd) => {
    try {
      return readlinkSync(`/proc/${pid}/fd/${fd}`)
    } catch {
      return ''
    }
  })
  try {
    setPower(box, onAc)
    setStatus(box, status())
    writeFileSync(join(box.root, 'sleep.block'), '')
    const first = startGate(box)
    await waitFor('the first hold', () => readHold(box) === String(first.child.pid))
    await waitFor('the real sleep', () => sleepPids().length === 1 && cmdline(sleepPids()[0])[0] === realSleep)
    const [sleeper] = sleepPids()
    assert.ok(openFiles(first.child.pid).includes(holdFile(box)), 'the gate holds the hold file open')
    assert.ok(!openFiles(sleeper).includes(holdFile(box)), 'its sleep does not')
    // Killed outright: no trap runs, the hold file stays and the sleep lives on.
    first.child.kill('SIGKILL')
    await waitFor('the killed gate', () => first.child.signalCode === 'SIGKILL')
    assert.equal(cmdline(sleeper)[0], realSleep, 'the orphaned sleep still runs')
    assert.equal(readHold(box), String(first.child.pid))
    assert.equal(spawnSync(which('flock'), ['-n', holdFile(box), 'true']).status, 0, 'nobody holds the lock')
    // The next idle period's gate takes the lock at once and waits.
    const second = startGate(box)
    await waitFor('the second hold', () => readHold(box) === String(second.child.pid), 3000)
    assert.equal(runGate(box, ['resume']).stdout, 'idle-mode-gate: resume, stopped the waiting gate\n')
    const out = await within(5000, second.done, 'the second gate')
    assert.deepEqual(lines(out), [
      'idle-mode-gate: mode off, androlink keep_awake mic, on AC, not suspending, checking again every 60 s for up to 120 min',
      'idle-mode-gate: input, not suspending',
    ])
    assert.equal(readSuspendLog(box), '')
  } finally {
    for (const pid of sleepPids()) {
      try {
        process.kill(pid)
      } catch {}
    }
    cleanup(box)
  }
})

gateTest('gate: resume never signals a process that is not a waiting gate', { timeout: 20000 }, async () => {
  const box = sandbox()
  const bystander = spawn(realSleep, ['30'], { stdio: 'ignore' })
  const alive = (pid) => {
    try {
      process.kill(pid, 0)
      return true
    } catch {
      return false
    }
  }
  let locker
  try {
    // No hold file, or the runtime dir unset.
    assert.equal(runGate(box, ['resume']).stdout, 'idle-mode-gate: resume, nothing waiting\n')
    assert.equal(runGate(box, ['resume'], { XDG_RUNTIME_DIR: '' }).stdout, 'idle-mode-gate: resume, nothing waiting\n')
    // A leftover nobody locks names another process: it is removed, not signalled.
    for (const text of [`${bystander.pid}\n`, 'junk\n', '', `${process.pid}\n`]) {
      writeFileSync(holdFile(box), text)
      assert.equal(runGate(box, ['resume']).stdout, 'idle-mode-gate: resume, nothing waiting\n', JSON.stringify(text))
      assert.equal(existsSync(holdFile(box)), false, JSON.stringify(text))
    }
    // Locked by something that is not the gate: left alone.
    locker = spawn(which('flock'), [holdFile(box), realSleep, '30'], { stdio: 'ignore' })
    await waitFor('the lock', () => existsSync(holdFile(box)) && spawnSync(which('flock'), ['-n', holdFile(box), 'true']).status !== 0)
    writeFileSync(holdFile(box), `${locker.pid}\n`)
    assert.equal(runGate(box, ['resume']).stdout, 'idle-mode-gate: resume, nothing waiting\n')
    assert.equal(readHold(box), String(locker.pid))
    assert.ok(alive(locker.pid), 'the locking process is not signalled')
    assert.ok(alive(bystander.pid), 'the named process is not signalled')
    // A symlink is not followed.
    rmSync(holdFile(box))
    symlinkSync(join(box.root, 'elsewhere'), holdFile(box))
    assert.equal(runGate(box, ['resume']).stdout, 'idle-mode-gate: resume, nothing waiting\n')
  } finally {
    bystander.kill()
    locker?.kill()
    cleanup(box)
  }
})

gateTest('gate: without --dry-run it suspends through systemctl, then loginctl', () => {
  const box = sandbox()
  try {
    setPower(box, onBattery(10))
    setStatus(box, status())
    let out = runGate(box, ['suspend'])
    assert.equal(out.status, 0)
    assert.equal(out.stdout.trim(), 'idle-mode-gate: mode off, androlink keep_awake mic, battery 10% below floor 20%, suspending')
    assert.equal(out.suspendLog, 'systemctl suspend\n')
    rmSync(join(box.root, 'suspend.log'))
    writeFileSync(join(box.root, 'systemctl.fail'), '')
    out = runGate(box, ['suspend'])
    assert.equal(out.suspendLog, 'systemctl suspend\nloginctl suspend\n')
  } finally {
    cleanup(box)
  }
})

gateTest('gate: other arguments print the usage and exit 2', () => {
  const box = sandbox()
  try {
    for (const args of [[], ['hibernate'], ['--dry-run'], ['Resume']]) {
      const out = runGate(box, args)
      assert.equal(out.status, 2)
      assert.match(out.stderr, /^usage: idle-mode-gate\.sh suspend \[--dry-run\] \| idle-mode-gate\.sh resume$/m)
      assert.equal(out.suspendLog, '')
    }
  } finally {
    cleanup(box)
  }
})

test('the README lines add the on-resume line to the suspend listener once', async () => {
  const en = await readFile(new URL('README.en.md', moduleRoot), 'utf8')
  const zh = await readFile(new URL('README.md', moduleRoot), 'utf8')
  const lines = en.match(/^grep -q 'idle-mode-gate\.sh resume' .*\n {4}sed -i .*$/m)
  assert.ok(lines, 'README.en.md has the on-resume install lines')
  assert.ok(zh.includes(lines[0]), 'README.md has the same lines')
  const resume = '    on-resume = ~/.config/hypr/custom/scripts/idle-mode-gate.sh resume\n'
  const before = [
    '$suspend_cmd = ~/.config/hypr/custom/scripts/idle-mode-gate.sh suspend\n',
    'listener {\n    timeout = 600 # 10mins\n    on-timeout = hyprctl dispatch dpms off\n    on-resume = hyprctl dispatch dpms on\n}\n',
    'listener {\n    timeout = 900 # 15mins\n    on-timeout = $suspend_cmd\n}\n',
  ].join('\n')
  const root = mkdtempSync(join(tmpdir(), 'idle-modes-conf-'))
  try {
    const conf = join(root, '.config/hypr/hypridle.conf')
    mkdirSync(dirname(conf), { recursive: true })
    writeFileSync(conf, before)
    for (let run = 0; run < 2; run++) {
      const out = spawnSync('bash', ['-c', lines[0]], { encoding: 'utf8', env: { HOME: root, PATH: '/usr/bin:/bin' } })
      assert.equal(out.stderr, '')
    }
    assert.equal(readFileSync(conf, 'utf8'), before.replace('    on-timeout = $suspend_cmd\n', `    on-timeout = $suspend_cmd\n${resume}`))
    // A config without the gate's listener is left as it was.
    writeFileSync(conf, 'listener {\n    timeout = 900\n    on-timeout = systemctl suspend\n}\n')
    spawnSync('bash', ['-c', lines[0]], { env: { HOME: root, PATH: '/usr/bin:/bin' } })
    assert.equal(readFileSync(conf, 'utf8'), 'listener {\n    timeout = 900\n    on-timeout = systemctl suspend\n}\n')
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})

test('gate options are declared in the ConfigLoader with the same ranges', async () => {
  const loader = await readFile(new URL('ConfigLoader.qml', moduleRoot), 'utf8')
  const script = await readFile(gate, 'utf8')
  assert.match(loader, /property int keepAwakeBatteryFloor: 20\n/)
  assert.match(loader, /property int keepAwakeMaxAgeSecs: 90\n/)
  assert.match(loader, /root\.clamp\(adapterItem\.keepAwakeBatteryFloor, 0, 100, 20\)/)
  assert.match(loader, /root\.clamp\(adapterItem\.keepAwakeMaxAgeSecs, 15, 3600, 90\)/)
  assert.match(loader, /property int keepAwakeRecheckSecs: 60\n/)
  assert.match(loader, /property int keepAwakeMaxHoldMins: 120\n/)
  assert.match(loader, /root\.clamp\(adapterItem\.keepAwakeRecheckSecs, 15, 600, 60\)/)
  assert.match(loader, /root\.clamp\(adapterItem\.keepAwakeMaxHoldMins, 1, 1440, 120\)/)
  assert.match(loader, /property int keepAwakeReleaseGraceSecs: 45\n/)
  assert.match(loader, /root\.clamp\(adapterItem\.keepAwakeReleaseGraceSecs, 15, 600, 45\)/)
  assert.match(script, /floor_default=20 floor_min=0 floor_max=100\n/)
  assert.match(script, /max_age_default=90 max_age_min=15 max_age_max=3600\n/)
  assert.match(script, /recheck_default=60 recheck_min=15 recheck_max=600\n/)
  assert.match(script, /max_hold_default=120 max_hold_min=1 max_hold_max=1440\n/)
  assert.match(script, /grace_default=45 grace_min=15 grace_max=600\n/)
  assert.match(script, /read_option keepAwakeReleaseGraceSecs /)
  assert.match(script, /read_option keepAwakeRecheckSecs /)
  assert.match(script, /read_option keepAwakeMaxHoldMins /)
  assert.match(script, /read_option keepAwakeBatteryFloor /)
  assert.match(script, /read_option keepAwakeMaxAgeSecs /)
  assert.ok((statSync(gate).mode & 0o111) !== 0, 'the gate script stays executable')
  const m = await manifest()
  assert.equal(m.version, '1.2.1')
  assert.deepEqual(m.capabilities, [], 'the gate runs outside the shell; the module itself needs no capability')
})
