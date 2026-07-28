import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'

const moduleRoot = new URL('../', import.meta.url)

async function loadContract() {
  const [bridge, bluetoothEntry, bluetoothMenu, wifiMenu, manifestSource] = await Promise.all([
    readFile(new URL('AppletMenuBridge.qml', moduleRoot), 'utf8'),
    readFile(new URL('AppletMenuEntry.qml', moduleRoot), 'utf8'),
    readFile(new URL('AppletMenu.qml', moduleRoot), 'utf8'),
    readFile(new URL('WifiAppletMenu.qml', moduleRoot), 'utf8'),
    readFile(new URL('module.json', moduleRoot), 'utf8'),
  ])
  return {
    bridge,
    bluetoothEntry,
    bluetoothMenu,
    wifiMenu,
    manifest: JSON.parse(manifestSource),
  }
}

function patchesFor(manifest, file) {
  return manifest.patches.filter((patch) => patch.file === file)
}

test('the bridge is hover-only and never competes for mouse buttons', async () => {
  const { bridge } = await loadContract()

  assert.match(bridge, /acceptedButtons:\s*Qt\.NoButton/)
  assert.doesNotMatch(bridge, /acceptedButtons:\s*Qt\.RightButton/)
  assert.doesNotMatch(bridge, /\bonPressed\s*:/)
})

test('the bridge can cancel pending opens and close its popup', async () => {
  const { bridge } = await loadContract()

  assert.match(bridge, /function closeStyledMenu\(\)/)
  assert.match(bridge, /root\.openWhenLoaded = false/)
  assert.match(bridge, /if \(root\.loadedMenu\)\s*\n\s*root\.loadedMenu\.close\(\)/)
  assert.match(
    bridge,
    /function closeStyledMenu\(\)\s*\{[\s\S]*?root\.focusWindow = null[\s\S]*?\}/,
  )
  assert.match(
    bridge,
    /onItemChanged:\s*\{[\s\S]*?if \(!item\)[\s\S]*?root\.focusWindow = null[\s\S]*?\}/,
  )
})

test('inside actions, trigger toggles, and outside clicks share one complete focus grab', async () => {
  const { bridge, bluetoothMenu, wifiMenu } = await loadContract()

  assert.match(bridge, /anchor\s*{/)
  assert.match(bridge, /window:\s*root\.QsWindow\.window/)
  assert.match(bridge, /rect\.x:\s*root\.menuAnchorRect\.x/)
  assert.match(bridge, /HyprlandFocusGrab\s*{/)
  assert.match(bridge, /property var focusWindow:\s*null/)
  assert.match(bridge, /active:\s*root\.focusWindow !== null/)
  assert.match(bridge, /windows:\s*\[root\.QsWindow\.window, root\.focusWindow\]/)
  assert.match(bridge, /onMenuOpened:\s*qsWindow => root\.focusWindow = qsWindow/)
  assert.match(bridge, /onMenuClosed:\s*root\.focusWindow = null/)
  assert.match(
    bridge,
    /onCleared:\s*(?:root\.closeStyledMenu\(\)|\{[\s\S]*?root\.closeStyledMenu\(\)[\s\S]*?\})/,
  )
  for (const [name, source] of [
    ['Bluetooth', bluetoothMenu],
    ['Wi-Fi', wifiMenu],
  ]) {
    assert.match(source, /PopupWindow\s*{/, `${name} uses popup stacking and geometry`)
    assert.doesNotMatch(source, /PanelWindow\s*{/)
    assert.doesNotMatch(source, /GlobalFocusGrab/)
    assert.doesNotMatch(source, /HyprlandFocusGrab/)
  }
})

test('compact device actions center their visible content group', async () => {
  const { bluetoothEntry } = await loadContract()

  assert.match(bluetoothEntry, /readonly property bool centerCompactContent:\s*presentation === "compact"/)
  assert.match(bluetoothEntry, /RowLayout\s*\{[\s\S]*id:\s*compactContent[\s\S]*anchors\.centerIn:\s*parent/)
  assert.match(bluetoothEntry, /visible:\s*root\.menuEntry\.hasChildren[\s\S]*text:\s*"chevron_right"/)
  assert.doesNotMatch(bluetoothEntry, /id:\s*compactTrailing/)
  assert.doesNotMatch(bluetoothEntry, /compactLabel\.implicitWidth \+ 20 \* 2/)
})

test('known applet actions prefer end4 Material icons over unresolved native names', async () => {
  const { bluetoothEntry, wifiMenu } = await loadContract()

  assert.match(bluetoothEntry, /readonly property bool useMaterialIcon:\s*fallbackIcon !== ""/)
  assert.match(bluetoothEntry, /hasNativeIcon:[\s\S]*&& !useMaterialIcon/)
  assert.match(bluetoothEntry, /active:\s*root\.useMaterialIcon/)
  assert.match(bluetoothEntry, /text:\s*root\.fallbackIcon/)
  assert.doesNotMatch(wifiMenu, /sourceComponent:\s*IconImage/)
  assert.match(wifiMenu, /text:\s*root\.materialIcon\(entryButton\.menuEntry\)/)
})

test('menu actions stay open long enough to trigger and reflect D-Bus state updates', async () => {
  const { bluetoothEntry, wifiMenu } = await loadContract()

  assert.match(bluetoothEntry, /property bool dismissAfterTrigger:\s*false/)
  assert.doesNotMatch(
    wifiMenu,
    /menuEntry\.triggered\(\)\s*\n\s*entryButton\.dismiss\(\)/,
  )
})

test('each stock RippleButton owns and dispatches right-click exactly once', async () => {
  const { manifest } = await loadContract()
  const targets = [
    'modules/ii/bar/BarContent.qml',
    'modules/ii/verticalBar/VerticalBarContent.qml',
  ]

  for (const target of targets) {
    const patches = patchesFor(manifest, target)
    const altActions = patches.filter((patch) => patch.content.includes('altAction:'))
    assert.equal(altActions.length, 1, `${target} must define one right-click owner`)

    const content = altActions[0].content
    assert.match(content, /bluetoothAppletMenuBridge\.item\?\.closeStyledMenu\(\)/)
    assert.match(content, /wifiAppletMenuBridge\.item\?\.closeStyledMenu\(\)/)
    assert.match(content, /wifiAppletMenuBridge\.parent\.visible/)
    assert.match(content, /bluetoothAppletMenuBridge\.parent\.visible/)
    assert.match(content, /wifiAppletMenuBridge/)
    assert.match(content, /bluetoothAppletMenuBridge/)
    assert.equal(
      patches.filter((patch) => patch.content.includes('id: wifiAppletMenuBridge')).length,
      1,
      `${target} must expose one Wi-Fi bridge`,
    )
    assert.equal(
      patches.filter((patch) => patch.content.includes('id: bluetoothAppletMenuBridge')).length,
      1,
      `${target} must expose one Bluetooth bridge`,
    )
  }
})
