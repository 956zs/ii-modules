import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

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
