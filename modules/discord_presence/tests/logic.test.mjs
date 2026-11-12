import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = await readFile(new URL('../PresenceLogic.js', import.meta.url), 'utf8')
const context = vm.createContext({})
vm.runInContext(source.replace('.pragma library', ''), context)
const L = context

// Objects cross the vm context boundary; compare as plain JSON.
const plain = value => JSON.parse(JSON.stringify(value))

const game = { id: 'osu', name: 'osu!', pid: 4242, started_at: 1000, playtime_secs: 7200, shown: true }
const line = (fields = {}) => JSON.stringify({ paused: false, away: false, discord_connected: true, game, ...fields })

test('parseStatus accepts the watch contract', () => {
  const r = plain(L.parseStatus(line()))
  assert.deepEqual(r, {
    up: true,
    paused: false,
    away: false,
    connected: true,
    game: { id: 'osu', name: 'osu!', pid: 4242, startedAt: 1000, playtimeSecs: 7200, shown: true }
  })
  const idle = plain(L.parseStatus(line({ game: null, away: true, discord_connected: false, paused: true })))
  assert.deepEqual(idle, { up: true, paused: true, away: true, connected: false, game: null })
})

test('parseStatus rejects anything that is not a status line', () => {
  for (const junk of ['', '   ', 'nope', '[]', 'null', '42', '"x"', '{}', '{"paused":"yes"}', '{"error":"no daemon"}', undefined, null, 7]) {
    assert.equal(L.parseStatus(junk), null, `junk ${JSON.stringify(junk)}`)
  }
})

test('parseStatus normalises odd game fields', () => {
  const g = fields => plain(L.parseStatus(line({ game: { ...game, ...fields } })).game)
  assert.equal(g({ playtime_secs: null }).playtimeSecs, -1)
  assert.equal(g({ playtime_secs: undefined }).playtimeSecs, -1)
  assert.equal(g({ playtime_secs: -5 }).playtimeSecs, -1)
  assert.equal(g({ playtime_secs: true }).playtimeSecs, -1)
  assert.equal(g({ playtime_secs: 0 }).playtimeSecs, 0)
  assert.equal(g({ playtime_secs: 12.9 }).playtimeSecs, 12)
  assert.equal(g({ started_at: -1 }).startedAt, 0)
  assert.equal(g({ started_at: 'x' }).startedAt, 0)
  assert.equal(g({ pid: null }).pid, 0)
  assert.equal(g({ shown: 'true' }).shown, false)
  assert.equal(g({ name: '  Celeste  ' }).name, 'Celeste')
  assert.equal(g({ name: '' }).name, 'osu', 'falls back to the id')
  assert.equal(plain(L.parseStatus(line({ game: { name: '', id: '' } }))).game, null)
  assert.equal(plain(L.parseStatus(line({ game: [] }))).game, null)
  assert.equal(plain(L.parseStatus(line({ game: 'osu' }))).game, null)
  // Missing optional booleans read as false.
  const bare = plain(L.parseStatus('{"paused":false}'))
  assert.deepEqual(bare, { up: true, paused: false, away: false, connected: false, game: null })
})

test('kind, visibility and marker follow the record', () => {
  const down = L.downState()
  const playing = L.parseStatus(line())
  const paused = L.parseStatus(line({ paused: true }))
  const pausedIdle = L.parseStatus(line({ paused: true, game: null }))
  const idle = L.parseStatus(line({ game: null }))
  assert.equal(L.kind(down), 'down')
  assert.equal(L.kind(null), 'down')
  assert.equal(L.kind(playing), 'playing')
  assert.equal(L.kind(paused), 'paused')
  assert.equal(L.kind(pausedIdle), 'paused')
  assert.equal(L.kind(idle), 'idle')

  for (const r of [down, playing, paused, idle]) assert.equal(L.shownFor(r, false), true)
  assert.equal(L.shownFor(idle, undefined), true)
  assert.equal(L.shownFor(down, true), false)
  assert.equal(L.shownFor(idle, true), false)
  assert.equal(L.shownFor(playing, true), true)
  assert.equal(L.shownFor(pausedIdle, true), true)

  assert.equal(L.marker(down), '')
  assert.equal(L.marker(null), '')
  assert.equal(L.marker(playing), '')
  assert.equal(L.marker(L.parseStatus(line({ away: true }))), 'away')
  assert.equal(L.marker(L.parseStatus(line({ discord_connected: false }))), 'disconnected')
  assert.equal(L.marker(L.parseStatus(line({ away: true, discord_connected: false }))), 'disconnected')
})

test('bar text is the game name only while a game is detected', () => {
  assert.equal(L.barText(L.parseStatus(line())), 'osu!')
  assert.equal(L.barText(L.parseStatus(line({ paused: true }))), 'osu!')
  assert.equal(L.barText(L.parseStatus(line({ game: null }))), '')
  assert.equal(L.barText(L.downState()), '')
  assert.equal(L.barText(null), '')
})

