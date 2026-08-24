import assert from 'node:assert/strict'
import { readFile, readdir } from 'node:fs/promises'
import test from 'node:test'

const moduleRoot = new URL('../', import.meta.url)

async function read(name) {
  return readFile(new URL(name, moduleRoot), 'utf8')
}

test('samplers poll only while a consumer surface can see the data', async () => {
  const bar = await read('bar.qml')

  // /proc/meminfo: bar pill visible OR the panel open — otherwise silent.
  assert.match(bar, /MemInfo \{[\s\S]*?active: barGroup\.visible \|\| \(panelLoader\.item\?\.visible \?\? false\)/)
  // ps: strictly panel-open only; spawns nothing otherwise.
  assert.match(bar, /ProcTop \{[\s\S]*?active: panelLoader\.active && \(panelLoader\.item\?\.visible \?\? false\)/)
  // The samplers' own gates: timers keyed to `active`, immediate resample on
  // reactivation instead of waiting a full interval.
  const memInfo = await read('MemInfo.qml')
  assert.match(memInfo, /running: root\.active/)
  assert.match(memInfo, /onActiveChanged: if \(active\) resample\(\)/)
  const procTop = await read('ProcTop.qml')
  assert.match(procTop, /running: root\.active/)
})

test('bar hides via the showBar option and clamps config values', async () => {
  const bar = await read('bar.qml')
  assert.match(bar, /visible: cfg\.options\.showBar !== false/)
  assert.match(bar, /meminfoInterval >= 500 \? cfg\.options\.meminfoInterval : 2000/)
  assert.match(bar, /procInterval >= 1000 \? cfg\.options\.procInterval : 4000/)
  assert.match(bar, /blockCount > 0 \? cfg\.options\.blockCount : 12/)
  assert.match(bar, /Math\.min\(0\.96, Math\.max\(0\.5,/)
})

test('LazyLoader bindings never self-shadow their ids (memInfo/procTop gotcha)', async () => {
  const bar = await read('bar.qml')
  // Slice from the object declaration, not the first mention: an earlier
  // comment cites the `mem: mem` anti-pattern verbatim.
  const loaderStart = bar.indexOf('LazyLoader {')
  assert.notEqual(loaderStart, -1)
  const loaderBlock = bar.slice(loaderStart)
  assert.match(loaderBlock, /mem: memInfo/)
  assert.match(loaderBlock, /procs: procTop/)
  // `mem: mem` / `procs: procs` inside a LazyLoader component resolves to the
  // property itself (permanently undefined) — the exact bug this module hit.
  assert.doesNotMatch(loaderBlock, /\bmem: mem\b/)
  assert.doesNotMatch(loaderBlock, /\bprocs: procs\b/)
})

test('panel toggle is reachable via IPC and debounces the focus-grab close', async () => {
  const bar = await read('bar.qml')
  assert.match(bar, /IpcHandler \{[\s\S]*?target: "memory_center"/)
  assert.match(bar, /Date\.now\(\) - panel\.lastCloseTime > 300/)
})

test('panel shell closes on click-outside and Esc, and records close time', async () => {
  const shell = await read('PanelShell.qml')
  assert.match(shell, /HyprlandFocusGrab \{[\s\S]*?active: root\.visible[\s\S]*?onCleared: root\.visible = false/)
  assert.match(shell, /Keys\.onEscapePressed: root\.visible = false/)
  assert.match(shell, /onVisibleChanged: if \(!visible\) lastCloseTime = Date\.now\(\)/)
})

test('privilege escalation: pkexec first, single sudo -A fallback, dismissal stops', async () => {
  const actions = await read('Actions.qml')
  assert.match(actions, /\["pkexec", "sh", "-c", root\.script\]/)
  // Interactive sudo is never used; the one fallback goes through askpass.
  assert.match(actions, /\["sudo", "-A", "sh", "-c", root\.script\]/)
  // Exit 126 = auth dialog dismissed: back to idle, no sudo nag.
  assert.match(actions, /if \(exitCode === 126\) \{[\s\S]*?root\.phase = "idle"[\s\S]*?return/)
  // The fallback fires at most once.
  assert.match(actions, /if \(!root\.triedSudo\) \{[\s\S]*?root\.triedSudo = true[\s\S]*?sudoProc\.running = true/)
})

test('kill affordance: own processes only, two clicks, SIGTERM, arming decays', async () => {
  const panel = await read('MemPanel.qml')
  assert.match(panel, /\["kill", "-15", String\(pid\)\]/)
  assert.match(panel, /if \(!block\.modelData\.own\)\s*\n\s*return/)
  assert.match(panel, /panel\.armedPid = block\.modelData\.pid[\s\S]*?disarmTimer\.restart\(\)/)
  assert.match(panel, /id: disarmTimer[\s\S]*?onTriggered: panel\.armedPid = -1/)
})

test('swap compaction is gated on safety and the Other strip only shows with a tail', async () => {
  const panel = await read('MemPanel.qml')
  assert.match(panel, /swapTrimOk: mem\.swapUsedKb > 0 && mem\.memAvailable > mem\.swapUsedKb/)
  assert.match(panel, /visible: procs\.otherKb > 0/)
  // blockRows re-evaluates per sample via the revision counter.
  assert.match(panel, /readonly property var blockRows: \{\s*\n\s*procs\.revision/)
})

test('every file using Translation.tr imports qs.services', async () => {
  const entries = await readdir(moduleRoot)
  for (const name of entries.filter(n => n.endsWith('.qml'))) {
    const text = await read(name)
    if (text.includes('Translation.tr('))
      assert.match(text, /^import qs\.services$/m, `${name} misses import qs.services`)
  }
})
