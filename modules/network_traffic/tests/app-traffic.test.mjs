import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

async function loadLogic() {
  const source = await readFile(new URL('../AppTrafficLogic.js', import.meta.url), 'utf8')
  const context = vm.createContext({})
  vm.runInContext(
    `${source}\nglobalThis.api = { restoreAccounting, ranking, pruneAccounting, drainResolvedPending, finalizePending, nethogsCommand, parseNethogsLine, commitNethogsBatch, migrateStatsPeriod }`,
    context,
  )
  return context.api
}

async function loadConfigLogic() {
  const source = await readFile(new URL('../ConfigLogic.js', import.meta.url), 'utf8')
  const context = vm.createContext({})
  vm.runInContext(`${source}\nglobalThis.api = { prepareConfig, mergeConfigChanges, decodeSettingIntent }`, context)
  return context.api
}

const configDefaults = {
  updateInterval: 2000,
  excludeRegex: '^lo$',
  displayMode: 'auto',
  autoStackMaxWidth: 1920,
  stackedShowIcons: true,
  statsPeriod: 'today',
  statsPeriodSchema: 1,
  appMonitoring: true,
  pingHost: 'auto',
  breatheThresholdKB: 1024,
  acctState: '',
  appAcctState: '',
}

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

function sum(rows) {
  return rows.reduce((total, row) => ({ rx: total.rx + row.rx, tx: total.tx + row.tx }), { rx: 0, tx: 0 })
}

test('persisted day, month, and boot totals expire at their boundaries', async () => {
  const logic = await loadLogic()
  const stored = JSON.stringify({
    v: 1,
    bootId: 'current-boot',
    apps: [{
      n: 'browser', dk: '2026-07-27', drx: 1000, dtx: 200,
      mk: '2026-06', mrx: 5000, mtx: 700, brx: 9000, btx: 1100,
    }],
  })
  const now = new Date(2026, 6, 28, 12, 0, 0)
  const acct = plain(logic.restoreAccounting(stored, 'current-boot', now))

  assert.deepEqual(plain(logic.ranking(acct, 'today', now)), [])
  assert.deepEqual(plain(logic.ranking(acct, 'month', now)), [])
  assert.deepEqual(plain(logic.ranking(acct, 'boot', now)), [
    { name: 'browser', rx: 9000, tx: 1100 },
  ])
})

test('malformed and empty persisted accounting restore safely', async () => {
  const logic = await loadLogic()
  const now = new Date(2026, 6, 28, 12, 0, 0)
  assert.deepEqual(plain(logic.restoreAccounting('', 'boot', now)), {})
  assert.deepEqual(plain(logic.restoreAccounting('{bad', 'boot', now)), {})
  assert.deepEqual(plain(logic.restoreAccounting('{"apps":{}}', 'boot', now)), {})
  assert.deepEqual(plain(logic.ranking(null, 'today', now)), [])

  const damaged = JSON.stringify({
    bootId: 'boot',
    apps: [
      { n: 'bad', dk: '2026-07-28', drx: null, dtx: -1, mk: '2026-07', mrx: 'NaN', mtx: null, brx: null, btx: -2 },
      { n: '', drx: 10 },
      null,
    ],
  })
  assert.deepEqual(plain(logic.restoreAccounting(damaged, 'boot', now)), {
    bad: { dk: '2026-07-28', drx: 0, dtx: 0, mk: '2026-07', mrx: 0, mtx: 0, brx: 0, btx: 0 },
  })
})

test('restore clamps a current day into its month when the stored month key is stale', async () => {
  const logic = await loadLogic()
  const now = new Date(2026, 6, 28, 12, 0, 0)
  const stored = JSON.stringify({
    bootId: 'boot',
    apps: [{
      n: 'browser', dk: '2026-07-28', drx: 900, dtx: 90,
      mk: '2026-06', mrx: 5000, mtx: 500, brx: 900, btx: 90,
    }],
  })

  assert.deepEqual(plain(logic.restoreAccounting(stored, 'boot', now)), {
    browser: {
      dk: '2026-07-28', drx: 900, dtx: 90,
      mk: '2026-07', mrx: 900, mtx: 90, brx: 900, btx: 90,
    },
  })
})

test('collector requests TCP and UDP cumulative bytes', async () => {
  const logic = await loadLogic()
  const command = plain(logic.nethogsCommand(2))
  assert.deepEqual(command.slice(0, 5), ['stdbuf', '-oL', 'nethogs', '-t', '-C'])
  assert.deepEqual(command.slice(5), ['-v', '2', '-d', '2'])
})

