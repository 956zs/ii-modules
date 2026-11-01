import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = await readFile(new URL('../AulaKeysLogic.js', import.meta.url), 'utf8')
const context = vm.createContext({})
vm.runInContext(source.replace('.pragma library', ''), context)
const L = context
// Objects and arrays cross the vm context boundary; copy before deepEqual.
const plain = value => JSON.parse(JSON.stringify(value))

test('parseKeyList keeps valid codes in order and falls back to Z/X', () => {
  assert.deepEqual(plain(L.parseKeyList('KeyZ,KeyX')), ['KeyZ', 'KeyX'])
  assert.deepEqual(plain(L.parseKeyList(' KeyD  KeyF ; KeyJ,KeyK ')), ['KeyD', 'KeyF', 'KeyJ', 'KeyK'])
  assert.deepEqual(plain(L.parseKeyList('KeyZ,KeyZ,Space')), ['KeyZ', 'Space'])
  assert.deepEqual(plain(L.parseKeyList('KeyZ,bad-name,$(rm),z')), ['KeyZ'])
  for (const empty of ['', '   ', ',,', 'nope lower', undefined, null, 42]) {
    assert.deepEqual(plain(L.parseKeyList(empty)), ['KeyZ', 'KeyX'], `input ${String(empty)}`)
  }
  const many = Array.from({ length: 30 }, (_, i) => `Key${String.fromCharCode(65 + (i % 26))}${i}`).join(',')
  assert.equal(L.parseKeyList(many).length, L.MAX_KEYS)
})

test('keyLabel and feedArgs', () => {
  assert.equal(L.keyLabel('KeyZ'), 'Z')
  assert.equal(L.keyLabel('Digit7'), '7')
  assert.equal(L.keyLabel('Semicolon'), ';')
  assert.equal(L.keyLabel('Space'), 'Space')
  assert.equal(L.keyLabel('F13'), 'F13')
  assert.equal(L.keyLabel(''), '?')
  assert.equal(L.keyLabel(undefined), '?')
  assert.deepEqual(plain(L.feedArgs(['KeyZ', 'KeyX'], 0)), ['feed', '--keys', 'KeyZ,KeyX'])
  assert.deepEqual(plain(L.feedArgs(['KeyD'], 60)), ['feed', '--keys', 'KeyD', '--depth-hz', '60'])
  assert.deepEqual(plain(L.feedArgs(['KeyD'], 'x')), ['feed', '--keys', 'KeyD'])
  assert.deepEqual(plain(L.feedArgs(['KeyD'], -5)), ['feed', '--keys', 'KeyD'])
})

test('parseLine accepts every contract line', () => {
  assert.deepEqual(plain(L.parseLine('{"type":"status","state":"waiting","reason":"no keyboard"}')),
    { type: 'status', state: 'waiting', reason: 'no keyboard' })
  const hello = L.parseLine(JSON.stringify({
    type: 'hello', product: 'SI2825KZHEARGB', firmware: '3.17.07', max_mm: 3.4,
    keys: [{ code: 'KeyZ', label: 'Z', idx: 89, x: 1.75, y: 3, w: 1, mode: 'rt', point: 1, press: 0.5, release: 0.5 },
      { code: 'KeyX', label: '', point: 'bad' }, { label: 'no code' }, null]
  }))
  assert.equal(hello.type, 'hello')
  assert.equal(hello.maxMm, 3.4)
  assert.equal(hello.firmware, '3.17.07')
  assert.deepEqual(plain(hello.keys), [
    { code: 'KeyZ', label: 'Z', mode: 'rt', point: 1, press: 0.5, release: 0.5 },
    { code: 'KeyX', label: 'X', mode: '', point: 0, press: 0, release: 0 }
  ])
  assert.deepEqual(plain(L.parseLine('{"type":"depth","t":1234.5,"key":"KeyZ","mm":1.23}')),
    { type: 'depth', t: 1234.5, key: 'KeyZ', mm: 1.23 })
  assert.deepEqual(plain(L.parseLine('{"type":"press","t":1234.6,"key":"KeyZ"}')), { type: 'press', t: 1234.6, key: 'KeyZ' })
  assert.deepEqual(plain(L.parseLine('{"type":"release","t":1301,"key":"KeyZ"}\r')), { type: 'release', t: 1301, key: 'KeyZ' })
  assert.deepEqual(plain(L.parseLine('{"type":"error","msg":"boom"}')), { type: 'error', msg: 'boom' })
})

