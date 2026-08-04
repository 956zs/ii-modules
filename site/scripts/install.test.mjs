import assert from 'node:assert/strict'
import test from 'node:test'
import ts from 'typescript'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'

async function loadInstallExports() {
  const source = await readFile(new URL('../src/lib/install.ts', import.meta.url), 'utf8')
  const transpiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2023 },
  }).outputText
  const body = transpiled.replaceAll('export ', '')
  const context = vm.createContext({})
  vm.runInContext(
    `${body}; globalThis.installExports = { INSTALL_IIMOD_COMMAND, installCommand }`,
    context,
  )
  return context.installExports
}

test('CLI install command presents each safe installation stage in order', async () => {
  const { INSTALL_IIMOD_COMMAND } = await loadInstallExports()
  const stages = [
    'Downloading iimod',
    'curl ',
    'Installing iimod to /usr/local/bin/iimod',
    'sudo install ',
    'iimod --version',
    'Installation complete',
    'Next:',
  ]

  let previousIndex = -1
  for (const stage of stages) {
    const stageIndex = INSTALL_IIMOD_COMMAND.indexOf(stage)
    assert.ok(stageIndex > previousIndex, `${stage} must appear after the previous stage`)
    previousIndex = stageIndex
  }

  assert.doesNotMatch(INSTALL_IIMOD_COMMAND, /[\r\n]/)
  assert.match(INSTALL_IIMOD_COMMAND, /curl .*--fail.*--location.*--progress-bar/)
  assert.match(INSTALL_IIMOD_COMMAND, /\$\(mktemp\)/)
  assert.match(INSTALL_IIMOD_COMMAND, /sudo install .* \/usr\/local\/bin\/iimod/)
  assert.doesNotMatch(INSTALL_IIMOD_COMMAND, /curl[^&|]*\|\s*sudo/)
  assert.ok(
    INSTALL_IIMOD_COMMAND.split(' && ').length >= stages.length,
    'stages must retain fail-fast && chaining',
  )
})

test('Hero uses the shared CLI install command', async () => {
  const source = await readFile(new URL('../src/components/hero.tsx', import.meta.url), 'utf8')

  assert.match(source, /import \{ INSTALL_IIMOD_COMMAND, installCommand \} from '@\/lib\/install'/)
  assert.doesNotMatch(source, /releases\/latest\/download\/iimod-linux-x86_64/)
})

test('installCommand adds patch consent only for Tier B modules', async () => {
  const { installCommand } = await loadInstallExports()
  assert.equal(installCommand('https://example.test/a.iimod', false), 'iimod install https://example.test/a.iimod')
  assert.equal(
    installCommand('https://example.test/b.iimod', true),
    'iimod install https://example.test/b.iimod --allow-patches',
  )
})