test('raw cumulative trace replays exact app totals, directions, rates, and sorting', async () => {
  const logic = await loadLogic()
  const trace = await readFile(new URL('./fixtures/nethogs-v2.trace', import.meta.url), 'utf8')
  let batch = []
  let lastCum = {}
  let pendingDelta = {}
  let result = null
  let refresh = 0

  for (const line of trace.split('\n')) {
    const parsed = logic.parseNethogsLine(line)
    if (!parsed) continue
    if (parsed.refresh) {
      result = logic.commitNethogsBatch(batch, lastCum, refresh === 0 ? 0 : 2, { 303: 'electron-app' }, pendingDelta)
      lastCum = result.lastCum
      pendingDelta = result.pendingDelta
      batch = []
      refresh++
    } else {
      batch.push(parsed)
    }
  }

  const accounting = plain(result.accounting)
  assert.deepEqual(accounting, [
    { name: 'browser', rx: 900, tx: 400 },
    { name: 'udp-client', rx: 1200, tx: 200 },
    { name: 'electron-app', rx: 240, tx: 60 },
  ])
  assert.deepEqual(sum(accounting), { rx: 2340, tx: 660 })
  assert.deepEqual(plain(result.rates), [
    { name: 'udp-client', down: 600, up: 100 },
    { name: 'browser', down: 450, up: 200 },
    { name: 'electron-app', down: 120, up: 30 },
  ])
})

test('empty, null, boundary, and malformed input are handled deterministically', async () => {
  const logic = await loadLogic()
  assert.equal(logic.parseNethogsLine(null), null)
  assert.equal(logic.parseNethogsLine(''), null)
  assert.deepEqual(plain(logic.parseNethogsLine('Refreshing:')), { refresh: true })
  assert.equal(logic.parseNethogsLine('not a nethogs row'), null)
  assert.equal(logic.parseNethogsLine('/usr/bin/app/1/1000\tNaN\t12'), null)
  assert.equal(logic.parseNethogsLine('/usr/bin/app/1/1000\t-1\t12'), null)
  assert.equal(logic.parseNethogsLine('unknown SCTP/0/0\t10\t20'), null)
  assert.equal(logic.parseNethogsLine('unknown UDP/1/0\t10\t20'), null)
  assert.deepEqual(plain(logic.parseNethogsLine('unknown TCP/0/0\t10\t20')), {
    cmdline: '__unattributed_tcp', pid: '0', rx: 20, tx: 10,
  })
})

test('unknown TCP and UDP use independent cumulative deltas and preserve direction', async () => {
  const logic = await loadLogic()
  const first = [
    logic.parseNethogsLine('unknown TCP/0/0\t100\t500'),
    logic.parseNethogsLine('unknown UDP/0/0\t300\t900'),
  ]
  let state = logic.commitNethogsBatch(first, {}, 0, {}, {})

  const second = [
    logic.parseNethogsLine('unknown TCP/0/0\t140\t620'),
    logic.parseNethogsLine('unknown UDP/0/0\t500\t2100'),
  ]
  state = logic.commitNethogsBatch(second, state.lastCum, 2, {}, state.pendingDelta)

  assert.deepEqual(plain(state.accounting), [
    { name: '__unattributed_tcp', rx: 120, tx: 40 },
    { name: '__unattributed_udp', rx: 1200, tx: 200 },
  ])
  assert.deepEqual(plain(state.rates), [
    { name: '__unattributed_udp', down: 600, up: 100 },
    { name: '__unattributed_tcp', down: 60, up: 20 },
  ])
})

test('Spotify trace keeps unattributed QUIC bytes without assigning them to Spotify', async () => {
  const logic = await loadLogic()
  const first = [
    logic.parseNethogsLine('/opt/spotify/spotify/25186/1000\t100\t200'),
    logic.parseNethogsLine('unknown UDP/0/0\t300\t900'),
  ]
  let state = logic.commitNethogsBatch(first, {}, 0, {}, {})

  const second = [
    logic.parseNethogsLine('/opt/spotify/spotify/25186/1000\t160\t440'),
    logic.parseNethogsLine('unknown UDP/0/0\t500\t2100'),
  ]
  state = logic.commitNethogsBatch(second, state.lastCum, 2, {}, state.pendingDelta)

  assert.deepEqual(plain(state.accounting), [
    { name: 'spotify', rx: 240, tx: 60 },
    { name: '__unattributed_udp', rx: 1200, tx: 200 },
  ])
  assert.deepEqual(sum(plain(state.accounting)), { rx: 1440, tx: 260 })
})

test('stats period migration uses stored schema presence and preserves deliberate boot', async () => {
  const logic = await loadLogic()
  assert.deepEqual(plain(logic.migrateStatsPeriod('{"statsPeriod":"boot"}', 'boot', 1)), {
    statsPeriod: 'today', statsPeriodSchema: 1,
  })
  assert.deepEqual(plain(logic.migrateStatsPeriod('{"statsPeriod":"boot","statsPeriodSchema":1}', 'boot', 1)), {
    statsPeriod: 'boot', statsPeriodSchema: 1,
  })
  assert.deepEqual(plain(logic.migrateStatsPeriod('', '', undefined)), {
    statsPeriod: 'today', statsPeriodSchema: 1,
  })
  assert.deepEqual(plain(logic.migrateStatsPeriod('{bad', null, -1)), {
    statsPeriod: 'today', statsPeriodSchema: 1,
  })
  assert.deepEqual(plain(logic.migrateStatsPeriod('{"statsPeriod":"week","statsPeriodSchema":2}', 'today', 1)), {
    statsPeriod: 'week', statsPeriodSchema: 2,
  })
})

