import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const moduleRoot = new URL('../', import.meta.url)
const read = (name) => readFile(new URL(name, moduleRoot), 'utf8')

const source = await read('ReplyLogic.js')
const context = vm.createContext({})
vm.runInContext(source.replace('.pragma library', ''), context)
const L = context

const manifest = JSON.parse(await read('module.json'))
const field = await read('ReplyField.qml')

const NOTIFS = 'services/Notifications.qml'
const ITEM = 'modules/common/widgets/NotificationItem.qml'
const POPUP = 'modules/ii/notificationPopup/NotificationPopup.qml'
const patchesFor = (file) => manifest.patches.filter((p) => p.file === file)
const contentFor = (file) => patchesFor(file).map((p) => p.content).join('\n')

function liveNotification(extra = {}) {
  return { hasInlineReply: true, inlineReplyPlaceholder: 'Reply to Amy', sendInlineReply() {}, ...extra }
}

test('a reply needs a live notification with an inline-reply action', () => {
  assert.equal(L.canReply(liveNotification()), true)
  assert.equal(L.canReply(null), false, 'restored entries have no live object')
  assert.equal(L.canReply(undefined), false)
  assert.equal(L.canReply(liveNotification({ hasInlineReply: false })), false)
  assert.equal(L.canReply(liveNotification({ hasInlineReply: 'true' })), false)
  assert.equal(L.canReply(liveNotification({ sendInlineReply: undefined })), false, 'older Quickshell without the API')
})

test('the placeholder comes from the app, else the fallback', () => {
  assert.equal(L.placeholder(liveNotification(), 'Reply…'), 'Reply to Amy')
  assert.equal(L.placeholder(liveNotification({ inlineReplyPlaceholder: '  Reply\n to  Amy ' }), 'Reply…'), 'Reply to Amy')
  assert.equal(L.placeholder(liveNotification({ inlineReplyPlaceholder: '' }), 'Reply…'), 'Reply…')
  assert.equal(L.placeholder(liveNotification({ inlineReplyPlaceholder: '   ' }), 'Reply…'), 'Reply…')
  assert.equal(L.placeholder(liveNotification({ inlineReplyPlaceholder: 7 }), 'Reply…'), 'Reply…')
  assert.equal(L.placeholder(null, 'Reply…'), 'Reply…')
})

test('the app-supplied placeholder can never carry markup', () => {
  // A sender could put HTML in its reply-action label; Qt would load the
  // image if the label were rendered as rich text.
  const label = L.placeholder(liveNotification({ inlineReplyPlaceholder: '<img src=http://198.51.100.7/x.png>Reply' }), 'Reply…')
  assert.equal(label, '‹img src=http://198.51.100.7/x.png›Reply')
  assert.doesNotMatch(label, /[<>]/)
  // The field draws it itself as plain text, never through the style's
  // placeholder (an AutoText item without a textFormat).
  assert.doesNotMatch(field, /placeholderText\s*:/)
  assert.match(field, /textFormat: Text\.PlainText\n\s+elide: Text\.ElideRight\n\s+maximumLineCount: 1\n\s+text: root\.hint/)
  assert.match(field, /Accessible\.name: root\.hint/)
})

test('the reply limit is explicit and a cut paste is reported', () => {
  assert.equal(L.MAX_REPLY_LENGTH, 32767)
  assert.match(field, /maximumLength: Logic\.MAX_REPLY_LENGTH/)
  assert.match(field, /visible: field\.length >= field\.maximumLength/)
})

test('losing focus ends composing so the popup gives the keyboard back', () => {
  assert.match(field, /\} else if \(root\.composing\) \{[\s\S]*?if \(!field\.activeFocus && root\.composing\)\n\s+root\.stopComposing\(\);/)
})

test('only non-blank text is sent, trimmed', () => {
  assert.equal(L.replyText('  on my way  '), 'on my way')
  assert.equal(L.replyText('ok'), 'ok')
  assert.equal(L.replyText(''), '')
  assert.equal(L.replyText(' \n\t '), '')
  assert.equal(L.replyText(null), '')
  assert.equal(L.replyText(undefined), '')
  assert.equal(L.replyText(42), '')
})

test('the hosting notification group is the nearest ancestor with notificationGroup and a boolean popup', () => {
  const group = { notificationGroup: {}, popup: true, parent: null }
  const list = { parent: { parent: group } }
  const item = { parent: { parent: list } }
  const field = { parent: item }
  assert.equal(L.hostGroup(field), group)
  const fake = { notificationGroup: {}, popup: 'yes', parent: group }
  assert.equal(L.hostGroup({ parent: fake }), group, 'a non-boolean popup is not a group')
  assert.equal(L.hostGroup({ parent: { parent: null } }), null)
  assert.equal(L.hostGroup(null), null)
})

