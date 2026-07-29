import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const moduleRoot = new URL('../', import.meta.url)

async function read(name) {
  return readFile(new URL(name, moduleRoot), 'utf8')
}

test('settings owns a validated draft with apply, revert, token reset, and reset all', async () => {
  const source = await read('settings.qml')

  assert.match(source, /ConfigLoader\s*{[\s\S]*writable:\s*true/)
  assert.match(source, /property var draftDocument:/)
  assert.match(source, /function applyDraft\(\)/)
  assert.match(source, /MotionMath\.validateDocument\(root\.draftDocument\)/)
  assert.match(source, /const serialized = JSON\.stringify\(root\.draftDocument\)/)
  assert.match(source, /cfg\.commit\(serialized\)/)
  assert.match(source, /root\.loadedCommittedJson = serialized/)
  assert.match(source, /function revertDraft\(\)/)
  assert.match(source, /function resetSelectedToken\(\)/)
  assert.match(source, /function resetAll\(\)[\s\S]*next\.overrides = \{\}/)
  assert.doesNotMatch(source, /function resetAll\(\)[\s\S]{0,240}MotionMath\.defaultDocument\(\)/)
  assert.match(source, /property string loadError:/)
  assert.match(source, /No unapplied changes/)
})

test('settings exposes search, all eight tokens, honest delay coverage, and reduced-motion disclosure', async () => {
  const source = await read('settings.qml')

  assert.match(source, /placeholderText:\s*Translation\.tr\("Search animation tokens"\)/)
  assert.match(source, /MotionMath\.tokenCatalog\(\)/)
  assert.match(source, /Preview-only delay/)
  assert.match(source, /fixed-distance preview does not represent it/)
  assert.match(source, /No matching animation tokens/)
  assert.match(source, /does not change inline spring animations or direct readonly curve references/)
  assert.match(source, /Reduced motion/)
})

test('selected token tabs and primary actions use paired dynamic foreground tokens', async () => {
  const source = await read('settings.qml')

  assert.match(
    source,
    /delegate:\s*RippleButton\s*{[\s\S]*?toggled:\s*root\.selectedTokenId === modelData\.id[\s\S]*?contentItem:\s*StyledText\s*{[\s\S]*?color:\s*tokenButton\.toggled\s*\?\s*Appearance\.colors\.colOnPrimary\s*:\s*Appearance\.colors\.colOnLayer1/,
  )
  assert.match(
    source,
    /buttonText:\s*Translation\.tr\("Apply"\)[\s\S]*?colBackground:\s*Appearance\.colors\.colPrimary[\s\S]*?contentItem:\s*StyledText\s*{[\s\S]*?color:\s*Appearance\.colors\.colOnPrimary/,
  )
  assert.doesNotMatch(source, /(?:color|colBackground|colBackgroundHover):\s*(?:"#[0-9a-fA-F]{3,8}"|"black"|"white")/)
})

test('Bezier editor supports multi-segment graph, pointer drag, keyboard adjustment, and numeric alternatives', async () => {
  const source = await read('BezierEditor.qml')

  assert.match(source, /Canvas\s*{/)
  assert.match(source, /MotionMath\.sampleBezier/)
  assert.match(source, /onAvailableChanged:[\s\S]*requestPaint\(\)/)
  assert.match(source, /DragHandler\s*{/)
  assert.match(source, /Keys\.onPressed/)
  assert.match(source, /Accessible\.name/)
  assert.match(source, /MaterialTextField\s*{/)
  assert.match(source, /Add segment/)
  assert.match(source, /Remove segment/)
})

test('preview uses actual Qt animations and offers synchronized compare and restart', async () => {
  const source = await read('MotionPreview.qml')

  assert.match(source, /NumberAnimation\s*{/)
  assert.match(source, /SpringAnimation\s*{/)
  assert.doesNotMatch(source, /property var baseline:/)
  assert.match(source, /property var baselineMotion:/)
  assert.match(source, /function restart\(\)/)
  assert.match(source, /springDelay\.stop\(\)/)
  assert.match(source, /root\.resettingSpring = true[\s\S]*root\.springAtEnd = false[\s\S]*root\.resettingSpring = false/)
  assert.match(source, /Behavior on x\s*{[\s\S]*enabled:\s*!root\.resettingSpring/)
  assert.match(source, /onDraftPreviewSignatureChanged:[\s\S]*previewRestart\.restart\(\)/)
  assert.doesNotMatch(source, /onDraftChanged:/)
  assert.match(source, /Timer\s*{[\s\S]*id:\s*previewRestart/)
  assert.match(source, /Compare baseline/)
  assert.match(source, /Spring Lab/)
  assert.match(source, /preview only/)
  assert.doesNotMatch(source, /Qt\.createQmlObject/)
})

test('dense toolbars wrap instead of forcing the settings card wider', async () => {
  const [settings, editor, preview] = await Promise.all([
    read('settings.qml'),
    read('BezierEditor.qml'),
    read('MotionPreview.qml'),
  ])

  assert.match(settings, /columns:\s*width >= 520 \? 2 : 1/)
  assert.match(settings, /Flow\s*{[\s\S]*Confirm reset all token overrides[\s\S]*Apply/)
  assert.match(editor, /Flow\s*{[\s\S]*Stock baseline/)
  assert.match(editor, /Flow\s*{[\s\S]*Add segment[\s\S]*Remove segment/)
  assert.match(preview, /Flow\s*{[\s\S]*Compare baseline[\s\S]*Replay/)
})

test('presets include only verified stock curves and custom preset operations', async () => {
  const source = await read('settings.qml')

  for (const name of [
    'Expressive fast', 'Expressive default', 'Expressive slow', 'Expressive effects',
    'Emphasized', 'Emphasized accelerate', 'Emphasized decelerate',
    'Standard', 'Standard accelerate', 'Standard decelerate',
  ]) {
    assert.match(source, new RegExp(name))
  }
  assert.match(source, /function saveCustomPreset\(\)/)
  assert.match(source, /function deleteCustomPreset\(index\)/)
})
