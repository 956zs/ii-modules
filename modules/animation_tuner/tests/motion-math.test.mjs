import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

async function loadMath() {
  const source = await readFile(new URL('../MotionMath.js', import.meta.url), 'utf8')
  const context = vm.createContext({})
  vm.runInContext(
    `${source}\nglobalThis.api = { tokenCatalog, defaultDocument, parseDocument, validateDocument, effectiveToken, sampleBezier, migrateDocument }`,
    context,
  )
  return context.api
}

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

test('catalog freezes the eight writable stock animation tokens and their contracts', async () => {
  const math = await loadMath()
  const catalog = plain(math.tokenCatalog())

  assert.deepEqual(catalog.map(token => token.id), [
    'elementMove',
    'elementMoveSmall',
    'elementMoveEnter',
    'elementMoveExit',
    'elementMoveFast',
    'elementResize',
    'clickBounce',
    'scroll',
  ])
  assert.deepEqual(catalog.map(token => token.factory), [
    'number', 'number', 'number', 'number', 'number-color', 'number', 'number', 'none',
  ])
  assert.deepEqual(catalog.map(token => token.delayCoverage), [
    'preview', 'preview', 'preview', 'preview', 'preview', 'preview', 'preview', 'preview',
  ])
})

test('default document is an empty versioned override set', async () => {
  const math = await loadMath()

  assert.deepEqual(plain(math.defaultDocument()), {
    schemaVersion: 1,
    reducedMotion: false,
    overrides: {},
    springLab: {
      mass: 1,
      spring: 2.5,
      damping: 0.3,
      epsilon: 0.01,
      velocity: 0,
      modulus: 0,
      delayMs: 0,
    },
    customPresets: [],
  })
})

test('malformed, null, empty, and future documents fail closed', async () => {
  const math = await loadMath()

  for (const source of ['', '{bad', 'null', '[]', '{"schemaVersion":2}']) {
    const parsed = plain(math.parseDocument(source))
    assert.equal(parsed.ok, false, source)
    assert.deepEqual(parsed.document, plain(math.defaultDocument()))
    assert.ok(parsed.errors.length > 0)
  }
})

test('valid overrides preserve unknown future token records but apply only known tokens', async () => {
  const math = await loadMath()
  const source = JSON.stringify({
    schemaVersion: 1,
    reducedMotion: false,
    overrides: {
      elementMove: {
        enabled: true,
        easingKind: 'bezier',
        durationMs: 480,
        delayMs: 20,
        velocity: 700,
        bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1],
      },
      futureToken: { enabled: true, durationMs: 123 },
    },
    springLab: { mass: 1, spring: 3, damping: 0.25, epsilon: 0.01, velocity: 0, modulus: 0, delayMs: 0 },
    customPresets: [],
  })

  const parsed = plain(math.parseDocument(source))
  assert.equal(parsed.ok, true)
  assert.equal(parsed.document.overrides.futureToken.durationMs, 123)
  assert.deepEqual(parsed.applicableTokens, ['elementMove'])
})

test('single and multi-segment Bezier curves validate and sample known points', async () => {
  const math = await loadMath()
  const linear = [1 / 3, 1 / 3, 2 / 3, 2 / 3, 1, 1]
  const twoSegment = [0.1, 0, 0.2, 0.2, 0.5, 0.5, 0.7, 0.8, 0.9, 1, 1, 1]

  assert.deepEqual(plain(math.validateDocument({
    ...plain(math.defaultDocument()),
    overrides: {
      elementMove: { enabled: true, easingKind: 'bezier', durationMs: 500, delayMs: 0, velocity: 650, bezierCurve: linear },
      elementResize: { enabled: true, easingKind: 'bezier', durationMs: 300, delayMs: 0, velocity: 650, bezierCurve: twoSegment },
    },
  })).errors, [])
  assert.deepEqual(plain(math.sampleBezier(linear, 2)), [
    { x: 0, y: 0 },
    { x: 0.5, y: 0.5 },
    { x: 1, y: 1 },
  ])
  assert.deepEqual(plain(math.sampleBezier(twoSegment, 4)).map(point => point.x), [0, 0.25, 0.5, 0.75, 1])
})

test('Bezier validation rejects malformed, nonfinite, unordered, and incomplete curves', async () => {
  const math = await loadMath()
  const badCurves = [
    [],
    [0.2, 0, 0.8, 1, 0.9, 1],
    [1.2, 0, 0.8, 1, 1, 1],
    [0.2, 0, Number.NaN, 1, 1, 1],
    [0.2, -3, 0.8, 1, 1, 1],
    [0.2, 0, 0.8, 4, 1, 1],
    [0.1, 0, 0.4, 0.5, 0.5, 0.5, 0.4, 0.5, 0.8, 1, 1, 1],
  ]

  for (const bezierCurve of badCurves) {
    const result = plain(math.validateDocument({
      ...plain(math.defaultDocument()),
      overrides: {
        elementMove: { enabled: true, easingKind: 'bezier', durationMs: 500, delayMs: 0, velocity: 650, bezierCurve },
      },
    }))
    assert.ok(result.errors.length > 0, JSON.stringify(bezierCurve))
  }
})

