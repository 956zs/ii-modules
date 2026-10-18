import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = await readFile(new URL('../assets/ModulesConfig.qml', import.meta.url), 'utf8')

function loadPureLogic() {
  const match = source.match(/\/\/ PURE_LOGIC_START[^\n]*\n([\s\S]*?)\n\s*\/\/ PURE_LOGIC_END/)
  assert.ok(match, 'pure logic contract block must remain available')

  const context = vm.createContext({})
  vm.runInContext(
    `${match[1]}\nglobalThis.api = { isFlippable, needsAttention, filterModules, reconcileSelectedId, slotKind, matchesSlot, parsePageMap, pageOf, setPageEntry, parseOrderList, orderedBarIds, moveOrderEntry }`,
    context,
  )
  return context.api
}

function ids(modules) {
  return Array.from(modules, module => module.id)
}

test('filtering matches localized search text and each state', () => {
  const logic = loadPureLogic()
  const modules = [
    { id: 'network_traffic', state: 'enabled', search: 'Network Traffic 網路流量' },
    { id: 'screen_time', state: 'disabled', search: 'Screen Time 螢幕時間' },
    { id: 'patched', state: 'incompatible', search: 'Patched Tool' },
  ]
  const searchTextFor = module => `${module.search} ${module.id}`
  const noErrors = () => false

  assert.deepEqual(ids(logic.filterModules(modules, '網路', 'all', searchTextFor, noErrors)), ['network_traffic'])
  assert.deepEqual(ids(logic.filterModules(modules, 'SCREEN_TIME', 'all', searchTextFor, noErrors)), ['screen_time'])
  assert.deepEqual(ids(logic.filterModules(modules, '', 'enabled', searchTextFor, noErrors)), ['network_traffic'])
  assert.deepEqual(ids(logic.filterModules(modules, '', 'disabled', searchTextFor, noErrors)), ['screen_time'])
  assert.deepEqual(ids(logic.filterModules(modules, '', 'attention', searchTextFor, noErrors)), ['patched'])
  assert.deepEqual(ids(logic.filterModules(modules, '', 'attention', searchTextFor, id => id === 'screen_time')), ['screen_time', 'patched'])
})

test('filtering handles null, empty, malformed, and unknown filter input', () => {
  const logic = loadPureLogic()
  assert.deepEqual(ids(logic.filterModules(null, null, 'all', null, null)), [])
  assert.deepEqual(ids(logic.filterModules([], '', 'enabled', () => '', () => false)), [])
  assert.deepEqual(ids(logic.filterModules([null, 4, { id: 'valid', state: 'enabled' }], '', 'all', () => '', () => false)), ['valid'])
  assert.deepEqual(ids(logic.filterModules([{ id: 'valid', state: 'enabled' }], 42, 'future', () => '', () => false)), ['valid'])
})

test('selection preserves a visible id and falls back at result boundaries', () => {
  const logic = loadPureLogic()
  const modules = [{ id: 'first' }, { id: 'second' }]
  assert.equal(logic.reconcileSelectedId(modules, 'second'), 'second')
  assert.equal(logic.reconcileSelectedId(modules, 'removed'), 'first')
  assert.equal(logic.reconcileSelectedId([], 'removed'), '')
  assert.equal(logic.reconcileSelectedId(null, 'removed'), '')
  assert.equal(logic.reconcileSelectedId([null, {}, { id: 'valid' }], ''), 'valid')
})

test('slot filter keeps modules that declare the slot and ignores unknown values', () => {
  const logic = loadPureLogic()
  const bar = { id: 'bar_only', slots: ['bar'] }
  const window = { id: 'window_only', slots: ['window'] }
  const both = { id: 'both', slots: ['bar', 'window'] }

  assert.equal(logic.matchesSlot(bar, 'bar'), true)
  assert.equal(logic.matchesSlot(bar, 'window'), false)
  assert.equal(logic.matchesSlot(window, 'window'), true)
  assert.equal(logic.matchesSlot(window, 'bar'), false)
  assert.equal(logic.matchesSlot(both, 'bar'), true)
  assert.equal(logic.matchesSlot(both, 'window'), true)
  assert.equal(logic.matchesSlot(bar, 'all'), true)
  assert.equal(logic.matchesSlot(bar, undefined), true)
  assert.equal(logic.matchesSlot(null, 'all'), false)
  assert.equal(logic.matchesSlot('not a module', 'bar'), false)
})

test('state and slot helpers handle normal and malformed modules', () => {
  const logic = loadPureLogic()
  assert.equal(logic.isFlippable({ state: 'enabled' }), true)
  assert.equal(logic.isFlippable({ state: 'disabled' }), true)
  assert.equal(logic.isFlippable({ state: 'blocked' }), false)
  assert.equal(logic.isFlippable(null), false)
  assert.equal(logic.needsAttention({ state: 'enabled' }, true), true)
  assert.equal(logic.needsAttention({ state: 'incompatible' }, false), true)
  assert.equal(logic.needsAttention(null, true), false)
  assert.equal(logic.slotKind(['bar']), 'bar')
  assert.equal(logic.slotKind(['window']), 'window')
  assert.equal(logic.slotKind(['bar', 'window']), 'both')
  assert.equal(logic.slotKind(null), 'window')
})

