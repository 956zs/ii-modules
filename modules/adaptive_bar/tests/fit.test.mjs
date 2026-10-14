import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const moduleRoot = new URL('../', import.meta.url)

async function loadFit() {
  const source = (await readFile(new URL('Fit.js', moduleRoot), 'utf8')).replace(/^\.pragma library\s*/m, '')
  const context = {}
  vm.createContext(context)
  vm.runInContext(source, context)
  return context
}

// Measured on the 1920 px 16:10 panel: workspaces group 266 px plus two 4 px
// Row gaps, both side groups at the stock 360 px, clock group content ~290 px.
function laptop(overrides = {}) {
  return {
    barWidth: 1920,
    coreWidth: 274,
    sideMax: 360,
    sideMin: 290,
    rightNeed: 581,
    foldable: 3,
    foldUnit: 35,
    foldOverhead: 0,
    ...overrides,
  }
}

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

test('wide screens keep the stock layout', async () => {
  const fit = await loadFit()
  assert.deepEqual(plain(fit.plan(laptop({ barWidth: 2560 }))), { fold: 0, side: 360, overflow: 0 })
  // Exactly enough room is still a fit.
  assert.deepEqual(plain(fit.plan(laptop({ rightNeed: 463 }))), { fold: 0, side: 360, overflow: 0 })
})

test('tray icons fold before the centre groups shrink', async () => {
  const fit = await loadFit()
  // 118 px missing: all three icons fold (105 px), the centre covers 13 px.
  assert.deepEqual(plain(fit.plan(laptop())), { fold: 3, side: 347, overflow: 0 })
  // 30 px missing: one icon covers it, the centre keeps its full width.
  assert.deepEqual(plain(fit.plan(laptop({ rightNeed: 493 }))), { fold: 1, side: 360, overflow: 0 })
  // 36 px missing needs a second icon rather than a 1 px shrink.
  assert.deepEqual(plain(fit.plan(laptop({ rightNeed: 499 }))), { fold: 2, side: 360, overflow: 0 })
})

test('without foldable icons the centre groups absorb the deficit', async () => {
  const fit = await loadFit()
  assert.deepEqual(plain(fit.plan(laptop({ foldable: 0 }))), { fold: 0, side: 290, overflow: 48 })
  assert.deepEqual(plain(fit.plan(laptop({ foldable: 0, rightNeed: 500 }))), { fold: 0, side: 323, overflow: 0 })
  // A disabled overflow menu reports zero fold width.
  assert.deepEqual(plain(fit.plan(laptop({ foldUnit: 0, rightNeed: 500 }))), { fold: 0, side: 323, overflow: 0 })
})

test('revealing the overflow button is charged to the first fold', async () => {
  const fit = await loadFit()
  // One icon would save 35 - 39 = -4 px, so it is never folded alone.
  assert.deepEqual(
    plain(fit.plan(laptop({ foldable: 1, foldOverhead: 39, rightNeed: 473 }))),
    { fold: 0, side: 350, overflow: 0 },
  )
  // Two icons save 31 px net, which covers a 10 px deficit.
  assert.deepEqual(
    plain(fit.plan(laptop({ foldOverhead: 39, rightNeed: 473 }))),
    { fold: 2, side: 360, overflow: 0 },
  )
})

test('whatever still does not fit is reported as overflow', async () => {
  const fit = await loadFit()
  assert.deepEqual(plain(fit.plan(laptop({ rightNeed: 700 }))), { fold: 3, side: 290, overflow: 62 })
})

test('invalid or not-yet-measured input leaves the stock layout', async () => {
  const fit = await loadFit()
  assert.deepEqual(plain(fit.plan(laptop({ barWidth: 0 }))), { fold: 0, side: 360, overflow: 0 })
  assert.deepEqual(plain(fit.plan(laptop({ barWidth: Number.NaN }))), { fold: 0, side: 360, overflow: 0 })
  assert.deepEqual(plain(fit.plan(laptop({ sideMax: 0 }))), { fold: 0, side: 0, overflow: 0 })
  assert.deepEqual(plain(fit.plan({})), { fold: 0, side: 0, overflow: 0 })
  // Non-numeric demand counts as no demand.
  assert.deepEqual(plain(fit.plan(laptop({ rightNeed: undefined }))), { fold: 0, side: 360, overflow: 0 })
})

test('a content minimum above the cap never widens the centre', async () => {
  const fit = await loadFit()
  assert.deepEqual(plain(fit.plan(laptop({ sideMin: 400, foldable: 0 }))), { fold: 0, side: 360, overflow: 118 })
  assert.deepEqual(plain(fit.plan(laptop({ sideMin: -5, foldable: 0, rightNeed: 900 }))), { fold: 0, side: 0, overflow: 77 })
})

test('folding is never more than the foldable count', async () => {
  const fit = await loadFit()
  const result = fit.plan(laptop({ foldable: 2.7, rightNeed: 900 }))
  assert.equal(result.fold, 2)
})

