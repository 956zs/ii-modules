import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = await readFile(new URL('../OsuStateLogic.js', import.meta.url), 'utf8')
const context = vm.createContext({})
vm.runInContext(source.replace('.pragma library', ''), context)
const L = context

const playing = JSON.stringify({ state: 'playing', since: 100, beatmap: 'A - B (m) [Hard]', updated: 100, pid: 1 })
const cooldown = JSON.stringify({ state: 'cooldown', since: 200, beatmap: 'A - B (m) [Hard]', cooldown_until: 320, updated: 200, pid: 1 })

test('parseState accepts the daemon contract and rejects everything else', () => {
  const p = L.parseState(playing)
  assert.equal(p.state, 'playing')
  assert.equal(p.since, 100)
  assert.equal(p.beatmap, 'A - B (m) [Hard]')
  assert.equal(p.cooldownUntil, 0)
  assert.equal(p.valid, true)
  const c = L.parseState(cooldown)
  assert.equal(c.state, 'cooldown')
  assert.equal(c.cooldownUntil, 320)
  for (const junk of ['', '   ', 'nope', '[]', '{"state":"dancing"}', '{"state":5}', 'null', undefined, null]) {
    const r = L.parseState(junk)
    assert.equal(r.state, 'off', `junk ${JSON.stringify(junk)}`)
    assert.equal(r.valid, false)
  }
  assert.equal(L.parseState('{"state":"idle","since":"12.7","beatmap":null}').since, 12)
  assert.equal(L.parseState('{"state":"idle","since":-5}').since, 0)
  assert.equal(L.parseState('{"state":"idle","beatmap":"  x  "}').beatmap, 'x')
})

test('visibility switches only affect idle and menu', () => {
  assert.equal(L.shownFor('off', true, true), false)
  assert.equal(L.shownFor('playing', false, false), true)
  assert.equal(L.shownFor('cooldown', false, false), true)
  assert.equal(L.shownFor('idle', false, true), false)
  assert.equal(L.shownFor('idle', true, true), true)
  assert.equal(L.shownFor('menu', true, false), false)
  assert.equal(L.shownFor('menu', undefined, undefined), true)
  assert.equal(L.shownFor('bogus', true, true), false)
})

test('timing helpers never go negative and format like a clock', () => {
  const p = L.parseState(playing)
  assert.equal(L.elapsed(p, 161), 61)
  assert.equal(L.elapsed(p, 50), 0)
  assert.equal(L.elapsed(L.offState(), 50), 0)
  const c = L.parseState(cooldown)
  assert.equal(L.cooldownLeft(c, 300), 20)
  assert.equal(L.cooldownLeft(c, 400), 0)
  assert.equal(L.cooldownLeft(p, 100), 0)
  assert.equal(L.formatDuration(0), '0:00')
  assert.equal(L.formatDuration(61), '1:01')
  assert.equal(L.formatDuration(3599), '59:59')
  assert.equal(L.formatDuration(3661), '1:01:01')
  assert.equal(L.formatDuration(-4), '0:00')
  assert.equal(L.formatDuration('x'), '0:00')
})

test('bar text and ticker follow the state and the timer switch', () => {
  const p = L.parseState(playing)
  const c = L.parseState(cooldown)
  assert.equal(L.barText(p, 190, true), '1:30')
  assert.equal(L.barText(c, 300, true), '0:20')
  assert.equal(L.barText(p, 190, false), '')
  assert.equal(L.barText(L.parseState('{"state":"menu","since":1}'), 50, true), '')
  assert.equal(L.barText(null, 50, true), '')
  assert.equal(L.needsTicker(p, true), true)
  assert.equal(L.needsTicker(c, true), true)
  assert.equal(L.needsTicker(p, false), false)
  assert.equal(L.needsTicker(L.offState(), true), false)
  assert.equal(L.needsTicker(null, true), false)
})

test('beatmap splitting handles the lazer shape and odd input', () => {
  // Objects cross the vm context boundary; copy to plain objects first.
  const split = value => ({ ...L.splitBeatmap(value) })
  assert.deepEqual(split('DJ OKAWARI - Flower Dance (Raijodo) [mapped in jail]'), { title: 'DJ OKAWARI - Flower Dance', mapper: 'Raijodo', difficulty: 'mapped in jail' })
  assert.deepEqual(split('A (feat. B) - C (m) [X]'), { title: 'A (feat. B) - C', mapper: 'm', difficulty: 'X' })
  assert.deepEqual(split('no shape here'), { title: 'no shape here', mapper: '', difficulty: '' })
  assert.deepEqual(split(''), { title: '', mapper: '', difficulty: '' })
  assert.deepEqual(split(undefined), { title: '', mapper: '', difficulty: '' })
})