test('releasing a popup times it out only when the pointer is off its group', () => {
  assert.equal(L.timeoutAfterRelease({ popup: true }, { containsMouse: false }), true)
  assert.equal(L.timeoutAfterRelease({ popup: true }, null), true)
  assert.equal(L.timeoutAfterRelease({ popup: true }, { containsMouse: true }), false)
  assert.equal(L.timeoutAfterRelease({ popup: false }, { containsMouse: false }), false)
  assert.equal(L.timeoutAfterRelease(null, { containsMouse: false }), false)
})

test('navigation and focus-chain keys stay inside the field', () => {
  // Qt::Key_Tab, Key_Backtab, Key_Up, Key_Down, Key_PageUp, Key_PageDown
  for (const key of [0x01000001, 0x01000002, 0x01000013, 0x01000015, 0x01000016, 0x01000017])
    assert.equal(L.containsKey(key), true, key.toString(16))
  // Letters, Return, Escape and Left/Right reach the field's own handlers.
  for (const key of [0x41, 0x20, 0x01000004, 0x01000000, 0x01000012, 0x01000014])
    assert.equal(L.containsKey(key), false, key.toString(16))
})

test('patches are insert-only, fenced-content free, and limited to the notification files', () => {
  assert.ok(manifest.patches.length > 0)
  for (const patch of manifest.patches) {
    assert.ok([NOTIFS, ITEM, POPUP].includes(patch.file), patch.file)
    assert.ok(['insert-after', 'insert-before'].includes(patch.op), patch.op)
    assert.doesNotMatch(patch.content, />>> iimp |<<< iimp /)
    assert.ok(patch.anchor.length >= 10, patch.anchor)
    assert.doesNotMatch(patch.anchor, /\n/)
    assert.ok(patch.content.endsWith('\n'), `${patch.file}: content ends with a newline`)
  }
  assert.deepEqual(manifest.capabilities, [])
})

test('every anchor is guarded by a probe on the same file', () => {
  for (const patch of manifest.patches) {
    const guarded = manifest.compat.probes.some(
      (probe) => probe.type === 'file-contains' && probe.path === patch.file && probe.pattern.includes(patch.anchor.trim()),
    )
    assert.ok(guarded, `${patch.file}: ${patch.anchor}`)
  }
})

test('the server patch turns on inline replies and nothing else changes behaviour unguarded', () => {
  const notifs = contentFor(NOTIFS)
  assert.match(notifs, /^\s+inlineReplySupported: true$/m)
  assert.match(notifs, /^\s+property bool iimpReplyHold: false$/m)
  assert.match(notifs, /^\s+property int iimpReplyComposer: -1$/m)
  // The timeout guard returns early only for a held popup.
  assert.match(notifs, /if \(root\.list\.find\(\(notif\) => notif\.notificationId === id\)\?\.iimpReplyHold\) return;/)
  const guard = patchesFor(NOTIFS).find((p) => p.content.includes('iimpReplyHold) return'))
  assert.equal(guard.anchor.trim(), 'function timeoutNotification(id) {')
  assert.equal(guard.op, 'insert-after')
})

test('the item patch imports the module and passes the wrapper to the field', () => {
  const item = contentFor(ITEM)
  assert.match(item, /^import qs\.mod\.inline_reply as InlineReply$/m)
  assert.match(item, /InlineReply\.ReplyField \{\n\s+Layout\.fillWidth: true\n\s+notif: root\.notificationObject\n\s+urgency: root\.notificationObject\.urgency\n\s+\}/)
  // Every property the patch sets exists on ReplyField.
  for (const name of ['notif', 'urgency'])
    assert.match(field, new RegExp(`property \\w+ ${name}:`), name)
})

test('the popup takes the keyboard only while a reply is composed there', () => {
  const popup = contentFor(POPUP)
  assert.match(popup, /WlrLayershell\.keyboardFocus: Notifications\.iimpReplyComposer >= 0 \? WlrKeyboardFocus\.OnDemand : WlrKeyboardFocus\.None/)
  assert.match(popup, /HyprlandFocusGrab \{\n\s+windows: \[root\]\n\s+active: root\.visible && Notifications\.iimpReplyComposer >= 0\n\s+onCleared: Notifications\.iimpReplyComposer = -1\n\s+\}/)
})

test('the field uses exactly the names the patches declare', () => {
  for (const name of ['iimpReplyHold', 'iimpReplyComposer'])
    assert.match(field, new RegExp(name), name)
  assert.match(field, /Notifications\.timeoutNotification\(/)
  assert.match(field, /sendInlineReply\(/)
  assert.match(field, /onIimpReplyComposerChanged/)
})

test('the reply text is never logged', () => {
  for (const text of [field, source])
    assert.doesNotMatch(text, /console\.(log|info|warn|error|debug)|print\(/)
})