test('module manager uses a scope rail, card grid, and responsive detail pane', () => {
  assert.match(source, /baseWidth:\s*Math\.max\(320, width - 40\)/)
  assert.match(source, /readonly property bool wideLayout:\s*baseWidth >= 760/)
  assert.match(source, /id:\s*workspace[\s\S]*id:\s*railColumn[\s\S]*id:\s*contentColumn[\s\S]*id:\s*detailPane/)
  assert.match(source, /id:\s*railColumn[\s\S]*?visible:\s*root\.wideLayout/)
  assert.match(source, /id:\s*contentColumn[\s\S]*?visible:\s*root\.wideLayout \|\| !root\.detailOpen/)
  assert.match(source, /id:\s*detailPane[\s\S]*?visible:\s*root\.detailOpen && root\.hasSelection/)
  assert.match(source, /Layout\.preferredWidth:\s*root\.wideLayout \? 340 : -1/)
  assert.match(source, /text:\s*root\.wideLayout \? "close" : "arrow_back"/)
  assert.match(source, /onClicked:\s*root\.closeDetail\(\)/)
  assert.doesNotMatch(source, /narrowDetailOpen|listPane/)
})

test('card grid derives columns from width and keeps the slot filter wired', () => {
  assert.match(source, /readonly property int columns:\s*Math\.max\(1, Math\.floor\(\(width \+ spacing\) \/ \(240 \+ spacing\)\)\)/)
  assert.match(source, /readonly property real cardWidth:\s*Math\.floor\(\(width - spacing \* \(columns - 1\)\) \/ columns\)/)
  assert.match(source, /\)\.filter\(module => matchesSlot\(module, slotFilter\)\)/)
  assert.match(source, /readonly property var slotOptions:/)
  assert.match(source, /root\.slotFilter = modelData\.value/)
  assert.match(source, /slotFilter = "all"/)
})