test('settings changes merge against latest disk accounting instead of a stale adapter snapshot', async () => {
  const logic = await loadConfigLogic()
  const latest = JSON.stringify({
    ...configDefaults,
    pingHost: 'old.example',
    acctState: 'acct-new',
    appAcctState: 'apps-new',
  })
  const result = plain(logic.mergeConfigChanges(
    latest,
    { pingHost: 'new.example', acctState: 'acct-old' },
    false,
  ))

  assert.equal(result.changed, true)
  assert.deepEqual(JSON.parse(result.serialized), {
    ...configDefaults,
    pingHost: 'new.example',
    acctState: 'acct-new',
    appAcctState: 'apps-new',
  })
})

test('only an owner can merge accounting changes while settings remain writable', async () => {
  const logic = await loadConfigLogic()
  const latest = JSON.stringify({ ...configDefaults, acctState: 'owner-acct', appAcctState: 'owner-apps' })
  const secondary = plain(logic.mergeConfigChanges(
    latest,
    { displayMode: 'stacked', acctState: 'stale-acct', appAcctState: 'stale-apps' },
    false,
  ))
  assert.deepEqual(JSON.parse(secondary.serialized), {
    ...configDefaults,
    displayMode: 'stacked',
    acctState: 'owner-acct',
    appAcctState: 'owner-apps',
  })
  const owner = plain(logic.mergeConfigChanges(latest, { acctState: 'next-acct' }, true))
  assert.equal(JSON.parse(owner.serialized).acctState, 'next-acct')
})

test('future schema fields survive load, materialization, and later settings writes', async () => {
  const logic = await loadConfigLogic()
  const futureRaw = JSON.stringify({
    statsPeriod: 'week', statsPeriodSchema: 3,
    futureMode: { rollingDays: 7 }, acctState: 'acct-current',
  })
  const prepared = plain(logic.prepareConfig(futureRaw, configDefaults, true, 1))
  assert.equal(prepared.futureSchema, true)
  assert.equal(prepared.shouldWrite, false)
  assert.equal(prepared.serialized, futureRaw)
  assert.equal(prepared.values.statsPeriod, 'week')
  assert.equal(prepared.values.updateInterval, 2000)

  const changed = plain(logic.mergeConfigChanges(futureRaw, { pingHost: 'dns.example' }, false))
  assert.deepEqual(JSON.parse(changed.serialized), {
    statsPeriod: 'week', statsPeriodSchema: 3,
    futureMode: { rollingDays: 7 }, acctState: 'acct-current', pingHost: 'dns.example',
  })
})

test('config preparation handles empty and malformed input safely', async () => {
  const logic = await loadConfigLogic()
  for (const serialized of ['', '{bad', 'null', '[]']) {
    const prepared = plain(logic.prepareConfig(serialized, configDefaults, false, 1))
    assert.equal(prepared.futureSchema, false)
    assert.equal(prepared.shouldWrite, false)
    assert.deepEqual(prepared.values, configDefaults)
  }
  const ignored = plain(logic.mergeConfigChanges('{bad', { acctState: 'not-owner' }, false))
  assert.equal(ignored.changed, false)
  assert.deepEqual(JSON.parse(ignored.serialized), {})
})

test('legacy boot default migrates before owner write without removing boot selection', async () => {
  const configSource = await readFile(new URL('../ConfigLoader.qml', import.meta.url), 'utf8')
  const barSource = await readFile(new URL('../bar.qml', import.meta.url), 'utf8')

  assert.match(configSource, /property string statsPeriod: "today"/)
  assert.match(configSource, /property int statsPeriodSchema: 1/)
  assert.match(configSource, /property bool materializing: true/)
  assert.match(configSource, /onFileChanged:[\s\S]*materializing = true[\s\S]*reload\(\)/)
  const fileChangedBody = configSource.match(/onFileChanged: \{([\s\S]*?)\n    \}/)?.[1] ?? ''
  assert.doesNotMatch(fileChangedBody, /ready = false/)
  assert.doesNotMatch(configSource, /writeAdapter\(\)/)
  assert.match(configSource, /ConfigLogic\.prepareConfig\(text\(\), root\.defaults, root\.owner, 1\)/)
  assert.match(configSource, /if \(prepared\.shouldWrite\)\s+setText\(prepared\.serialized\)/)
  assert.match(barSource, /cfg\.options\.statsPeriod === "boot"[\s\S]*\? cfg\.options\.statsPeriod : "today"/)
  const migrationBody = configSource.match(/function migrateStatsPeriod\(\) \{([\s\S]*?)\n    \}/)?.[1] ?? ''
  assert.doesNotMatch(migrationBody, /acctState\s*=/)
  assert.doesNotMatch(migrationBody, /appAcctState\s*=/)
})

