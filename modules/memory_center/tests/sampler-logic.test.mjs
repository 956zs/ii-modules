import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const moduleRoot = new URL('../', import.meta.url)

async function read(name) {
  return readFile(new URL(name, moduleRoot), 'utf8')
}

// vm-realm values have foreign prototypes; normalize before deep comparison.
function plain(x) {
  return JSON.parse(JSON.stringify(x))
}

// Extract a brace-balanced block starting at the first match of `pattern`.
// Good enough for these files: no unbalanced braces inside their strings.
function extractBraced(source, pattern, label) {
  const idx = source.search(pattern)
  assert.notEqual(idx, -1, `${label}: pattern not found`)
  const open = source.indexOf('{', idx)
  let depth = 0
  for (let i = open; i < source.length; i++) {
    if (source[i] === '{') depth++
    else if (source[i] === '}' && --depth === 0)
      return source.slice(idx, i + 1)
  }
  assert.fail(`${label}: unbalanced braces`)
}

// --- MemInfo: /proc/meminfo parsing and formatting -------------------------

async function loadMemInfo(initial = {}) {
  const source = await read('MemInfo.qml')
  const code = [
    extractBraced(source, /function parse\(t\)/, 'MemInfo.parse'),
    extractBraced(source, /function fmt\(kb\)/, 'MemInfo.fmt'),
    extractBraced(source, /function fmtShort\(kb\)/, 'MemInfo.fmtShort'),
  ].join('\n')
  const context = {
    memTotal: 0, memFree: 0, memAvailable: 0,
    swapTotal: 0, swapFree: 0, dirty: 0,
    ...initial,
  }
  vm.createContext(context)
  vm.runInContext(code, context)
  return context
}

const MEMINFO_SAMPLE = [
  'MemTotal:       16000000 kB',
  'MemFree:         1000000 kB',
  'MemAvailable:    8000000 kB',
  'Buffers:          200000 kB',
  'SwapTotal:       4000000 kB',
  'SwapFree:        3000000 kB',
  'Dirty:                42 kB',
].join('\n')

test('MemInfo.parse reads the fields the taxonomy is built on', async () => {
  const m = await loadMemInfo()
  m.parse(MEMINFO_SAMPLE)
  assert.equal(m.memTotal, 16000000)
  assert.equal(m.memFree, 1000000)
  assert.equal(m.memAvailable, 8000000)
  assert.equal(m.swapTotal, 4000000)
  assert.equal(m.swapFree, 3000000)
  assert.equal(m.dirty, 42)
  // The exact-by-construction taxonomy: the three parts sum to MemTotal.
  const used = m.memTotal - m.memAvailable
  const reclaim = m.memAvailable - m.memFree
  assert.equal(used + reclaim + m.memFree, m.memTotal)
})

test('MemInfo.parse keeps the previous sample on torn or empty reads', async () => {
  const prev = { memTotal: 123, memFree: 45, memAvailable: 67, swapTotal: 8, swapFree: 9, dirty: 1 }
  for (const torn of ['', 'garbage', 'MemFree: 999 kB\nSwapFree: 999 kB']) {
    const m = await loadMemInfo(prev)
    m.parse(torn)
    assert.deepEqual(
      { memTotal: m.memTotal, memFree: m.memFree, memAvailable: m.memAvailable,
        swapTotal: m.swapTotal, swapFree: m.swapFree, dirty: m.dirty },
      prev,
      `torn read ${JSON.stringify(torn)} must not clobber the sample`,
    )
  }
})

test('MemInfo.parse only matches keys at line start', async () => {
  const m = await loadMemInfo()
  // "MemTotal" also appears embedded; the anchored regex must take the real line.
  m.parse('NotMemTotal: 5\nMemTotal: 100\nMemFree: 10\nMemAvailable: 50')
  assert.equal(m.memTotal, 100)
})

test('MemInfo formatting boundaries (GiB switch, decimals, rounding)', async () => {
  const m = await loadMemInfo()
  assert.equal(m.fmt(1024 * 1024), '1.00 GiB')
  assert.equal(m.fmt(10 * 1024 * 1024), '10.0 GiB')
  assert.equal(m.fmt(512 * 1024), '512 MiB')
  assert.equal(m.fmt(1536), '2 MiB')
  assert.equal(m.fmt(0), '0 MiB')
  assert.equal(m.fmtShort(1.25 * 1024 * 1024), '1.3G')
  assert.equal(m.fmtShort(204800), '200M')
  assert.equal(m.fmtShort(0), '0M')
})

// --- ProcTop: ps output parsing --------------------------------------------

