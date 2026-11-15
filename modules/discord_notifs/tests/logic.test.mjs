import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = await readFile(new URL('../DiscordLogic.js', import.meta.url), 'utf8')
const context = vm.createContext({})
vm.runInContext(source.replace('.pragma library', ''), context)
const L = context

test('classify: server message with channel and server', () => {
  const c = L.classify('Alice\n(#orbs, Example\'s Server)', 'hi')
  assert.deepEqual({ ...c }, { kind: 'server', reaction: false, sender: 'Alice', channel: '#orbs', server: "Example's Server" })
})

test('classify: isolate marks are stripped', () => {
  const c = L.classify('⁨Helper Bot⁩ (⁨#chat⁩, ⁨Sample Community⁩)', 'Reacted ⁨:wave:⁩ to you')
  assert.equal(c.kind, 'server')
  assert.equal(c.sender, 'Helper Bot')
  assert.equal(c.channel, '#chat')
  assert.equal(c.server, 'Sample Community')
  assert.equal(c.reaction, true)
})

test('classify: forum post keeps the post title in the channel part', () => {
  const c = L.classify('Relay\n(weekly notes · demo · 10-26 in #forum, Test Hub)', 'x')
  assert.equal(c.kind, 'server')
  assert.equal(c.sender, 'Relay')
  assert.equal(c.channel, 'weekly notes · demo · 10-26 in #forum')
  assert.equal(c.server, 'Test Hub')
})

test('classify: plain sender is a DM, parentheses without # stay a DM', () => {
  assert.equal(L.classify('Bob', 'yo').kind, 'dm')
  assert.equal(L.classify('Bob (work)', 'yo').kind, 'dm')
})

test('classify: quests and empty summaries are system', () => {
  assert.equal(L.classify('Quest Completed!', 'The X Quest has completed.').kind, 'system')
  assert.equal(L.classify('', 'x').kind, 'system')
  assert.equal(L.classify(undefined, undefined).kind, 'system')
})

test('parseList: valid, invalid, empty fall back', () => {
  assert.deepEqual([...L.parseList('["Discord","Vesktop"]', ['d'])], ['discord', 'vesktop'])
  assert.deepEqual([...L.parseList('nope', ['d'])], ['d'])
  assert.deepEqual([...L.parseList('[]', ['d'])], ['d'])
  assert.deepEqual([...L.parseList('{"a":1}', ['d'])], ['d'])
})

const list = [
  { notificationId: 1, appName: 'discord', summary: 'Bob', body: 'dm1', time: 100 },
  { notificationId: 2, appName: 'foot', summary: 'Bob', body: 'not discord', time: 200 },
  { notificationId: 3, appName: 'Discord', summary: 'Al (#g, S)', body: 'srv', time: 300 },
  { notificationId: 4, appName: 'discord', summary: 'Quest Completed!', body: 'q', time: 400 },
  { notificationId: 5, appName: 'discord', summary: 'Cy', body: 'dm2', time: 500 }
]
const apps = ['discord']

test('select: filters by app, sorts newest first, counts per kind', () => {
  const all = L.select(list, apps, 'all', 10)
  assert.deepEqual([...all.items].map(i => i.id), [5, 4, 3, 1])
  assert.deepEqual({ ...all.counts }, { all: 4, dm: 2, server: 1, other: 1 })
  assert.deepEqual([...L.select(list, apps, 'dm', 10).items].map(i => i.id), [5, 1])
  assert.deepEqual([...L.select(list, apps, 'server', 10).items].map(i => i.id), [3])
  assert.deepEqual([...L.select(list, apps, 'other', 10).items].map(i => i.id), [4])
})

test('select: cap applies after filtering and is at least 1; empty list is safe', () => {
  assert.equal(L.select(list, apps, 'all', 2).items.length, 2)
  assert.equal(L.select(list, apps, 'all', 0).items.length, 1)
  const e = L.select([], apps, 'dm', 5)
  assert.equal(e.items.length, 0)
  assert.equal(e.counts.all, 0)
})

test('nextFilter cycles and unknown names restart at all', () => {
  assert.equal(L.nextFilter('all'), 'dm')
  assert.equal(L.nextFilter('other'), 'all')
  assert.equal(L.nextFilter('bogus'), 'all')
  assert.equal(L.isFilter('dm'), true)
  assert.equal(L.isFilter('x'), false)
})

test('ago buckets', () => {
  assert.equal(L.ago(1000000, 1000000).unit, 'now')
  assert.equal(L.ago(1000000, 1000000 + 5000).unit, 'now')
  const m = L.ago(10 * 60000, 0); assert.deepEqual({ ...m }, { unit: 'min', n: 10 })
  const h = L.ago(3 * 3600000, 0); assert.deepEqual({ ...h }, { unit: 'hour', n: 3 })
  const d = L.ago(2 * 86400000, 0); assert.deepEqual({ ...d }, { unit: 'day', n: 2 })
})
