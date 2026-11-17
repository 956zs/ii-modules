import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
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
// argv, so no test can suspend this machine.

const gate = fileURLToPath(new URL('idle-mode-gate.sh', moduleRoot))
const hasJq = spawnSync('jq', ['--version']).status === 0
const gateTest = (name, fn) => test(name, { skip: hasJq ? false : 'jq is not installed' }, fn)

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
  return dirs
}

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

function runGate(box, args = ['suspend', '--dry-run'], env = {}) {
  const jqDir = dirname(spawnSync('sh', ['-c', 'command -v jq'], { encoding: 'utf8' }).stdout.trim())
  const out = spawnSync('bash', [gate, ...args], {
    encoding: 'utf8',
    env: {
      PATH: `${box.bin}:${jqDir}:/usr/bin:/bin`,
      HOME: box.root,
      XDG_CONFIG_HOME: box.config,
      XDG_RUNTIME_DIR: box.runtime,
      IDLE_MODES_POWER_SUPPLY_DIR: box.power,
      ...env,
    },
  })
  let suspendLog = ''
  try {
    suspendLog = readFileSync(join(box.root, 'suspend.log'), 'utf8')
  } catch {
    suspendLog = ''
  }
  return { status: out.status, stdout: out.stdout, stderr: out.stderr, suspendLog }
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
    assert.equal(decide(box, ['suspend']), 'idle-mode-gate: mode off, androlink keep_awake mic,transfer, on AC, not suspending')
    assert.equal(runGate(box, ['suspend']).suspendLog, '', 'never calls systemctl while held')
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
    for (const args of [[], ['hibernate'], ['--dry-run']]) {
      const out = runGate(box, args)
      assert.equal(out.status, 2)
      assert.match(out.stderr, /^usage: idle-mode-gate\.sh suspend \[--dry-run\]/)
      assert.equal(out.suspendLog, '')
    }
  } finally {
    cleanup(box)
  }
})

test('gate options are declared in the ConfigLoader with the same ranges', async () => {
  const loader = await readFile(new URL('ConfigLoader.qml', moduleRoot), 'utf8')
  const script = await readFile(gate, 'utf8')
  assert.match(loader, /property int keepAwakeBatteryFloor: 20\n/)
  assert.match(loader, /property int keepAwakeMaxAgeSecs: 90\n/)
  assert.match(loader, /root\.clamp\(adapterItem\.keepAwakeBatteryFloor, 0, 100, 20\)/)
  assert.match(loader, /root\.clamp\(adapterItem\.keepAwakeMaxAgeSecs, 15, 3600, 90\)/)
  assert.match(script, /floor_default=20 floor_min=0 floor_max=100\n/)
  assert.match(script, /max_age_default=90 max_age_min=15 max_age_max=3600\n/)
  assert.match(script, /read_option keepAwakeBatteryFloor /)
  assert.match(script, /read_option keepAwakeMaxAgeSecs /)
  assert.ok((statSync(gate).mode & 0o111) !== 0, 'the gate script stays executable')
  const m = await manifest()
  assert.equal(m.version, '1.1.0')
  assert.deepEqual(m.capabilities, [], 'the gate runs outside the shell; the module itself needs no capability')
})