test('parseLine rejects junk and tolerates loose fields', () => {
  for (const junk of ['', '  ', 'not json', '{', '[]', 'null', '{"type":"dance"}', '{"type":"status","state":"ok"}',
    '{"type":"depth","key":"KeyZ"}', '{"type":"depth","mm":1}', '{"type":"depth","key":"KeyZ","mm":"x"}',
    '{"type":"press"}', '{"type":"press","key":""}', undefined, null, 5]) {
    assert.equal(L.parseLine(junk), null, `junk ${JSON.stringify(junk)}`)
  }
  assert.equal(L.parseLine('{"type":"depth","key":"KeyZ","mm":-0.2,"t":1}').mm, 0)
  assert.ok(Number.isNaN(L.parseLine('{"type":"press","key":"KeyZ"}').t))
  assert.deepEqual(plain(L.parseLine('{"type":"hello"}').keys), [])
  assert.equal(L.parseLine('{"type":"hello","max_mm":-1}').maxMm, 0)
})

test('statusKind and travelFraction', () => {
  assert.equal(L.statusKind(L.parseLine('{"type":"status","state":"waiting","reason":"busy"}')), 'busy')
  assert.equal(L.statusKind(L.parseLine('{"type":"status","state":"waiting","reason":"no keyboard"}')), 'waiting')
  assert.equal(L.statusKind(L.parseLine('{"type":"status","state":"lost","reason":"busy"}')), 'lost')
  assert.equal(L.statusKind(L.parseLine('{"type":"error","msg":"x"}')), 'error')
  assert.equal(L.statusKind(L.parseLine('{"type":"press","key":"KeyZ"}')), '')
  assert.equal(L.statusKind(null), '')
  assert.equal(L.travelFraction(1.7, 3.4), 0.5)
  assert.equal(L.travelFraction(5, 3.4), 1)
  assert.equal(L.travelFraction(-1, 3.4), 0)
  assert.equal(L.travelFraction(1, 0), 0)
  assert.equal(L.travelFraction('x', 3.4), 0)
})

test('counts, KPS window and peak', () => {
  const s = L.newStats()
  assert.equal(L.kps(s, 0), 0)
  // 10 presses 50 ms apart on the feed clock.
  for (let i = 0; i < 10; i++) L.recordPress(s, i % 2 ? 'KeyX' : 'KeyZ', 1000 + i * 50, 5000 + i * 50)
  assert.equal(s.total, 10)
  assert.equal(s.counts.KeyZ, 5)
  assert.equal(s.counts.KeyX, 5)
  assert.equal(s.peak, 10)
  // Last press at t=1450, received at wall 5450. 400 ms later all ten are
  // still within 1 s; at 1001 ms past the first press it has left the window.
  assert.equal(L.kps(s, 5850), 10)
  assert.equal(L.kps(s, 6000), 9)
  // Boundary: a press exactly windowMs old is out.
  assert.equal(L.kps(s, 5450 + 1000), 0)
  assert.equal(s.peak, 10)
  assert.equal(s.total, 10)
  L.resetCounts(s)
  assert.equal(s.total, 0)
  assert.equal(s.peak, 0)
  assert.deepEqual(plain(s.counts), {})
  assert.equal(L.kps(s, 9999), 0)
})

test('KPS survives untimed events and resets on a new feed clock', () => {
  const s = L.newStats()
  assert.equal(L.recordPress(s, 'KeyZ', NaN, 100), 1)
  assert.equal(L.recordPress(s, 'KeyZ', NaN, 300), 2)
  assert.equal(L.kps(s, 1200), 1)
  const t = L.newStats()
  L.recordPress(t, 'KeyZ', 5000, 0)
  L.recordPress(t, 'KeyZ', 5100, 100)
  // A new process starts its clock at 0: old presses must not linger.
  assert.equal(L.recordPress(t, 'KeyZ', 10, 150), 1)
  assert.equal(t.total, 3)
  assert.equal(t.peak, 2)
  L.syncClock(t, 20, 160)
  assert.equal(L.feedNow(t, 200), 60)
  assert.equal(L.kps(t, 200, 2000), 1)
})