async function loadProcTop(rootProps = {}) {
  const source = await read('ProcTop.qml')
  const code = extractBraced(source, /function parse\(text\)/, 'ProcTop.parse')
  const root = {
    topCount: 12, me: '', topProcs: [], otherKb: 0, otherCount: 0,
    sampledKb: 0, revision: 0,
    ...rootProps,
  }
  const context = { root }
  vm.createContext(context)
  vm.runInContext(code, context)
  return { parse: context.parse, root }
}

const PS_SAMPLE = [
  '   10 alice            4000 firefox',
  '   20 bob              3000 some app with spaces',
  '   30 root                0 kthreadd',
  'not a process line',
  '   40 alice            2000 code',
  '   50 root             1000 systemd',
  '',
].join('\n')

test('ProcTop.parse drops RSS-0 rows, sorts, folds the tail and tags own rows', async () => {
  const { parse, root } = await loadProcTop({ topCount: 3, me: 'alice' })
  parse(PS_SAMPLE)
  assert.deepEqual(plain(root.topProcs.map(p => p.rss)), [4000, 3000, 2000])
  assert.deepEqual(plain(root.topProcs.map(p => p.own)), [true, false, true])
  // comm is "the rest of the line", spaces preserved
  assert.equal(root.topProcs[1].name, 'some app with spaces')
  assert.equal(root.otherKb, 1000)
  assert.equal(root.otherCount, 1)
  assert.equal(root.sampledKb, 10000)
  assert.equal(root.revision, 1)
})

test('ProcTop.parse clamps topCount to at least one block', async () => {
  const { parse, root } = await loadProcTop({ topCount: 0 })
  parse(PS_SAMPLE)
  assert.equal(root.topProcs.length, 1)
  assert.equal(root.topProcs[0].rss, 4000)
  assert.equal(root.otherCount, 3)
  assert.equal(root.otherKb, 3000 + 2000 + 1000)
})

test('ProcTop.parse never claims ownership while the user is unresolved', async () => {
  const { parse, root } = await loadProcTop({ me: '' })
  parse(PS_SAMPLE)
  assert.ok(root.topProcs.every(p => p.own === false))
})

test('ProcTop.parse handles empty output without residue', async () => {
  const { parse, root } = await loadProcTop({ topCount: 5 })
  parse('')
  assert.deepEqual(plain(root.topProcs), [])
  assert.equal(root.otherKb, 0)
  assert.equal(root.otherCount, 0)
  assert.equal(root.sampledKb, 0)
  assert.equal(root.revision, 1)
})

// --- MemPanel.blockRows: two-row flow-treemap split -------------------------

async function loadBlockRows() {
  const source = await read('MemPanel.qml')
  const block = extractBraced(
    source, /readonly property var blockRows: \{/, 'MemPanel.blockRows')
  const body = block.slice(block.indexOf('{'))
  const context = {}
  vm.createContext(context)
  vm.runInContext(`function blockRows(procs) ${body}`, context)
  return context.blockRows
}

function procsOf(rssList) {
  return {
    revision: 1,
    topProcs: rssList.map((rss, i) => ({ pid: i + 1, name: `p${i}`, user: 'u', rss, own: false })),
  }
}

test('blockRows: empty sample yields no rows', async () => {
  const blockRows = await loadBlockRows()
  assert.deepEqual(plain(blockRows(procsOf([]))), [])
  assert.deepEqual(plain(blockRows(procsOf([0, 0]))), [])
})

test('blockRows: four or fewer items stay in a single full row', async () => {
  const blockRows = await loadBlockRows()
  const rows = blockRows(procsOf([40, 30, 20, 10]))
  assert.equal(rows.length, 1)
  assert.equal(rows[0].frac, 1)
  assert.equal(rows[0].total, 100)
  assert.equal(rows[0].items.length, 4)
})

test('blockRows: greedy split puts the dominant head alone in row one', async () => {
  const blockRows = await loadBlockRows()
  const rows = blockRows(procsOf([100, 10, 10, 10, 10, 10]))
  assert.equal(rows.length, 2)
  assert.equal(rows[0].items.length, 1)
  assert.equal(rows[0].total, 100)
  assert.equal(rows[1].items.length, 5)
  assert.ok(Math.abs(rows[0].frac + rows[1].frac - 1) < 1e-9)
})

test('blockRows: even mass splits near the middle and both rows stay non-empty', async () => {
  const blockRows = await loadBlockRows()
  const rows = blockRows(procsOf([10, 10, 10, 10, 10, 10]))
  assert.equal(rows.length, 2)
  assert.equal(rows[0].items.length, 3)
  assert.equal(rows[1].items.length, 3)
  // Area proportionality: row fracs mirror row totals.
  assert.ok(Math.abs(rows[0].frac - 0.5) < 1e-9)
})
