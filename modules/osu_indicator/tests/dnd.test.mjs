import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = await readFile(new URL('../DndLogic.js', import.meta.url), 'utf8')
const context = vm.createContext({})
vm.runInContext(source.replace('.pragma library', ''), context)
const D = context
const plain = value => JSON.parse(JSON.stringify(value))

// Drives the machine like DndGuard.qml: every event is either an osu-state
// change or a manual DND toggle; returned `set` values are applied to the
// simulated Notifications.silent, which echoes back as another step.
function run(events, { mode = 'playingCooldown', silent = false, owed = false } = {}) {
  let machine = D.initial(owed, silent)
  let state = 'off'
  let lastOwed = owed
  const trace = []
  const apply = () => {
    const r = D.step(machine, D.wantDnd(mode, state), silent)
    machine = r.machine
    lastOwed = r.owed
    if (r.set !== null) {
      silent = r.set
      // The write echoes back through onSilentChanged.
      const echo = D.step(machine, D.wantDnd(mode, state), silent)
      machine = echo.machine
      lastOwed = echo.owed
      assert.equal(echo.set, null, 'an echo never writes again')
    }
  }
  apply()
  for (const event of events) {
    if (event.startsWith('user:')) silent = event === 'user:on'
    else state = event
    apply()
    trace.push(silent)
  }
  return { trace, machine: plain(machine), owed: lastOwed }
}

test('wantDnd per mode', () => {
  const states = ['off', 'idle', 'menu', 'playing', 'cooldown', undefined]
  assert.deepEqual(states.map(s => D.wantDnd('playingCooldown', s)), [false, false, false, true, true, false])
  assert.deepEqual(states.map(s => D.wantDnd('playing', s)), [false, false, false, true, false, false])
  assert.deepEqual(states.map(s => D.wantDnd('off', s)), [false, false, false, false, false, false])
  assert.equal(D.wantDnd('bogus', 'cooldown'), true)
  assert.equal(D.normalizeMode(undefined), 'playingCooldown')
  assert.equal(D.normalizeMode('playing'), 'playing')
})

test('turns DND on for a play and back off afterwards', () => {
  const r = run(['menu', 'playing', 'cooldown', 'menu'])
  assert.deepEqual(r.trace, [false, true, true, false])
  assert.deepEqual(r.machine, plain(D.idle()))
  assert.equal(r.owed, false)
})

test('playing-only mode releases DND at cooldown', () => {
  assert.deepEqual(run(['playing', 'cooldown', 'menu'], { mode: 'playing' }).trace, [true, false, false])
})

test('off mode never touches DND', () => {
  assert.deepEqual(run(['playing', 'user:on', 'cooldown', 'menu'], { mode: 'off' }).trace, [false, true, true, true])
})

test('DND that was already on stays on after the play', () => {
  const r = run(['playing', 'cooldown', 'menu'], { silent: true })
  assert.deepEqual(r.trace, [true, true, true])
  assert.equal(r.owed, false)
})

test('a manual change during play stops management until the next play', () => {
  // User turns DND off mid-play: not turned back on, and not touched later.
  const r = run(['playing', 'user:off', 'cooldown', 'user:on', 'menu', 'playing', 'menu'])
  assert.deepEqual(r.trace, [true, false, false, true, true, true, true])
  // Next play after a suspended one is managed again (user had it on).
  const s = run(['playing', 'user:off', 'menu', 'playing', 'menu'])
  assert.deepEqual(s.trace, [true, false, false, true, false])
})

test('owed flag persists only while the module holds DND it turned on', () => {
  assert.equal(D.step(D.idle(), true, false).owed, true)
  assert.equal(D.step(D.idle(), true, true).owed, false)
  assert.equal(D.step({ managing: true, saved: false, suspended: false }, false, true).owed, false)
  assert.equal(D.step({ managing: true, saved: false, suspended: false }, false, true).set, false)
})

test('restart handling: resume an owed DND, start fresh after a reset', () => {
  // Module reloaded mid-play with DND still on: keeps owning it, releases later.
  assert.deepEqual(plain(D.initial(true, true)), { managing: true, saved: false, suspended: false })
  const resumed = run(['playing', 'menu'], { owed: true, silent: true })
  assert.deepEqual(resumed.trace, [true, false])
  // Shell restart reset silent to false: not a manual change, just start over.
  assert.deepEqual(plain(D.initial(true, false)), plain(D.idle()))
  assert.deepEqual(run(['playing', 'menu'], { owed: true, silent: false }).trace, [true, false])
  // Junk input is safe.
  assert.deepEqual(plain(D.initial(undefined, undefined)), plain(D.idle()))
  const r = D.step(null, true, undefined)
  assert.equal(r.set, true)
  assert.equal(r.machine.managing, true)
})