test('wantVisible per mode', () => {
  const states = ['off', 'idle', 'menu', 'playing', 'cooldown', undefined]
  const table = {
    playing: [false, false, false, true, false, false],
    focused: [false, false, true, true, true, false],
    always: [true, true, true, true, true, true],
    off: [false, false, false, false, false, false]
  }
  for (const [mode, expected] of Object.entries(table)) {
    assert.deepEqual(states.map(s => L.wantVisible(mode, s)), expected, mode)
  }
  assert.equal(L.wantVisible('garbage', 'playing'), true)
  assert.equal(L.wantVisible(undefined, 'menu'), false)
  assert.equal(L.normalizeMode('x'), 'playing')
  assert.equal(L.normalizeCorner('topLeft'), 'topLeft')
  assert.equal(L.normalizeCorner(''), 'bottomRight')
})

test('stepVisibility shows at once and lingers before hiding', () => {
  let m = { visible: false, hideAt: 0 }
  m = L.stepVisibility(m, true, 0, 3000)
  assert.deepEqual(plain(m), { visible: true, hideAt: 0 })
  m = L.stepVisibility(m, false, 1000, 3000)
  assert.deepEqual(plain(m), { visible: true, hideAt: 4000 })
  // Re-stepping before the deadline keeps the original deadline.
  assert.deepEqual(plain(L.stepVisibility(m, false, 2000, 3000)), { visible: true, hideAt: 4000 })
  // Wanted again inside the linger: stays up, deadline cleared.
  assert.deepEqual(plain(L.stepVisibility(m, true, 2000, 3000)), { visible: true, hideAt: 0 })
  // Boundary: hides exactly at the deadline.
  assert.deepEqual(plain(L.stepVisibility(m, false, 4000, 3000)), { visible: false, hideAt: 0 })
  assert.deepEqual(plain(L.stepVisibility({ visible: true, hideAt: 0 }, false, 5, 0)), { visible: false, hideAt: 0 })
  assert.deepEqual(plain(L.stepVisibility(null, false, 5, 3000)), { visible: false, hideAt: 0 })
  assert.deepEqual(plain(L.stepVisibility(undefined, true, 5, 'x')), { visible: true, hideAt: 0 })
})

test('backoff doubles up to the cap', () => {
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6, 100].map(n => L.backoffMs(n)), [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000])
  assert.equal(L.backoffMs(-3), 1000)
  assert.equal(L.backoffMs('x'), 1000)
  assert.equal(L.clamp('9', 0, 5, 1), 5)
  assert.equal(L.clamp(undefined, 0, 5, 1), 1)
})

test('vendored OsuStateLogic.js matches osu_indicator apart from its header', async () => {
  const upstream = await readFile(new URL('../../osu_indicator/OsuStateLogic.js', import.meta.url), 'utf8')
  const vendored = await readFile(new URL('../OsuStateLogic.js', import.meta.url), 'utf8')
  const body = text => text.slice(text.indexOf('// Pure helpers'))
  assert.equal(body(vendored), body(upstream))
})

test('the fake feeder speaks the contract', async () => {
  const { spawn } = await import('node:child_process')
  const child = spawn('bash', [new URL('./feeder.sh', import.meta.url).pathname, 'feed', '--keys', 'KeyD,KeyF', '--depth-hz', '60'],
    { env: { ...process.env, FEEDER_KPS: '40' } })
  let out = ''
  child.stdout.on('data', chunk => { out += chunk })
  await new Promise(resolve => setTimeout(resolve, 1600))
  child.kill('SIGTERM')
  const code = await new Promise(resolve => child.on('exit', resolve))
  assert.equal(code, 0)
  const lines = out.split('\n').filter(line => line !== '')
  const events = lines.map(line => L.parseLine(line))
  assert.ok(events.every(Boolean), 'every line parses')
  assert.equal(events[0].type, 'status')
  assert.equal(events[1].type, 'hello')
  assert.deepEqual(plain(events[1].keys.map(k => k.code)), ['KeyD', 'KeyF'])
  const presses = events.filter(e => e.type === 'press')
  assert.ok(presses.length >= 2, `presses ${presses.length}`)
  assert.ok(presses.every(e => Number.isFinite(e.t)))
  const stats = L.newStats()
  for (const e of presses) L.recordPress(stats, e.key, e.t, 0)
  assert.equal(stats.total, presses.length)
})

