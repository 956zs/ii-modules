import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = await readFile(new URL('../StatusLogic.js', import.meta.url), 'utf8')
const context = vm.createContext({})
vm.runInContext(source.replace('.pragma library', ''), context)
const L = context

// Objects cross the vm context boundary; round-trip to plain data for deepEqual.
const plain = (value) => JSON.parse(JSON.stringify(value))
const fixture = (name) => readFile(new URL(`fixtures/${name}`, import.meta.url), 'utf8')

const UPDATED = 1794550751
const FRESH = UPDATED + 20
const opts = { showWhenNotRunning: false, showUnread: true, threshold: 20 }

test('a live single-phone file parses to the contract fields', async () => {
  const r = plain(L.parseStatus(await fixture('live-one.json'), FRESH, 30))
  assert.equal(r.state, 'live')
  assert.equal(r.updated, UPDATED)
  assert.deepEqual(r.phones, [{
    id: 'a54-0f3c9e',
    name: 'Galaxy A54',
    connected: true,
    route: 'lan',
    battery: { level: 60, charging: false },
    helper: 'running',
    unread: 3,
    ringing: false,
    webcam: false,
  }])
  assert.equal(L.appRunning(L.parseStatus(await fixture('live-one.json'), FRESH, 30)), true)
})

test('missing, unreadable and malformed files read as androlink not running', async () => {
  for (const text of [null, undefined, '', '   \n']) {
    const r = L.parseStatus(text, FRESH, 30)
    assert.equal(r.state, 'missing', JSON.stringify(text))
    assert.equal(r.phones.length, 0)
    assert.equal(L.appRunning(r), false)
  }
  for (const name of ['invalid.json', 'wrong-shape.json', 'no-version.json']) {
    const r = L.parseStatus(await fixture(name), FRESH, 30)
    assert.equal(r.state, 'invalid', name)
    assert.equal(r.phones.length, 0, name)
    assert.equal(L.appRunning(r), false, name)
  }
  for (const junk of ['null', '42', '"text"', '{"version":0,"updated":1,"running":true}',
    '{"version":1.5,"updated":1,"running":true}', '{"version":1,"running":true}',
    '{"version":1,"updated":-3,"running":true}', '{"version":1,"updated":"soon","running":true}']) {
    assert.equal(L.parseStatus(junk, FRESH, 30).state, 'invalid', junk)
  }
})

test('running false is a clean quit with no phones', async () => {
  const r = L.parseStatus(await fixture('not-running.json'), FRESH, 30)
  assert.equal(r.state, 'stopped')
  assert.equal(r.updated, UPDATED)
  assert.equal(r.phones.length, 0)
  assert.equal(L.appRunning(r), false)
  // running must be exactly true; anything else is a quit too.
  assert.equal(L.parseStatus(`{"version":1,"updated":${UPDATED},"running":"yes","phones":[]}`, FRESH, 30).state, 'stopped')
})

test('a file older than three heartbeats is stale, never earlier', async () => {
  const text = await fixture('live-one.json')
  assert.equal(L.parseStatus(text, UPDATED + 90, 30).state, 'live')
  assert.equal(L.parseStatus(text, UPDATED + 91, 30).state, 'stale')
  assert.equal(L.parseStatus(text, UPDATED + 91, 60).state, 'live')
  // A clock running behind the writer is not stale.
  assert.equal(L.parseStatus(text, UPDATED - 500, 30).state, 'live')
  // Non-numeric heartbeats fall back to the contract default of 30 s; numbers clamp to 1 s or more.
  assert.equal(L.parseStatus(text, UPDATED + 91, 'x').state, 'stale')
  assert.equal(L.parseStatus(text, UPDATED + 89, 0).state, 'stale')
  // A stale record still counts as androlink running (dimmed, not hidden).
  assert.equal(L.appRunning(L.parseStatus(text, UPDATED + 500, 30)), true)
})