test('detail pane closes when the open module leaves the filtered result', () => {
  assert.match(source, /function reconcileSelection\(\)[\s\S]*?const stillVisible = root\.filteredMods\.some\(module => module\.id === root\.selectedId\)[\s\S]*?if \(!stillVisible\)\s*root\.detailOpen = false/)
  assert.match(source, /function selectModule\(id\)\s*{\s*root\.selectedId = id;\s*root\.detailOpen = true;/)
})

test('QML searches localized name, id, and description without an undeployed asset', () => {
  assert.doesNotMatch(source, /ModulesConfigLogic\.js/)
  assert.match(source, /function filterModules\(modules, query, filter, searchTextFor, hasOperationError\)/)
  assert.match(source, /readonly property var filteredMods:\s*filterModules\(/)
  assert.match(source, /localized\(module\.name, module\.id\)/)
  assert.match(source, /module\.id \?\? ""/)
  assert.match(source, /localized\(module\.description, ""\)/)
  assert.match(source, /id => operationFor\(id\)\.error\.length > 0/)
  assert.match(source, /reconcileSelectedId\(root\.filteredMods, root\.selectedId\)/)
  assert.match(source, /placeholderText:\s*Translation\.tr\("Search modules…"\)/)
})

test('search field is a vertically centered single-line control', () => {
  assert.match(source, /placeholderText:\s*Translation\.tr\("Search modules…"\)[\s\S]*?wrapMode:\s*TextEdit\.NoWrap[\s\S]*?verticalAlignment:\s*TextInput\.AlignVCenter/)
})

test('selected filter chip uses the end-4 primary foreground color', () => {
  assert.match(source, /root\.statusFilter === modelData\.value\s*\? Appearance\.colors\.colOnPrimary\s*:\s*Appearance\.colors\.colOnLayer1/)
  assert.doesNotMatch(source, /buttonText:\s*modelData\.label \+ "  " \+ modelData\.count/)
})

test('selection does not expand settings inside list rows', () => {
  assert.match(source, /onFilteredModsChanged:\s*Qt\.callLater\(reconcileSelection\)/)
  assert.match(source, /onClicked:\s*root\.selectModule\(card\.modelData\.id\)/)
  assert.doesNotMatch(source, /showSettings|settingsEverOpened|settingsRevealer|Revealer\s*{/)

  const delegateStart = source.indexOf('id: card\n')
  const detailStart = source.indexOf('id: detailPane')
  assert.ok(delegateStart >= 0 && detailStart > delegateStart)
  assert.doesNotMatch(source.slice(delegateStart, detailStart), /Loader\s*{/)
})

test('enable transitions retain iimod authority, fallback, reload, and safe errors', () => {
  assert.match(source, /command -v iimod \|\| echo "\$HOME\/\.local\/bin\/iimod"/)
  assert.match(source, /exec "\$bin" "\$1" "\$2"/)
  assert.match(source, /indexFile\.reload\(\)/)
  assert.match(source, /checked:\s*card\.moduleOn/)
  assert.match(source, /checked:\s*root\.selectedModule\?\.state === "enabled"/)
  assert.match(source, /Module operation failed\./)
  assert.doesNotMatch(source, /text:\s*flipProc\.lastError|text:\s*flipStderr\.text/)
})

test('detail keeps lazy module settings, placement, statuses, and empty recovery', () => {
  assert.match(source, /id:\s*moduleSettingsLoader/)
  assert.match(source, /active:\s*root\.hasSelection && !!root\.selectedModule\.settings/)
  assert.match(source, /Quickshell\.shellPath\(`mod\/\$\{root\.selectedModule\.id\}/)
  assert.match(source, /barPlacementsJson/)
  assert.match(source, /No configurable options/)
  assert.match(source, /No modules installed/)
  assert.match(source, /No matching modules/)
  assert.match(source, /Clear search and filters/)
  assert.match(source, /The module index could not be read\./)
  assert.match(source, /This module modifies stock shell files/)
})

test('bar page map stores non-main pages only and survives junk', () => {
  const logic = loadPureLogic()
  assert.equal(logic.setPageEntry('{}', 'network_traffic', 1), '{"network_traffic":1}')
  assert.equal(logic.setPageEntry('{"network_traffic":1}', 'screentime', 2), '{"network_traffic":1,"screentime":2}')
  assert.equal(logic.setPageEntry('{"network_traffic":1}', 'network_traffic', 0), '{}')
  assert.equal(logic.setPageEntry('{"network_traffic":1}', 'network_traffic', -3), '{}')
  assert.equal(logic.setPageEntry('{"network_traffic":1}', 'network_traffic', 1.5), '{}')
  assert.equal(logic.setPageEntry('not json', 'a', 2), '{"a":2}')
  assert.equal(logic.setPageEntry('[1,2]', 'a', 2), '{"a":2}')
  assert.equal(logic.setPageEntry(undefined, '', 2), '{}')
  assert.equal(logic.pageOf('{"a":3}', 'a'), 3)
  assert.equal(logic.pageOf('{"a":"3"}', 'a'), 3)
  assert.equal(logic.pageOf('{"a":-1}', 'a'), 0)
  assert.equal(logic.pageOf('{', 'a'), 0)
  assert.equal(logic.pageOf('{"a":3}', 'missing'), 0)
  assert.match(source, /Config\.options\.iimp\.barPagesJson = setPageEntry/)
  assert.match(source, /Horizontal bar page/)
})

test('bar order lists enabled ids first, moves within enabled ids, and survives junk', () => {
  const logic = loadPureLogic()
  const enabled = ['a', 'b', 'c', 'd']
  assert.deepEqual(Array.from(logic.orderedBarIds('[]', enabled)), ['a', 'b', 'c', 'd'])
  assert.deepEqual(Array.from(logic.orderedBarIds('["d","gone","b"]', enabled)), ['d', 'b', 'a', 'c'])
  assert.deepEqual(Array.from(logic.orderedBarIds('{"a":1}', enabled)), ['a', 'b', 'c', 'd'])
  assert.deepEqual(Array.from(logic.orderedBarIds('[1,"b",null,"b"]', ['b', 'a', 'a'])), ['b', 'a'])
  assert.deepEqual(Array.from(logic.orderedBarIds(undefined, null)), [])
  assert.deepEqual(Array.from(logic.parseOrderList('not json')), [])

  assert.equal(logic.moveOrderEntry('[]', enabled, 'c', 1), '["c","a","b","d"]')
  assert.equal(logic.moveOrderEntry('["d"]', enabled, 'b', 2), '["d","b","a","c"]')
  assert.equal(logic.moveOrderEntry('[]', enabled, 'a', 99), '["b","c","d","a"]')
  assert.equal(logic.moveOrderEntry('[]', enabled, 'd', 0), '["d","a","b","c"]')
  assert.equal(logic.moveOrderEntry('["gone","c","a"]', ['a', 'c'], 'a', 1), '["a","c","gone"]')
  assert.equal(logic.moveOrderEntry('["gone"]', enabled, 'missing', 1), '["gone"]')
  assert.equal(logic.moveOrderEntry('[]', enabled, 'a', 'x'), '[]')
  assert.match(source, /Config\.options\.iimp\.barOrderJson = moveOrderEntry\(/)
  assert.match(source, /onClicked:\s*root\.moveBar\(root\.selectedId, -1\)/)
  assert.match(source, /onClicked:\s*root\.moveBar\(root\.selectedId, 1\)/)
  assert.match(source, /Bar order: %1 of %2/)
})