test('keycap colours: gradient, luminance and legend contrast', () => {
  assert.equal(L.fillAlpha(0, false), L.FILL_ALPHA_TOP)
  assert.equal(L.fillAlpha(1, false), L.FILL_ALPHA_BOTTOM)
  assert.ok(L.fillAlpha(1, true) > L.fillAlpha(1, false))
  assert.ok(L.fillAlpha(1, true) <= 1)
  assert.equal(L.fillAlpha(-3, false), L.FILL_ALPHA_TOP)
  assert.equal(L.fillAlpha('x', false), L.FILL_ALPHA_TOP)
  const black = { r: 0, g: 0, b: 0 }
  const white = { r: 1, g: 1, b: 1 }
  assert.equal(L.luminance(black), 0)
  assert.equal(L.luminance(white), 1)
  assert.equal(L.luminance(null), 0)
  assert.ok(Math.abs(L.contrastRatio(black, white) - 21) < 1e-9)
  const darkCap = { r: 0.12, g: 0.12, b: 0.14 }
  const lightAccent = { r: 0.95, g: 0.9, b: 1 }
  // Below half travel the legend sits on the bare cap.
  assert.deepEqual(plain(L.legendBackdrop(darkCap, lightAccent, 0.4, false)), plain(darkCap))
  const covered = L.legendBackdrop(darkCap, lightAccent, 1, true)
  assert.ok(covered.r > darkCap.r && covered.r < lightAccent.r)
  // Boundary: at exactly half travel the centre is the fill's faint top edge.
  const edge = L.legendBackdrop(darkCap, lightAccent, 0.5, false)
  assert.ok(Math.abs(edge.r - (darkCap.r + (lightAccent.r - darkCap.r) * L.FILL_ALPHA_TOP)) < 1e-9)
  // A light accent over a dark cap keeps the light legend at full travel.
  const lightText = { r: 0.9, g: 0.9, b: 0.92 }
  assert.equal(L.pickContrast(covered, lightText, darkCap), 0)
  assert.deepEqual(plain(L.legendBackdrop(null, lightAccent, 1, true)), plain(black))
  assert.deepEqual(plain(L.legendBackdrop(darkCap, null, 1, true)), plain(darkCap))
  assert.equal(L.pickContrast(darkCap, white, black), 0)
  assert.equal(L.pickContrast(white, white, black), 1)
  assert.equal(L.normalizeTravelStyle('bar'), 'bar')
  assert.equal(L.normalizeTravelStyle('fancy'), 'fill')
  assert.equal(L.normalizeTravelStyle(undefined), 'fill')
})

test('presetFor recognises presets regardless of separators', () => {
  assert.equal(L.presetFor('KeyZ,KeyX'), 'standard')
  assert.equal(L.presetFor(' KeyZ  KeyX '), 'standard')
  assert.equal(L.presetFor('KeyD;KeyF;KeyJ;KeyK'), 'mania4k')
  assert.equal(L.presetFor(L.PRESETS.mania7k), 'mania7k')
  assert.equal(L.presetFor('KeyX,KeyZ'), 'custom')
  assert.equal(L.presetFor('KeyA,KeyS'), 'custom')
  // Empty or invalid falls back to the default list, which is the standard preset.
  assert.equal(L.presetFor(''), 'standard')
  assert.equal(L.presetFor(undefined), 'standard')
})

test('barState covers every mode and feed status', () => {
  assert.equal(L.barState('off', true, ''), 'off')
  assert.equal(L.barState('playing', false, ''), 'hidden')
  assert.equal(L.barState('always', true, ''), 'live')
  assert.equal(L.barState('always', true, 'starting'), 'starting')
  for (const status of ['waiting', 'busy', 'lost', 'error', 'restarting']) {
    assert.equal(L.barState('focused', true, status), 'warn', status)
  }
  assert.equal(L.barState('bogus', true, ''), 'live')
  assert.equal(L.barState(undefined, false, undefined), 'hidden')
})