test('a heartbeat published in the file wins and newer versions still read', async () => {
  const text = await fixture('future-version.json')
  const fresh = plain(L.parseStatus(text, UPDATED + 30, 30))
  assert.equal(fresh.state, 'live')
  assert.equal(fresh.phones[0].battery.level, 81)
  assert.equal(fresh.phones[0].signal, undefined)
  assert.equal(L.parseStatus(text, UPDATED + 31, 30).state, 'stale')
})

test('phone entries are sanitised field by field', async () => {
  const r = plain(L.parseStatus(await fixture('several-phones.json'), FRESH, 30))
  assert.equal(r.state, 'live')
  assert.equal(r.phones.length, 3, 'non-object entries are dropped')
  assert.deepEqual(r.phones[0], {
    id: 'tab-s9-77aa', name: 'Galaxy Tab S9', connected: false, route: null, battery: null,
    helper: 'not_set_up', unread: 0, ringing: false, webcam: false,
  })
  const bad = r.phones[2]
  assert.equal(bad.id, '', 'an id the CLI could read as a flag is dropped')
  assert.equal(bad.name, 'Bad id phone', 'control characters and runs of space collapse')
  assert.equal(bad.route, null)
  assert.deepEqual(bad.battery, { level: 100, charging: false })
  assert.equal(bad.helper, null)
  assert.equal(bad.unread, 0)
  assert.equal(bad.ringing, false)
  assert.equal(bad.webcam, false)
  const long = plain(L.cleanPhone({ id: 'x', name: 'n'.repeat(200) }))
  assert.equal(long.name.length, 64)
  assert.ok(long.name.endsWith('…'))
  assert.equal(L.cleanPhone(null), null)
  assert.equal(L.cleanPhone([1]), null)
})

test('device ids must be safe as one argv element', () => {
  for (const ok of ['a54-0f3c9e', 'R5CW12345', 'adb-RFC.local:5555', 'x'.repeat(64)])
    assert.equal(L.validId(ok), true, ok)
  for (const bad of ['', '-rf', '--ring', ' a54', 'a54 ', 'a\nb', 'a\u0000b', 'x'.repeat(65), 7, null, undefined, {}])
    assert.equal(L.validId(bad), false, JSON.stringify(bad))
})

test('the primary phone is the first connected one, else the first', async () => {
  assert.equal(L.primaryIndex(L.parseStatus(await fixture('several-phones.json'), FRESH, 30)), 1)
  assert.equal(L.primaryIndex(L.parseStatus(await fixture('disconnected.json'), FRESH, 30)), 0)
  assert.equal(L.primaryIndex(L.parseStatus(await fixture('no-phones.json'), FRESH, 30)), -1)
  assert.equal(L.primaryIndex(L.parseStatus(null, FRESH, 30)), -1)
  assert.equal(L.primaryIndex(null), -1)
})

test('the bar hides or goes quiet while androlink is not running', async () => {
  for (const text of [null, await fixture('invalid.json'), await fixture('not-running.json')]) {
    const record = L.parseStatus(text, FRESH, 30)
    const hidden = plain(L.barModel(record, opts))
    assert.equal(hidden.shown, false)
    assert.equal(hidden.quiet, true)
    const quiet = plain(L.barModel(record, { ...opts, showWhenNotRunning: true }))
    assert.equal(quiet.shown, true)
    assert.equal(quiet.quiet, true)
    assert.equal(quiet.dim, true)
    assert.equal(quiet.batteryText, '')
  }
})

test('the bar shows battery, charging, low battery and markers of the primary phone', async () => {
  const live = plain(L.barModel(L.parseStatus(await fixture('live-one.json'), FRESH, 30), opts))
  assert.deepEqual(live, {
    shown: true, quiet: false, dim: false, name: 'Galaxy A54', batteryText: '60%', charging: false,
    low: false, helperStopped: false, unread: 3, ringing: false, webcam: false,
  })
  const charging = plain(L.barModel(L.parseStatus(await fixture('charging.json'), FRESH, 30), opts))
  assert.equal(charging.batteryText, '15%')
  assert.equal(charging.charging, true)
  assert.equal(charging.low, false, 'charging is never low')
  assert.equal(charging.unread, 0)
  const low = plain(L.barModel(L.parseStatus(await fixture('low-battery.json'), FRESH, 30), opts))
  assert.equal(low.low, true)
  assert.equal(low.helperStopped, true)
  assert.equal(low.ringing, true)
  assert.equal(low.webcam, true)
  assert.equal(plain(L.barModel(L.parseStatus(await fixture('low-battery.json'), FRESH, 30), { ...opts, threshold: 15 })).low, false)
  const noUnread = plain(L.barModel(L.parseStatus(await fixture('live-one.json'), FRESH, 30), { ...opts, showUnread: false }))
  assert.equal(noUnread.unread, 0)
})