test('elapsed and play time extrapolation', () => {
  const r = L.parseStatus(line())
  assert.equal(L.elapsed(r, 1061), 61)
  assert.equal(L.elapsed(r, 900), 0, 'clock skew never goes negative')
  assert.equal(L.elapsed(L.parseStatus(line({ game: null })), 5000), 0)
  assert.equal(L.elapsed(L.parseStatus(line({ game: { ...game, started_at: 0 } })), 5000), 0)
  assert.equal(L.elapsed(null, 5000), 0)

  assert.equal(L.playtimeNow(r, 2000, 2000), 7200)
  assert.equal(L.playtimeNow(r, 2000, 2090.7), 7290)
  assert.equal(L.playtimeNow(r, 2000, 1990), 7200, 'never shrinks')
  assert.equal(L.playtimeNow(L.parseStatus(line({ away: true })), 2000, 2090), 7200, 'away does not count')
  assert.equal(L.playtimeNow(L.parseStatus(line({ paused: true })), 2000, 2010), 7210, 'paused still counts')
  assert.equal(L.playtimeNow(L.parseStatus(line({ game: { ...game, playtime_secs: null } })), 2000, 2010), -1)
  assert.equal(L.playtimeNow(L.parseStatus(line({ game: null })), 2000, 2010), -1)
  assert.equal(L.playtimeNow(L.downState(), 2000, 2010), -1)
  assert.equal(L.playtimeNow(null, 2000, 2010), -1)
})

test('time formatting', () => {
  assert.equal(L.formatClock(0), '0:00')
  assert.equal(L.formatClock(61), '1:01')
  assert.equal(L.formatClock(3599), '59:59')
  assert.equal(L.formatClock(3600), '1:00:00')
  assert.equal(L.formatClock(3661), '1:01:01')
  assert.equal(L.formatClock(-4), '0:00')
  assert.equal(L.formatClock('x'), '0:00')
  assert.equal(L.formatClock(undefined), '0:00')
  assert.deepEqual(plain(L.splitHours(0)), { hours: 0, minutes: 0, paddedMinutes: '00' })
  assert.deepEqual(plain(L.splitHours(59)), { hours: 0, minutes: 0, paddedMinutes: '00' })
  assert.deepEqual(plain(L.splitHours(3900)), { hours: 1, minutes: 5, paddedMinutes: '05' })
  assert.deepEqual(plain(L.splitHours(450000)), { hours: 125, minutes: 0, paddedMinutes: '00' })
  assert.deepEqual(plain(L.splitHours(-1)), { hours: 0, minutes: 0, paddedMinutes: '00' })
  assert.deepEqual(plain(L.splitHours(null)), { hours: 0, minutes: 0, paddedMinutes: '00' })
})

test('ticker runs only while the popup shows a game', () => {
  const r = L.parseStatus(line())
  assert.equal(L.needsTicker(r, true), true)
  assert.equal(L.needsTicker(r, false), false)
  assert.equal(L.needsTicker(L.parseStatus(line({ game: null })), true), false)
  assert.equal(L.needsTicker(L.downState(), true), false)
  assert.equal(L.needsTicker(null, true), false)
})

test('retry delay and binary resolution', () => {
  assert.equal(L.retryDelayMs(false), 10000)
  assert.equal(L.retryDelayMs(undefined), 10000)
  assert.equal(L.retryDelayMs(true), 1000)
  assert.equal(L.resolveBinary('discord-rpc-proxy', '/home/u'), 'discord-rpc-proxy')
  assert.equal(L.resolveBinary('  /opt/bin/drp  ', '/home/u'), '/opt/bin/drp')
  assert.equal(L.resolveBinary('', '/home/u'), 'discord-rpc-proxy')
  assert.equal(L.resolveBinary('   ', '/home/u'), 'discord-rpc-proxy')
  assert.equal(L.resolveBinary(undefined, '/home/u'), 'discord-rpc-proxy')
  assert.equal(L.resolveBinary('~/.local/bin/drp', '/home/u'), '/home/u/.local/bin/drp')
  assert.equal(L.resolveBinary('~/.local/bin/drp', '/home/u/'), '/home/u/.local/bin/drp')
  assert.equal(L.resolveBinary('~/.local/bin/drp', ''), '~/.local/bin/drp', 'no HOME: left alone')
  assert.equal(L.resolveBinary('~user/bin/drp', '/home/u'), '~user/bin/drp')
})

test('a real watch stream from the daemon parses', () => {
  // Shape copied from discord-rpc-proxy's status() (src/daemon.rs).
  const lines = [
    '{"away":false,"discord_connected":true,"game":null,"paused":false}',
    '{"away":false,"discord_connected":true,"game":{"id":"celeste","name":"Celeste","pid":1234,"playtime_secs":360,"shown":true,"started_at":1762940000},"paused":false}',
    '{"away":false,"discord_connected":true,"game":{"id":"celeste","name":"Celeste","pid":1234,"playtime_secs":372,"shown":false,"started_at":1762940000},"paused":true}'
  ]
  const kinds = lines.map(l => L.kind(L.parseStatus(l)))
  assert.deepEqual(kinds, ['idle', 'playing', 'paused'])
})
