import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const moduleRoot = new URL('../', import.meta.url)
const barContent = 'modules/ii/bar/BarContent.qml'
const sysTray = 'modules/ii/bar/SysTray.qml'

async function loadContract() {
  const [manifestSource, controller] = await Promise.all([
    readFile(new URL('module.json', moduleRoot), 'utf8'),
    readFile(new URL('FitController.qml', moduleRoot), 'utf8'),
  ])
  return { manifest: JSON.parse(manifestSource), controller }
}

function contentFor(manifest, file) {
  return manifest.patches.filter((patch) => patch.file === file).map((patch) => patch.content).join('\n')
}

test('patches are insert-only and limited to the horizontal bar and its tray', async () => {
  const { manifest } = await loadContract()
  for (const patch of manifest.patches) {
    assert.ok([barContent, sysTray].includes(patch.file), patch.file)
    assert.ok(['insert-after', 'insert-before'].includes(patch.op), patch.op)
    assert.doesNotMatch(patch.content, />>> iimp |<<< iimp /)
  }
})

test('every anchor is guarded by a probe on the same file', async () => {
  const { manifest } = await loadContract()
  for (const patch of manifest.patches) {
    const guarded = manifest.compat.probes.some(
      (probe) => probe.type === 'file-contains' && probe.path === patch.file && probe.pattern.includes(patch.anchor),
    )
    assert.ok(guarded, `${patch.file}: ${patch.anchor}`)
  }
})

test('both centre side groups receive the same fitted width', async () => {
  const { manifest } = await loadContract()
  const bar = contentFor(manifest, barContent)
  for (const target of ['leftCenterGroup', 'rightCenterGroup']) {
    assert.match(
      bar,
      new RegExp(`target: ${target}\\n\\s*property: "implicitWidth"\\n\\s*value: adaptiveBarFit\\.side\\n`),
    )
  }
  assert.match(bar, /target: barRightSideMouseArea\n\s*property: "clip"\n\s*value: adaptiveBarFit\.overflow > 0/)
})

test('the bar wires the controller to the tray it folds', async () => {
  const { manifest } = await loadContract()
  const bar = contentFor(manifest, barContent)
  assert.match(bar, /import qs\.mod\.adaptive_bar as AdaptiveBar/)
  assert.match(bar, /AdaptiveBar\.FitController \{\n\s*id: adaptiveBarFit/)
  assert.match(bar, /tray: adaptiveBarTray/)
  assert.match(bar, /id: adaptiveBarTray\n\s*adaptiveBarFoldCount: adaptiveBarFit\.fold/)
  for (const id of ['middleSection', 'leftCenterGroup', 'rightCenterGroup', 'rightCenterGroupContent', 'rightSectionRowLayout']) {
    assert.match(bar, new RegExp(`: ${id}\\n`), id)
  }
})

test('the tray exposes every property the controller reads', async () => {
  const { manifest, controller } = await loadContract()
  const tray = contentFor(manifest, sysTray)
  const read = new Set(controller.match(/adaptiveBar[A-Z]\w*/g))
  assert.ok(read.size > 0)
  for (const name of read)
    assert.match(tray, new RegExp(`property \\w+ ${name}:`), name)
  assert.match(tray, /property int adaptiveBarFoldCount: 0\n/)
})

test('folded icons leave the bar and join the overflow menu', async () => {
  const { manifest } = await loadContract()
  const tray = contentFor(manifest, sysTray)
  // The first N pinned icons hide in the bar...
  assert.match(tray, /required property int index\n\s*visible: index >= root\.adaptiveBarFolded\n/)
  // ...and lead the overflow model, which only overrides stock while folding.
  assert.match(tray, /for \(let i = 0; i < root\.adaptiveBarFolded; i\+\+\)\n\s*items\.push\(root\.pinnedItems\[i\]\)/)
  assert.match(tray, /id: adaptiveBarOverflowRepeater\n/)
  for (const [target, property] of [
    ['adaptiveBarOverflowRepeater', 'model'],
    ['trayOverflowLayout', 'columns'],
    ['trayOverflowButton', 'visible'],
    ['overflowPopup', 'active'],
  ]) {
    assert.match(
      tray,
      new RegExp(`target: ${target}\\n\\s*property: "${property}"\\n[^}]*when: root\\.adaptiveBarFolded > 0\\n`),
      `${target}.${property}`,
    )
  }
})