test('the bar dims a disconnected or stale phone and keeps the camera mark', async () => {
  const off = plain(L.barModel(L.parseStatus(await fixture('disconnected.json'), FRESH, 30), opts))
  assert.equal(off.shown, true)
  assert.equal(off.dim, true)
  assert.equal(off.batteryText, '12%')
  const stale = plain(L.barModel(L.parseStatus(await fixture('low-battery.json'), UPDATED + 600, 30), opts))
  assert.equal(stale.dim, true)
  assert.equal(stale.ringing, false, 'a stale ring flag is not trusted')
  assert.equal(stale.webcam, true, 'the camera mark stays until androlink says otherwise')
  const several = plain(L.barModel(L.parseStatus(await fixture('several-phones.json'), FRESH, 30), opts))
  assert.equal(several.name, 'Galaxy A54')
  assert.equal(several.unread, 7)
  assert.equal(several.webcam, true)
  const empty = plain(L.barModel(L.parseStatus(await fixture('no-phones.json'), FRESH, 30), opts))
  assert.equal(empty.shown, true)
  assert.equal(empty.quiet, false)
  assert.equal(empty.dim, true)
  assert.equal(empty.batteryText, '')
})

test('actions use fixed argv and name the phone only when several are listed', async () => {
  const record = plain(L.parseStatus(await fixture('several-phones.json'), FRESH, 30))
  const [tab, a54, bad] = record.phones
  assert.deepEqual(plain(L.actionArgs('', a54, 3)), ['androlink'])
  assert.deepEqual(plain(L.actionArgs('--ring', a54, 3)), ['androlink', '--ring', 'a54-0f3c9e'])
  assert.deepEqual(plain(L.actionArgs('--ring-stop', tab, 3)), ['androlink', '--ring-stop', 'tab-s9-77aa'])
  assert.deepEqual(plain(L.actionArgs('--send-clipboard', a54, 1)), ['androlink', '--send-clipboard'])
  assert.deepEqual(plain(L.actionArgs('--dex', a54, 1)), ['androlink', '--dex'])
  assert.deepEqual(plain(L.actionArgs('--webcam-stop', a54, 3)), ['androlink', '--webcam-stop'])
  assert.equal(L.actionArgs('--dex', bad, 3), null, 'no safe id, no device action')
  assert.deepEqual(plain(L.actionArgs('--dex', bad, 1)), ['androlink', '--dex'])
  for (const flag of ['--webcam-start', '--ring; rm -rf ~', 'ring', undefined, null])
    assert.equal(L.actionArgs(flag, a54, 1), null, String(flag))
})

test('CLI exit codes map to the panel messages', () => {
  assert.equal(L.exitKind(0, true), '')
  assert.equal(L.exitKind(1, true), 'notRunning')
  assert.equal(L.exitKind(2, true), 'noPhone')
  assert.equal(L.exitKind(101, true), 'failed')
  assert.equal(L.exitKind(-1, true), 'failed')
  assert.equal(L.exitKind(0, false), 'missingCli')
})

function phoneRecord(level, charging, extra = {}) {
  return L.parseStatus(JSON.stringify({
    version: 1, updated: UPDATED, running: true,
    phones: [{ id: 'a54', name: 'Galaxy A54', connected: true, route: 'lan', battery: level === null ? null : { level, charging }, helper: 'running', unread: 0, ringing: false, webcam: false, ...extra }],
  }), FRESH, 30)
}

function run(steps, threshold = 20, margin = 5) {
  let armed = {}
  const fired = []
  for (const record of steps) {
    const out = L.reminderStep(armed, record, threshold, margin)
    armed = plain(out.armed)
    fired.push(plain(out.fire).map((f) => f.level))
  }
  return fired
}