test('parseResults reads only an explicit true', () => {
  assert.equal(L.parseResults('{"state":"cooldown","since":1,"results":true}'), true)
  assert.equal(L.parseResults('{"state":"cooldown","since":1,"results":false}'), false)
  assert.equal(L.parseResults('{"state":"cooldown","since":1}'), false)
  for (const junk of ['', '  ', 'nope', 'null', '[]', '{"results":"true"}', '{"results":1}', undefined, null]) {
    assert.equal(L.parseResults(junk), false, `junk ${JSON.stringify(junk)}`)
  }
  assert.equal(L.normalizeKeepAfterPlay('delay'), 'delay')
  assert.equal(L.normalizeKeepAfterPlay('forever'), 'results')
  assert.equal(L.newPlayStarted(0, 'playing', 100), true)
  assert.equal(L.newPlayStarted(100, 'playing', 100), false)
  assert.equal(L.newPlayStarted(100, 'cooldown', 200), false)
})

// Mirrors main.qml: osu-state samples drive wantVisible -> stepVisibility;
// counters reset when the overlay appears or a new play starts. Each sample
// is [ms, state, since, results]; the linger timer is stepped at hideAt.
function simulate(samples, { mode = 'playing', keep = 'results', lingerMs = 3000 } = {}) {
  let machine = { visible: false, hideAt: 0 }
  let lastPlaySince = 0
  const out = []
  const step = (now, want) => {
    const wasShown = machine.visible
    machine = L.stepVisibility(machine, want, now, lingerMs)
    return !wasShown && machine.visible
  }
  let want = false
  for (let i = 0; i < samples.length; i++) {
    const [now, state, since, results] = samples[i]
    // Fire a pending linger deadline that falls before this sample.
    if (machine.hideAt > 0 && machine.hideAt <= now) step(machine.hideAt, want)
    want = L.wantVisible(mode, state, results, keep)
    let reset = step(now, want)
    if (L.newPlayStarted(lastPlaySince, state, since)) {
      lastPlaySince = since
      reset = reset || machine.visible
    }
    out.push({ state, visible: machine.visible, reset })
  }
  return out
}

test('results screen keeps the overlay up until it closes', () => {
  const r = simulate([
    [0, 'menu', 1, false],
    [1000, 'playing', 2, false],
    [60000, 'cooldown', 3, true], // results screen
    [90000, 'cooldown', 3, true], // still reading results
    [95000, 'menu', 4, false], // results closed
    [97000, 'menu', 4, false], // within the 3 s linger
    [99000, 'menu', 4, false] // past it
  ])
  assert.deepEqual(r.map(x => x.visible), [false, true, true, true, true, true, false])
  assert.deepEqual(r.map(x => x.reset), [false, true, false, false, false, false, false])
})

test('quitting without results hides after the linger', () => {
  const r = simulate([
    [0, 'playing', 1, false],
    [20000, 'cooldown', 2, false], // quit: short cooldown, no results
    [22000, 'menu', 3, false],
    [23001, 'menu', 3, false]
  ])
  assert.deepEqual(r.map(x => x.visible), [true, true, true, false])
})

test('retry from the results screen resets on the new play, not on results', () => {
  const r = simulate([
    [0, 'playing', 1, false],
    [50000, 'cooldown', 2, true],
    [55000, 'playing', 3, false], // retry
    [56000, 'playing', 3, false]
  ])
  assert.deepEqual(r.map(x => x.visible), [true, true, true, true])
  assert.deepEqual(r.map(x => x.reset), [true, false, true, false])
})

test('absent results field and keep=delay both fall back to the linger', () => {
  const samples = [
    [0, 'playing', 1, undefined],
    [50000, 'cooldown', 2, undefined],
    [52000, 'cooldown', 2, undefined],
    [54000, 'cooldown', 2, undefined]
  ]
  assert.deepEqual(simulate(samples).map(x => x.visible), [true, true, true, false])
  const withResults = samples.map(([t, s, since], i) => [t, s, since, i > 0])
  assert.deepEqual(simulate(withResults, { keep: 'delay' }).map(x => x.visible), [true, true, true, false])
  assert.deepEqual(simulate(withResults).map(x => x.visible), [true, true, true, true])
  // focused mode already covers cooldown; results also count there.
  assert.equal(L.wantVisible('focused', 'idle', true, 'results'), true)
  assert.equal(L.wantVisible('focused', 'idle', true, 'delay'), false)
  assert.equal(L.wantVisible('always', 'off', false, 'delay'), true)
  assert.equal(L.wantVisible('off', 'playing', true, 'results'), false)
})
