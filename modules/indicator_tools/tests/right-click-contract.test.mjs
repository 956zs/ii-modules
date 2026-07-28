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
  assert.match(bridge, /root\.loadedMenu\?\.close\(\)/)
})

test('popups use the shell-wide click-outside dismiss lifecycle', async () => {
  const { bridge, bluetoothMenu, wifiMenu } = await loadContract()

  assert.doesNotMatch(bridge, /HyprlandFocusGrab/)
  for (const [name, source] of [
    ['Bluetooth', bluetoothMenu],
    ['Wi-Fi', wifiMenu],
  ]) {
    assert.match(source, /GlobalFocusGrab\.addDismissable\(root\)/, `${name} registers when visible`)
    assert.match(source, /GlobalFocusGrab\.removeDismissable\(root\)/, `${name} unregisters when hidden`)
    assert.match(source, /target:\s*GlobalFocusGrab/, `${name} observes global dismiss`)
    assert.match(source, /function onDismissed\(\)\s*{\s*root\.close\(\)/, `${name} closes on outside click`)
  }
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