test('the low-battery reminder fires once per discharge cycle', () => {
  assert.deepEqual(run([phoneRecord(30, false), phoneRecord(21, false), phoneRecord(20, false),
    phoneRecord(19, false), phoneRecord(10, false), phoneRecord(3, false)]), [[], [], [20], [], [], []])
  // Already low when first seen: one reminder.
  assert.deepEqual(run([phoneRecord(12, false), phoneRecord(11, false)]), [[12], []])
  const fire = plain(L.reminderStep({}, phoneRecord(18, false), 20, 5).fire)
  assert.deepEqual(fire, [{ key: 'id:a54', name: 'Galaxy A54', level: 18 }])
})

test('charging or climbing past threshold plus margin re-arms the reminder', () => {
  // Charging re-arms even below the threshold.
  assert.deepEqual(run([phoneRecord(18, false), phoneRecord(18, true), phoneRecord(17, false)]), [[18], [], [17]])
  // Climbing to threshold + margin re-arms; hovering just under it does not.
  assert.deepEqual(run([phoneRecord(19, false), phoneRecord(24, false), phoneRecord(19, false)]), [[19], [], []])
  assert.deepEqual(run([phoneRecord(19, false), phoneRecord(25, false), phoneRecord(19, false)]), [[19], [], [19]])
  // Custom threshold and margin.
  assert.deepEqual(run([phoneRecord(30, false), phoneRecord(39, false), phoneRecord(30, false)], 30, 10), [[30], [], []])
  assert.deepEqual(run([phoneRecord(30, false), phoneRecord(40, false), phoneRecord(30, false)], 30, 10), [[30], [], [30]])
})

test('stale, stopped, disconnected and battery-less readings never fire or re-arm', () => {
  const stale = L.parseStatus(JSON.stringify({
    version: 1, updated: UPDATED, running: true,
    phones: [{ id: 'a54', name: 'A54', connected: true, battery: { level: 5, charging: false } }],
  }), UPDATED + 1000, 30)
  assert.deepEqual(run([stale]), [[]])
  assert.deepEqual(run([L.parseStatus(null, FRESH, 30)]), [[]])
  assert.deepEqual(run([phoneRecord(5, false, { connected: false })]), [[]])
  assert.deepEqual(run([phoneRecord(null, false)]), [[]])
  // A disconnect in the middle of a cycle keeps the reminder spent.
  assert.deepEqual(run([phoneRecord(15, false), phoneRecord(15, true, { connected: false }), phoneRecord(14, false)]), [[15], [], []])
  // A charging reading while stale does not re-arm either.
  const staleCharging = L.parseStatus(JSON.stringify({
    version: 1, updated: UPDATED, running: true,
    phones: [{ id: 'a54', name: 'A54', connected: true, battery: { level: 15, charging: true } }],
  }), UPDATED + 1000, 30)
  assert.deepEqual(run([phoneRecord(15, false), staleCharging, phoneRecord(14, false)]), [[15], [], []])
})

test('the reminder tracks each phone separately and keeps unknown keys', async () => {
  const two = L.parseStatus(JSON.stringify({
    version: 1, updated: UPDATED, running: true,
    phones: [
      { id: 'a', name: 'A', connected: true, battery: { level: 10, charging: false } },
      { id: 'b', name: 'B', connected: true, battery: { level: 50, charging: false } },
      { id: '', name: 'C', connected: true, battery: { level: 9, charging: false } },
    ],
  }), FRESH, 30)
  const out = L.reminderStep({ 'id:gone': false }, two, 20, 5)
  assert.deepEqual(plain(out.fire).map((f) => f.key), ['id:a', 'name:C'])
  assert.deepEqual(plain(out.armed), { 'id:gone': false, 'id:a': false, 'id:b': true, 'name:C': false })
  // Bad threshold and margin fall back to 20 and 5.
  assert.deepEqual(plain(L.reminderStep({}, phoneRecord(20, false), 'x', null).fire).map((f) => f.level), [20])
})