test('setting intents accept only the public typed allowlist and exact boundaries', async () => {
  const logic = await loadConfigLogic()
  const accepted = [
    ['displayMode', '"auto"', 'auto'],
    ['displayMode', '"stacked"', 'stacked'],
    ['displayMode', '"horizontal"', 'horizontal'],
    ['autoStackMaxWidth', '800', 800],
    ['autoStackMaxWidth', '7680', 7680],
    ['stackedShowIcons', 'false', false],
    ['statsPeriod', '"boot"', 'boot'],
    ['statsPeriod', '"today"', 'today'],
    ['statsPeriod', '"month"', 'month'],
    ['appMonitoring', 'true', true],
    ['updateInterval', '500', 500],
    ['updateInterval', '10000', 10000],
    ['breatheThresholdKB', '64', 64],
    ['breatheThresholdKB', '65536', 65536],
    ['pingHost', '"auto"', 'auto'],
    ['pingHost', '"2001:db8::1"', '2001:db8::1'],
  ]
  for (const [key, serialized, value] of accepted) {
    assert.deepEqual(plain(logic.decodeSettingIntent(key, serialized)), {
      accepted: true, key, value,
    })
  }

  const rejected = [
    [null, 'true'], ['', 'true'], ['displayMode', null], ['acctState', '"stale"'],
    ['appAcctState', '"stale"'], ['statsPeriodSchema', '2'],
    ['displayMode', '"wide"'], ['displayMode', 'null'],
    ['autoStackMaxWidth', '799'], ['autoStackMaxWidth', '7681'],
    ['autoStackMaxWidth', '800.5'], ['stackedShowIcons', '"false"'],
    ['statsPeriod', '"week"'], ['appMonitoring', '1'],
    ['updateInterval', '499'], ['updateInterval', '10001'],
    ['breatheThresholdKB', '63'], ['breatheThresholdKB', '65537'],
    ['pingHost', '""'], ['pingHost', '"bad\\nhost"'],
    ['pingHost', JSON.stringify('x'.repeat(256))], ['pingHost', '{bad'],
  ]
  for (const [key, serialized] of rejected)
    assert.deepEqual(plain(logic.decodeSettingIntent(key, serialized)), { accepted: false })
})