test('numeric boundaries accept supported values and reject unsafe values', async () => {
  const math = await loadMath()
  const base = plain(math.defaultDocument())
  const good = {
    ...base,
    overrides: {
      elementMove: {
        enabled: true,
        easingKind: 'bezier',
        durationMs: 0,
        delayMs: 5000,
        velocity: 10000,
        bezierCurve: [0, -2, 1, 3, 1, 1],
      },
    },
    springLab: { mass: 0.01, spring: 5, damping: 1, epsilon: 0.0001, velocity: 10000, modulus: 360, delayMs: 5000 },
  }
  assert.deepEqual(plain(math.validateDocument(good)).errors, [])

  const invalidValues = [-1, Number.NaN, Number.POSITIVE_INFINITY, '200']
  for (const durationMs of invalidValues) {
    const result = plain(math.validateDocument({
      ...base,
      overrides: {
        elementMove: { enabled: true, easingKind: 'bezier', durationMs, delayMs: 0, velocity: 650, bezierCurve: [0.2, 0, 0, 1, 1, 1] },
      },
    }))
    assert.ok(result.errors.length > 0)
  }
})

test('reduced motion produces zero effective duration and delay without mutating saved values', async () => {
  const math = await loadMath()
  const override = {
    enabled: true,
    easingKind: 'bezier',
    durationMs: 480,
    delayMs: 30,
    velocity: 700,
    bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1],
  }
  const document = {
    ...plain(math.defaultDocument()),
    reducedMotion: true,
    overrides: { elementMove: override },
  }

  assert.deepEqual(plain(math.effectiveToken(document, 'elementMove')), {
    ...override,
    durationMs: 0,
    delayMs: 0,
  })
  const unconfigured = plain(math.effectiveToken(document, 'elementMoveFast'))
  assert.equal(unconfigured.enabled, true)
  assert.equal(unconfigured.durationMs, 0)
  assert.equal(unconfigured.delayMs, 0)
  assert.deepEqual(unconfigured.bezierCurve, [0.34, 0.8, 0.34, 1, 1, 1])
  assert.equal(document.overrides.elementMove.durationMs, 480)
  assert.equal(document.overrides.elementMove.delayMs, 30)
})

test('custom presets are validated as named finite Bezier curves', async () => {
  const math = await loadMath()
  const valid = {
    ...plain(math.defaultDocument()),
    customPresets: [{ name: 'My curve', bezierCurve: [0.2, 0, 0.8, 1, 1, 1] }],
  }
  assert.deepEqual(plain(math.validateDocument(valid)).errors, [])

  for (const preset of [
    { name: '', bezierCurve: [0.2, 0, 0.8, 1, 1, 1] },
    { name: 'x'.repeat(41), bezierCurve: [0.2, 0, 0.8, 1, 1, 1] },
    { name: 'Broken', bezierCurve: [0.2, 0, 0.8, 1, 0.9, 1] },
    { name: 'NaN', bezierCurve: [0.2, 0, Number.NaN, 1, 1, 1] },
  ]) {
    const result = plain(math.validateDocument({
      ...plain(math.defaultDocument()),
      customPresets: [preset],
    }))
    assert.ok(result.errors.length > 0)
  }
})

test('legacy version zero migrates once and unknown future fields survive', async () => {
  const math = await loadMath()
  const legacy = {
    schemaVersion: 0,
    reduceMotion: true,
    tokens: { elementMoveFast: { enabled: true, durationMs: 160 } },
    futureField: { keep: true },
  }

  const migrated = plain(math.migrateDocument(legacy))
  assert.equal(migrated.schemaVersion, 1)
  assert.equal(migrated.reducedMotion, true)
  assert.equal(migrated.overrides.elementMoveFast.durationMs, 160)
  assert.equal(migrated.overrides.elementMoveFast.enabled, true)
  assert.equal(migrated.overrides.elementMoveFast.delayMs, 0)
  assert.deepEqual(migrated.overrides.elementMoveFast.bezierCurve, [0.34, 0.8, 0.34, 1, 1, 1])
  assert.deepEqual(migrated.futureField, { keep: true })
  assert.equal(plain(math.parseDocument(JSON.stringify(legacy))).ok, true)
})
