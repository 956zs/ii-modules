import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const moduleRoot = new URL('../', import.meta.url)

async function read(name) {
  return readFile(new URL(name, moduleRoot), 'utf8')
}

async function loadFormat() {
  const source = (await read('ClockFormat.js')).replace(/^\.pragma library\s*/m, '')
  const context = {}
  vm.createContext(context)
  vm.runInContext(source, context)
  return context
}

test('format validation preserves normal Qt patterns and rejects invalid input', async () => {
  const format = await loadFormat()

  assert.equal(format.safeFormat('  HH:mm:ss  ', 'HH:mm'), 'HH:mm:ss')
  assert.equal(format.safeFormat('', 'HH:mm'), 'HH:mm')
  assert.equal(format.safeFormat(null, 'HH:mm'), 'HH:mm')
  assert.equal(format.safeFormat('x'.repeat(65), 'HH:mm'), 'HH:mm')
  assert.equal(format.safeFormat(`HH:mm${String.fromCharCode(10)}`, 'HH:mm'), 'HH:mm')
})

test('separator validation allows empty separators but bounds unsafe values', async () => {
  const format = await loadFormat()

  assert.equal(format.safeSeparator(' • ', '•'), ' • ')
  assert.equal(format.safeSeparator('', '•'), '')
  assert.equal(format.safeSeparator('123456789', '•'), '•')
  assert.equal(format.safeSeparator(42, '•'), '•')
  assert.equal(format.safeSeparator(String.fromCharCode(127), '•'), '•')
})

test('integer options round, clamp, and recover from non-numeric values', async () => {
  const format = await loadFormat()

  assert.equal(format.clampInteger(4.6, 0, 24, 4), 5)
  assert.equal(format.clampInteger(-100, 0, 24, 4), 0)
  assert.equal(format.clampInteger(100, 0, 24, 4), 24)
  assert.equal(format.clampInteger('', 0, 24, 4), 0)
  assert.equal(format.clampInteger('bad', 0, 24, 4), 4)
  assert.equal(format.clampInteger(Number.NaN, 0, 24, 4), 4)
})

test('second precision detects only unquoted Qt second tokens', async () => {
  const format = await loadFormat()

  assert.equal(format.needsSecondPrecision('HH:mm:ss'), true)
  assert.equal(format.needsSecondPrecision('HH:mm'), false)
  assert.equal(format.needsSecondPrecision("HH:mm 'seconds'"), false)
  assert.equal(format.needsSecondPrecision("HH:mm 'it''s'"), false)
  assert.equal(format.needsSecondPrecision(null), false)
})

test('manifest upgrades the existing id into a configurable Tier B clock', async () => {
  const manifest = JSON.parse(await read('module.json'))

  assert.equal(manifest.id, 'clock_popup_slim')
  assert.equal(manifest.version, '2.1.0')
  assert.equal(manifest.name.en_US, 'Bar Clock Customizer (Experimental)')
  assert.match(manifest.name.zh_TW, /實驗性/)
  assert.match(manifest.name.zh_CN, /实验性/)
  assert.match(manifest.description.en_US, /may be deprecated/)
  assert.match(manifest.description.zh_TW, /可能棄用/)
  assert.match(manifest.description.zh_CN, /可能弃用/)
  assert.deepEqual(manifest.entries, { window: 'main.qml', settings: 'settings.qml' })
  assert.deepEqual(manifest.capabilities, [])

  const targets = new Set(manifest.patches.map((patch) => patch.file))
  assert.deepEqual([...targets].sort(), [
    'modules/ii/bar/BarContent.qml',
    'modules/ii/bar/ClockWidgetPopup.qml',
  ])
  assert.equal(
    manifest.patches.some((patch) => patch.file.includes('verticalBar')),
    false,
  )

  const barPatch = manifest.patches
    .filter((patch) => patch.file.endsWith('/BarContent.qml'))
    .map((patch) => patch.content)
    .join('\n')
  assert.match(barPatch, /ClockCustomizer\.ClockBar/)
  assert.match(barPatch, /visible: false/)
  assert.match(barPatch, /ClockWidgetPopup/)
  assert.doesNotMatch(barPatch, /Layout\.fillWidth: true/)
  assert.equal((barPatch.match(/property var clockCustomizerWidthBinding:/g) ?? []).length, 2)
  assert.equal((barPatch.match(/value: Math\.min\(root\.centerSideModuleWidth, customBarClock\.centerSideWidth\)/g) ?? []).length, 2)
  assert.match(barPatch, /target: leftCenterGroup/)
  assert.match(barPatch, /target: rightCenterGroup/)

  const popupPatch = manifest.patches
    .filter((patch) => patch.file.endsWith('/ClockWidgetPopup.qml'))
    .map((patch) => patch.content)
    .join('\n')
  assert.match(popupPatch, /property var clockCustomizerConfig:/)
  assert.match(popupPatch, /visible: !clockCustomizerConfig\.options\.slimPopup/g)
})

test('runtime and settings use one module-owned configuration contract', async () => {
  const [main, config, bar, settings] = await Promise.all([
    read('main.qml'),
    read('ConfigLoader.qml'),
    read('ClockBar.qml'),
    read('settings.qml'),
  ])

  assert.match(main, /ConfigLoader\s*{[\s\S]*owner: true/)
  assert.match(config, /modules\/clock_popup_slim\.json/)
  assert.match(config, /atomicWrites: true/)
  assert.match(config, /property bool showDate: false/)
  assert.match(config, /property string timeFormat: "HH:mm"/)
  assert.match(config, /property int horizontalPadding: 0/)
  assert.match(config, /property int centerSideWidth: 280/)
  assert.match(config, /centerSideWidth < 280 \|\| adapterItem\.centerSideWidth > 360/)
  assert.match(config, /property bool slimPopup: true/)
  assert.doesNotMatch(config, /property var\s+/)

  assert.match(bar, /implicitWidth: content\.implicitWidth \+ root\.horizontalPadding \* 2/)
  assert.match(bar, /precision: ClockFormat\.needsSecondPrecision/)
  assert.match(bar, /Qt\.locale\(\)\.toString\(clock\.date, root\.timeFormat\)/)
  assert.match(settings, /ConfigSwitch\s*{[\s\S]*Show date on the bar/)
  assert.match(settings, /Horizontal padding \(px\)/)
  assert.match(settings, /Center side width \(px\)/)
  assert.match(settings, /from: 280[\s\S]*to: 360/)
  assert.match(settings, /Slim hover popup/)
})

test('every settings translation key ships in both Chinese locales', async () => {
  const [settings, zhTwSource, zhCnSource] = await Promise.all([
    read('settings.qml'),
    read('translations/zh_TW.json'),
    read('translations/zh_CN.json'),
  ])
  const keys = [...settings.matchAll(/Translation\.tr\("([^"]+)"\)/g)].map((match) => match[1])
  const zhTw = JSON.parse(zhTwSource)
  const zhCn = JSON.parse(zhCnSource)

  assert.ok(keys.length > 0)
  for (const key of keys) {
    assert.equal(typeof zhTw[key], 'string', `zh_TW missing ${key}`)
    assert.equal(typeof zhCn[key], 'string', `zh_CN missing ${key}`)
  }
})