test('settle keeps a degradation until the slack exceeds the hysteresis', async () => {
  const fit = await loadFit()
  const previous = { fold: 1, side: 360 }
  // Demand dropped 3 px below the one-icon threshold: keep the icon folded.
  assert.deepEqual(plain(fit.settle(laptop({ rightNeed: 460 }), previous, 8)), { fold: 1, side: 360, overflow: 0 })
  // Demand dropped 10 px below it: restore the icon.
  assert.deepEqual(plain(fit.settle(laptop({ rightNeed: 453 }), previous, 8)), { fold: 0, side: 360, overflow: 0 })
  // More demand always degrades immediately.
  assert.deepEqual(plain(fit.settle(laptop({ rightNeed: 499 }), previous, 8)), { fold: 2, side: 360, overflow: 0 })
})

test('settle restores an over-degraded state only down to the padded need', async () => {
  const fit = await loadFit()
  // Previously everything folded and shrunk; now 20 px short. Strict needs
  // one icon, padded (28 px) still needs one: three folds drop to one.
  assert.deepEqual(
    plain(fit.settle(laptop({ rightNeed: 483 }), { fold: 3, side: 290 }, 8)),
    { fold: 1, side: 360, overflow: 0 },
  )
  // Shrink hysteresis: no icons, 10 px short; a previous 14 px shrink stays.
  assert.deepEqual(
    plain(fit.settle(laptop({ foldable: 0, rightNeed: 473 }), { fold: 0, side: 346 }, 8)),
    { fold: 0, side: 346, overflow: 0 },
  )
  // ...but a previous 40 px shrink relaxes to the padded 18 px.
  assert.deepEqual(
    plain(fit.settle(laptop({ foldable: 0, rightNeed: 473 }), { fold: 0, side: 320 }, 8)),
    { fold: 0, side: 342, overflow: 0 },
  )
})

test('settle drops a kept fold that would now cost width', async () => {
  const fit = await loadFit()
  // The last unpinned icon vanished: folding one icon now reveals the button.
  assert.deepEqual(
    plain(fit.settle(laptop({ foldable: 1, foldOverhead: 39, rightNeed: 465 }), { fold: 1, side: 360 }, 8)),
    { fold: 0, side: 358, overflow: 0 },
  )
  // A kept single fold between a strict 0 and a padded 2 would save -4 px.
  assert.deepEqual(
    plain(fit.settle(laptop({ foldOverhead: 39, rightNeed: 460 }), { fold: 1, side: 360 }, 8)),
    { fold: 0, side: 360, overflow: 0 },
  )
})

test('settle without history or hysteresis equals the plan', async () => {
  const fit = await loadFit()
  assert.deepEqual(plain(fit.settle(laptop(), null, 8)), plain(fit.plan(laptop())))
  assert.deepEqual(plain(fit.settle(laptop({ rightNeed: 460 }), { fold: 1, side: 360 }, 0)), { fold: 0, side: 360, overflow: 0 })
  assert.deepEqual(plain(fit.settle(laptop({ barWidth: 0 }), { fold: 3, side: 290 }, 8)), { fold: 0, side: 360, overflow: 0 })
})

test('unfolded demand adds back what applied folds saved', async () => {
  const fit = await loadFit()
  assert.equal(fit.unfoldedNeed(476, 3, 35, 0), 581)
  assert.equal(fit.unfoldedNeed(500, 2, 35, 39), 531)
  assert.equal(fit.unfoldedNeed(500, 0, 35, 39), 500)
  assert.equal(fit.unfoldedNeed(Number.NaN, 0, 35, 0), 0)
  assert.equal(fit.foldSavings(-1, 35, 0), 0)
})

test('group minimum squeezes elastic children and skips hidden ones', async () => {
  const fit = await loadFit()
  const resources = { visible: true, fill: false, width: 170 }
  const media = { visible: true, fill: true, width: 420 }
  assert.equal(fit.groupMinWidth([resources, media], 4, 5, 96), 170 + 96 + 4 + 10)
  assert.equal(fit.groupMinWidth([resources, { ...media, width: 40 }], 4, 5, 96), 170 + 40 + 4 + 10)
  assert.equal(fit.groupMinWidth([resources, { ...media, visible: false }], 4, 5, 96), 170 + 10)
  assert.equal(fit.groupMinWidth([], 4, 5, 96), 0)
  assert.equal(fit.groupMinWidth(null, 4, 5, 96), 0)
  assert.equal(fit.groupMinWidth([null, { visible: true, fill: false, width: Number.NaN }], 4, 5, 96), 10)
})

test('integer settings fall back on missing or malformed values', async () => {
  const fit = await loadFit()
  assert.equal(fit.clampInt(280, 190, 360, 360), 280)
  assert.equal(fit.clampInt(284.6, 190, 360, 360), 285)
  assert.equal(fit.clampInt(100, 190, 360, 360), 190)
  assert.equal(fit.clampInt(999, 190, 360, 360), 360)
  assert.equal(fit.clampInt(undefined, 190, 360, 360), 360)
  assert.equal(fit.clampInt(null, 190, 360, 360), 360)
  assert.equal(fit.clampInt('', 190, 360, 360), 360)
  assert.equal(fit.clampInt('wide', 190, 360, 360), 360)
})
