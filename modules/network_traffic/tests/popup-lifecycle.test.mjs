import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

test('DNS discovery and ping run only while the popup is active', async () => {
  const popupSource = await readFile(new URL('../TrafficPopup.qml', import.meta.url), 'utf8')

  assert.match(popupSource, /readonly property bool latencyActive: root\.active === true/)
  assert.match(popupSource, /function stopLatencyProcesses\(\) \{[\s\S]*dnsProc\.running = false[\s\S]*pingProc\.running = false[\s\S]*\}/)
  assert.match(popupSource, /onActiveChanged: \{[\s\S]*latencyGeneration\+\+[\s\S]*if \(latencyActive\)[\s\S]*startDnsDiscovery\(\)[\s\S]*else[\s\S]*stopLatencyProcesses\(\)/)
  assert.match(popupSource, /id:\s*pingTimer[\s\S]*running:\s*root\.latencyActive && root\.pingTarget !== ""[\s\S]*onTriggered: root\.startPing\(\)/)
  assert.match(popupSource, /onStreamFinished: \{[\s\S]*!root\.latencyActive \|\| dnsProc\.generation !== root\.latencyGeneration[\s\S]*return[\s\S]*root\.resolvedDns = root\.pickDns\(text\)/)
  assert.match(popupSource, /onStreamFinished: \{[\s\S]*!root\.latencyActive \|\| pingProc\.generation !== root\.latencyGeneration[\s\S]*return[\s\S]*root\.pingMs = parseFloat\(m\[1\]\)/)
  assert.match(popupSource, /onExited: \(exitCode, exitStatus\) => \{[\s\S]*!root\.latencyActive \|\| pingProc\.generation !== root\.latencyGeneration[\s\S]*return[\s\S]*root\.pingMs = -2/)
})
