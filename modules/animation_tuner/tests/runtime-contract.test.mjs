import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const moduleRoot = new URL('../', import.meta.url)

async function sources() {
  const names = [
    'module.json',
    'main.qml',
    'ConfigLoader.qml',
    'AnimationController.qml',
  ]
  const loaded = await Promise.all(names.map(name => readFile(new URL(name, moduleRoot), 'utf8')))
  return Object.fromEntries(names.map((name, index) => [name, loaded[index]]))
}

test('module is a zero-capability Tier A single window controller', async () => {
  const source = await sources()
  const manifest = JSON.parse(source['module.json'])

  assert.deepEqual(manifest.slots, ['window'])
  assert.deepEqual(manifest.entries, { window: 'main.qml', settings: 'settings.qml' })
  assert.deepEqual(manifest.capabilities, [])
  assert.deepEqual(manifest.patches, [])
  assert.match(source['main.qml'], /^import Quickshell$/m)
  assert.match(source['main.qml'], /Scope\s*{/)
  assert.match(source['main.qml'], /ConfigLoader\s*{[\s\S]*writable:\s*false/)
  assert.match(source['main.qml'], /AnimationController\s*{[\s\S]*config:/)
})

test('manifest probes every writable animation token used by the catalog', async () => {
  const manifest = JSON.parse((await sources())['module.json'])
  const patterns = manifest.compat.probes.map(probe => probe.pattern)

  for (const id of [
    'elementMove', 'elementMoveSmall', 'elementMoveEnter', 'elementMoveExit',
    'elementMoveFast', 'elementResize', 'clickBounce', 'scroll',
  ]) {
    assert.ok(patterns.includes(`property QtObject ${id}:`), id)
  }
})

test('configuration uses one adapter string with explicit read-only and writer roles', async () => {
  const source = await sources()
  const config = source['ConfigLoader.qml']

  assert.match(config, /property bool writable:\s*false/)
  assert.match(config, /property string documentJson:/)
  assert.match(config, /property string committedJson:/)
  assert.match(config, /property string draftJson:/)
  assert.match(config, /property alias storedDocumentJson:/)
  assert.match(config, /onAdapterUpdated:[\s\S]*if \(root\.writable\)/)
  assert.match(config, /onLoadFailed:[\s\S]*FileViewError\.FileNotFound/)
  assert.doesNotMatch(config, /property var\s+/)
})

test('controller restores stock values before rejecting invalid configuration', async () => {
  const controller = (await sources())['AnimationController.qml']
  const parseIndex = controller.indexOf('const parsed = MotionMath.parseDocument(serialized)')
  const restoreIndex = controller.indexOf('root.restoreOriginals()', parseIndex)
  const invalidIndex = controller.indexOf('if (!parsed.ok)', parseIndex)

  assert.ok(parseIndex >= 0)
  assert.ok(restoreIndex > parseIndex && restoreIndex < invalidIndex)
  assert.match(controller, /if \(!parsed\.ok\)[\s\S]*root\.currentDocument = MotionMath\.defaultDocument\(\)[\s\S]*return false/)
  assert.match(controller, /Component\.onDestruction:\s*root\.restoreOriginals\(\)/)
})

test('controller mutates only central token values and never replaces animation factories', async () => {
  const controller = (await sources())['AnimationController.qml']

  assert.match(controller, /token\.duration = effective\.durationMs/)
  assert.match(controller, /token\.bezierCurve = Array\.from/)
  assert.match(controller, /token\.velocity = effective\.velocity/)
  assert.doesNotMatch(controller, /numberAnimation\s*=/)
  assert.doesNotMatch(controller, /colorAnimation\s*=/)
  assert.doesNotMatch(controller, /Delayed(?:Number|Color)Animation/)
})