test('settings and secondary bars send intents while only the primary owner writes config', async () => {
  const settingsSource = await readFile(new URL('../settings.qml', import.meta.url), 'utf8')
  const senderSource = await readFile(new URL('../ConfigRequest.qml', import.meta.url), 'utf8')
  const configSource = await readFile(new URL('../ConfigLoader.qml', import.meta.url), 'utf8')
  const barSource = await readFile(new URL('../bar.qml', import.meta.url), 'utf8')

  assert.doesNotMatch(settingsSource, /cfg\.options\.[A-Za-z]+\s*=(?!=)/)
  assert.match(settingsSource, /ConfigRequest\s*\{\s*id:\s*configRequest/)
  for (const key of ['displayMode', 'autoStackMaxWidth', 'stackedShowIcons',
    'appMonitoring', 'updateInterval', 'breatheThresholdKB', 'pingHost']) {
    assert.match(settingsSource, new RegExp(`configRequest\\.send\\("${key}"`))
  }

  assert.match(senderSource, /command:\s*request === null \? \[\] : \[[\s\S]*"qs", "-c", "ii", "ipc", "--any-display", "call",/)
  assert.match(senderSource, /"network_traffic", "setSetting"/)
  assert.doesNotMatch(senderSource, /\["sh",\s*"-c"/)
  assert.match(senderSource, /const next = root\.queue\.filter\(request => request\.key !== key\)/)
  assert.match(senderSource, /property int maxAttempts:\s*8/)
  assert.match(senderSource, /if \(exitCode !== 0 && request\.attempts < root\.maxAttempts\)/)

  assert.match(configSource, /function queueChange\(key, value\) \{[\s\S]*!root\.ownerReady/)
  assert.match(configSource, /function requestSerializedSetting\(key, serializedValue\)/)
  assert.match(configSource, /ConfigLogic\.decodeSettingIntent\(key, serializedValue\)/)
  assert.match(configSource, /if \(!root\.ownerReady \|\| !intent\.accepted\)\s*return false/)

  assert.match(barSource, /IpcHandler\s*\{[\s\S]*enabled:\s*cfg\.ownerReady[\s\S]*target:\s*cfg\.ownerReady \? "network_traffic"/)
  assert.match(barSource, /network_traffic_reader_/)
  assert.match(barSource, /function setSetting\(key:\s*string, serializedValue:\s*string\):\s*void/)
  assert.match(barSource, /cfg\.requestSerializedSetting\(key, serializedValue\)/)
  assert.match(barSource, /function requestSetting\(key, value\)/)
  assert.match(barSource, /configRequest\.send\(key, value\)/)
  assert.doesNotMatch(barSource, /cfg\.options\.statsPeriod\s*=(?!=)/)
})

test('multi-monitor bars elect one accounting writer and keep readers read-only', async () => {
  const barSource = await readFile(new URL('../bar.qml', import.meta.url), 'utf8')
  const appSource = await readFile(new URL('../AppTraffic.qml', import.meta.url), 'utf8')
  const trafficSource = await readFile(new URL('../TrafficLogic.qml', import.meta.url), 'utf8')
  const configSource = await readFile(new URL('../ConfigLoader.qml', import.meta.url), 'utf8')

  assert.match(barSource, /readonly property bool isPrimary:[\s\S]*Quickshell\.screens[\s\S]*name === screens\[0\]\.name/)
  assert.match(barSource, /ConfigLoader \{[\s\S]*?id: cfg[\s\S]*?owner: root\.isPrimary[\s\S]*?onRelinquishing:[\s\S]*?appTraffic\.flushAcct\(\)[\s\S]*?logic\.flushAccounting\(\)[\s\S]*?\}/)
  assert.match(barSource, /TrafficLogic[\s\S]*writer: cfg\.ownerReady/)
  assert.match(barSource, /AppTraffic[\s\S]*active: cfg\.ownerReady[\s\S]*writer: cfg\.ownerReady/)
  assert.match(appSource, /property bool writer: true/)
  assert.match(appSource, /if \(!writer \|\| !store \|\| !acctLoaded\) return/)
  assert.match(appSource, /onAppAcctStateChanged[\s\S]*!root\.writer[\s\S]*root\.loadAccounting\(\)/)
  assert.match(appSource, /onWriterChanged:[\s\S]*if \(writer && acctLoaded && storeReady\) loadAccounting\(\)/)
  assert.match(trafficSource, /property bool writer: true/)
  assert.match(trafficSource, /if \(!writer \|\| !store \|\| !acctReady\) return/)
  assert.match(trafficSource, /onAcctStateChanged[\s\S]*!root\.writer[\s\S]*root\.loadStoredAccounting\(\)/)
  assert.match(trafficSource, /onWriterChanged:[\s\S]*acctReady = false[\s\S]*initAccounting\(previousStats\.rx, previousStats\.tx\)/)
  assert.match(configSource, /blockWrites: true/)
  assert.match(configSource, /atomicWrites: true/)
  assert.match(configSource, /signal relinquishing(?:\(\))?/)
  assert.match(configSource, /property bool acquiringOwner: false/)
  assert.match(configSource, /onLoaded:[\s\S]*const acquiring = root\.acquiringOwner;[\s\S]*root\.acquiringOwner = false;[\s\S]*root\.ownerReady = true/)
  assert.match(configSource, /onOwnerChanged:[\s\S]*root\.acquiringOwner = true[\s\S]*ownerReload\.restart\(\)/)
  assert.match(configSource, /^import QtQuick$/m)
  assert.match(configSource, /property var ownerReload(?:\s*:\s*Timer \{|\s*$[\s\S]*ownerReload:\s*Timer \{)[\s\S]*interval: 100[\s\S]*root\.reload\(\)/m)
  assert.match(configSource, /ConfigLogic\.mergeConfigChanges\([\s\S]*latest, changes, root\.owner \|\| root\.ownerReady\)/)
  assert.match(configSource, /root\.reload\(\);[\s\S]*const latest = root\.text\(\)/)
})

test('inactive and fallback lifecycle guards prevent late callbacks and concurrent collectors', async () => {
  const source = await readFile(new URL('../AppTraffic.qml', import.meta.url), 'utf8')
  assert.match(source, /else \{[\s\S]*startupTimeout\.stop\(\)[\s\S]*nethogs\.running = false[\s\S]*ssTimer\.stop\(\)[\s\S]*ssProc\.running = false/)
  assert.match(source, /function startSsFallback\(\) \{[\s\S]*if \(!root\.active\) return[\s\S]*startupTimeout\.stop\(\)[\s\S]*nethogs\.running = false/)
  assert.match(source, /onTriggered: \{\s*if \(!root\.active\) return;/)
  assert.match(source, /onRead: data => \{\s*if \(!root\.active \|\| root\.source === "ss"\) return;/)
  assert.match(source, /ssStopping = ssStopping \|\| ssProc\.running/)
  assert.match(source, /nethogsStopping = nethogsStopping \|\| nethogs\.running/)
  assert.match(source, /onStreamFinished: \{\s*if \(root\.active && root\.source === "ss"\)/)
  assert.match(source, /const requestedStop = root\.nethogsStopping[\s\S]*if \(root\.fallbackPending\)[\s\S]*else if \(requestedStop && root\.source === "starting"[\s\S]*root\.startNethogs\(\)[\s\S]*else \{[\s\S]*root\.startSsFallback\(\)/)
})

test('popup translates unattributed sentinel labels in supported locales', async () => {
  const source = await readFile(new URL('../TrafficPopup.qml', import.meta.url), 'utf8')
  const zhTW = JSON.parse(await readFile(new URL('../translations/zh_TW.json', import.meta.url), 'utf8'))
  const zhCN = JSON.parse(await readFile(new URL('../translations/zh_CN.json', import.meta.url), 'utf8'))
  assert.match(source, /name === "__unattributed_udp"[\s\S]*Translation\.tr\("Unattributed UDP"\)/)
  assert.match(source, /name === "__unattributed_tcp"[\s\S]*Translation\.tr\("Unattributed TCP"\)/)
  assert.equal(zhTW['Unattributed UDP'], '未歸屬 UDP')
  assert.equal(zhTW['Unattributed TCP'], '未歸屬 TCP')
  assert.equal(zhCN['Unattributed UDP'], '未归属 UDP')
  assert.equal(zhCN['Unattributed TCP'], '未归属 TCP')
})

test('a process absent for one snapshot gets a fresh baseline if its identity reappears', async () => {
  const logic = await loadLogic()
  const baseline = [{ cmdline: '/usr/bin/app', pid: '42', rx: 1000, tx: 500 }]
  let state = logic.commitNethogsBatch(baseline, {}, 0, {}, {})

  state = logic.commitNethogsBatch([], state.lastCum, 2, {}, state.pendingDelta)
  const reusedIdentity = [{ cmdline: '/usr/bin/app', pid: '42', rx: 4000, tx: 2500 }]
  state = logic.commitNethogsBatch(reusedIdentity, state.lastCum, 2, {}, state.pendingDelta)
  assert.deepEqual(plain(state.accounting), [])
  assert.deepEqual(plain(state.rates), [])
})

test('pruning rolls an expired Other bucket into the current day and month', async () => {
  const logic = await loadLogic()
  const now = new Date(2026, 7, 1, 12, 0, 0)
  const acct = {
    __other: {
      dk: '2026-07-31', drx: 900, dtx: 90,
      mk: '2026-07', mrx: 5000, mtx: 500,
      brx: 8000, btx: 800,
    },
  }
  for (let index = 0; index < 31; index++) {
    acct[`app-${index}`] = {
      dk: '2026-08-01', drx: index + 1, dtx: 0,
      mk: '2026-08', mrx: index + 1, mtx: 0,
      brx: index + 1, btx: 0,
    }
  }

  const pruned = plain(logic.pruneAccounting(acct, '__other', 30, now))
  assert.deepEqual(pruned.__other, {
    dk: '2026-08-01', drx: 1, dtx: 0,
    mk: '2026-08', mrx: 1, mtx: 0,
    brx: 8001, btx: 800,
  })
  assert.deepEqual(plain(logic.ranking(pruned, 'month', now)).find(row => row.name === '__other'), {
    name: '__other', rx: 1, tx: 0,
  })
})

test('pruning keeps unattributed identities outside the named-app limit', async () => {
  const logic = await loadLogic()
  const now = new Date(2026, 7, 1, 12, 0, 0)
  const acct = {
    __unattributed_udp: {
      dk: '2026-08-01', drx: 500, dtx: 50,
      mk: '2026-08', mrx: 500, mtx: 50,
      brx: 500, btx: 50,
    },
  }
  for (let index = 0; index < 31; index++) {
    acct[`app-${index}`] = {
      dk: '2026-08-01', drx: index + 1, dtx: 0,
      mk: '2026-08', mrx: index + 1, mtx: 0,
      brx: index + 1, btx: 0,
    }
  }

  const pruned = plain(logic.pruneAccounting(acct, '__other', 30, now))
  assert.deepEqual(pruned.__unattributed_udp, acct.__unattributed_udp)
  assert.equal(Object.keys(pruned).filter(name => name.startsWith('app-')).length, 30)
  assert.ok(pruned.__other)
})

test('PID disappearance conserves unresolved deltas and clears stale comm names', async () => {
  const logic = await loadLogic()
  const entry = [{ cmdline: '/proc/self/exe', pid: '77', rx: 10, tx: 20 }]
  let state = logic.commitNethogsBatch(entry, {}, 0, {}, {})
  state = logic.commitNethogsBatch(
    [{ cmdline: '/proc/self/exe', pid: '77', rx: 110, tx: 70 }],
    state.lastCum,
    2,
    {},
    state.pendingDelta,
  )
  assert.deepEqual(plain(state.pendingDelta), {
    '/proc/self/exe/77': { pid: '77', rx: 100, tx: 50 },
  })

  state = logic.commitNethogsBatch([], state.lastCum, 2, {}, state.pendingDelta)
  assert.deepEqual(plain(state.pendingDelta), {})
  assert.deepEqual(plain(state.accounting), [
    { name: '__unattributed_process', rx: 100, tx: 50 },
  ])
  assert.deepEqual(plain(state.activePids), [])

  let reused = logic.commitNethogsBatch(entry, state.lastCum, 2, { 77: 'old-process' }, state.pendingDelta)
  assert.deepEqual(plain(reused.accounting), [])
  assert.deepEqual(plain(reused.commByPid), {})

  reused = logic.commitNethogsBatch(
    [{ cmdline: '/proc/self/exe', pid: '77', rx: 30, tx: 30 }],
    reused.lastCum,
    2,
    reused.commByPid,
    reused.pendingDelta,
  )
  assert.deepEqual(plain(reused.accounting), [])
  assert.deepEqual(plain(reused.pendingDelta), {
    '/proc/self/exe/77': { pid: '77', rx: 20, tx: 10 },
  })
})

test('an active unresolved PID remains queued while a previous ps query is busy', async () => {
  const logic = await loadLogic()
  const first = [{ cmdline: '/proc/self/exe', pid: '77', rx: 10, tx: 20 }]
  let state = logic.commitNethogsBatch(first, {}, 0, {}, {})
  state = logic.commitNethogsBatch(
    [{ cmdline: '/proc/self/exe', pid: '77', rx: 110, tx: 70 }],
    state.lastCum,
    2,
    {},
    state.pendingDelta,
  )
  assert.deepEqual(plain(state.unresolvedPids), ['77'])

  state = logic.commitNethogsBatch(
    [{ cmdline: '/proc/self/exe', pid: '77', rx: 110, tx: 70 }],
    state.lastCum,
    2,
    {},
    state.pendingDelta,
  )
  assert.deepEqual(plain(state.unresolvedPids), ['77'])
})

test('resolved comms drain pending bytes immediately without another nethogs batch', async () => {
  const logic = await loadLogic()
  const pending = {
    '/proc/self/exe/77': { pid: '77', rx: 100, tx: 50 },
    '/proc/self/exe/88': { pid: '88', rx: 30, tx: 10 },
  }
  const drained = plain(logic.drainResolvedPending(
    pending,
    { 77: 'resolved-app', 88: 'stale-app' },
    ['77'],
  ))
  assert.deepEqual(drained.accounting, [{ name: 'resolved-app', rx: 100, tx: 50 }])
  assert.deepEqual(drained.pendingDelta, {})
  assert.deepEqual(drained.commByPid, { 77: 'resolved-app' })
})

test('QML isolates ps results by monitoring generation and entry lifecycle', async () => {
  const source = await readFile(new URL('../AppTraffic.qml', import.meta.url), 'utf8')
  assert.match(source, /property int monitoringGeneration:/)
  assert.match(source, /property int psQuerySerial:/)
  assert.match(source, /property bool psStopping:/)
  assert.match(source, /psProc\.running = false/)
  assert.match(source, /psProc\.pendingEntryIds = Object\.keys\(root\.pendingDelta\)/)
  assert.match(source, /psProc\.generation = root\.monitoringGeneration/)
  assert.match(source, /psProc\.querySerial = \+\+root\.psQuerySerial/)
  assert.match(source, /psProc\.generation !== root\.monitoringGeneration[\s\S]*psProc\.querySerial !== root\.psQuerySerial/)
  assert.match(source, /result\.activeEntryIds\.includes\(entryId\)/)
  assert.match(source, /root\.psStopping = true[\s\S]*psProc\.running = false/)
  assert.match(source, /AppTrafficLogic\.drainResolvedPending\(/)
  assert.match(source, /for \(const app of drained\.accounting\) root\.accumulate\(/)
})

test('counter shrink does not fabricate traffic', async () => {
  const logic = await loadLogic()
  const baseline = [{ cmdline: '/usr/bin/app', pid: '42', rx: 1000, tx: 500 }]
  let state = logic.commitNethogsBatch(baseline, {}, 0, {}, {})
  const shrunk = [{ cmdline: '/usr/bin/app', pid: '42', rx: 20, tx: 10 }]
  state = logic.commitNethogsBatch(shrunk, state.lastCum, 2, {}, state.pendingDelta)
  assert.deepEqual(plain(state.accounting), [])
})

test('counter shrink clears cached PID identity and pending bytes before re-resolution', async () => {
  const logic = await loadLogic()
  const baseline = [{ cmdline: '/proc/self/exe', pid: '42', rx: 1000, tx: 500 }]
  let state = logic.commitNethogsBatch(baseline, {}, 0, { 42: 'old-app' }, {})
  state = logic.commitNethogsBatch(
    [{ cmdline: '/proc/self/exe', pid: '42', rx: 20, tx: 10 }],
    state.lastCum, 2, { 42: 'old-app' },
    { '/proc/self/exe/42': { pid: '42', rx: 100, tx: 50 } },
  )
  assert.deepEqual(plain(state.accounting), [
    { name: '__unattributed_process', rx: 100, tx: 50 },
  ])
  assert.deepEqual(plain(state.commByPid), {})
  assert.deepEqual(plain(state.pendingDelta), {})

  state = logic.commitNethogsBatch(
    [{ cmdline: '/proc/self/exe', pid: '42', rx: 50, tx: 25 }],
    state.lastCum, 2, state.commByPid, state.pendingDelta,
  )
  assert.deepEqual(plain(state.accounting), [])
  assert.deepEqual(plain(state.pendingDelta), {
    '/proc/self/exe/42': { pid: '42', rx: 30, tx: 15 },
  })
  assert.deepEqual(plain(state.unresolvedPids), ['42'])
})

test('unattributed counter shrink establishes a new baseline without fabricated bytes', async () => {
  const logic = await loadLogic()
  const baseline = [logic.parseNethogsLine('unknown UDP/0/0\t500\t1000')]
  let state = logic.commitNethogsBatch(baseline, {}, 0, {}, {})

  const shrunk = [logic.parseNethogsLine('unknown UDP/0/0\t20\t40')]
  state = logic.commitNethogsBatch(shrunk, state.lastCum, 2, {}, state.pendingDelta)
  assert.deepEqual(plain(state.accounting), [])
  assert.deepEqual(plain(state.rates), [])

  const resumed = [logic.parseNethogsLine('unknown UDP/0/0\t30\t70')]
  state = logic.commitNethogsBatch(resumed, state.lastCum, 2, {}, state.pendingDelta)
  assert.deepEqual(plain(state.accounting), [
    { name: '__unattributed_udp', rx: 30, tx: 10 },
  ])
})

test('unresolved executable deltas are credited once after comm resolution', async () => {
  const logic = await loadLogic()
  const first = [{ cmdline: '/proc/self/exe', pid: '77', rx: 10, tx: 20 }]
  let state = logic.commitNethogsBatch(first, {}, 0, {}, {})
  const second = [{ cmdline: '/proc/self/exe', pid: '77', rx: 110, tx: 70 }]
  state = logic.commitNethogsBatch(second, state.lastCum, 2, {}, state.pendingDelta)
  assert.deepEqual(plain(state.accounting), [])

  state = logic.commitNethogsBatch(second, state.lastCum, 2, { 77: 'resolved-app' }, state.pendingDelta)
  assert.deepEqual(plain(state.accounting), [{ name: 'resolved-app', rx: 100, tx: 50 }])
  assert.deepEqual(plain(state.pendingDelta), {})
})

test('handoff finalization conserves unresolved bytes exactly once in an unattributed bucket', async () => {
  const logic = await loadLogic()
  const pending = {
    '/proc/self/exe/77': { pid: '77', rx: 100, tx: 50 },
    '/proc/self/exe/88': { pid: '88', rx: 30, tx: 10 },
  }
  const finalized = plain(logic.finalizePending(pending, { 77: 'resolved-app' }, '__unattributed_process'))
  assert.deepEqual(finalized.accounting, [
    { name: 'resolved-app', rx: 100, tx: 50 },
    { name: '__unattributed_process', rx: 30, tx: 10 },
  ])
  assert.deepEqual(finalized.pendingDelta, {})
  assert.deepEqual(sum(finalized.accounting), { rx: 130, tx: 60 })

  const repeated = plain(logic.finalizePending(finalized.pendingDelta, {}, '__unattributed_process'))
  assert.deepEqual(repeated.accounting, [])
  assert.deepEqual(repeated.pendingDelta, {})

  const malformed = plain(logic.finalizePending({
    null: null,
    negative: { pid: '1', rx: -1, tx: -2 },
    damaged: { pid: null, rx: 7, tx: 'bad' },
  }, null, ''))
  assert.deepEqual(malformed.accounting, [
    { name: '__unattributed_process', rx: 7, tx: 0 },
  ])
  assert.deepEqual(plain(logic.finalizePending(null, null, null).accounting), [])
})

test('QML finalizes pending bytes before inactive reset and ownership flush', async () => {
  const appSource = await readFile(new URL('../AppTraffic.qml', import.meta.url), 'utf8')
  const barSource = await readFile(new URL('../bar.qml', import.meta.url), 'utf8')
  assert.match(appSource, /function finalizePendingAccounting\(\)/)
  assert.match(appSource, /else \{[\s\S]*finalizePendingAccounting\(\)[\s\S]*pendingDelta = \{\}/)
  assert.match(barSource, /onRelinquishing: \{[\s\S]*appTraffic\.finalizePendingAccounting\(\)[\s\S]*appTraffic\.flushAcct\(\)/)
})
