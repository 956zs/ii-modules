import assert from 'node:assert/strict'
import test from 'node:test'
import ts from 'typescript'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'

async function loadInstallCommand() {
  const source = await readFile(new URL('../src/lib/install.ts', import.meta.url), 'utf8')
  const transpiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2023 },
  }).outputText
  const body = transpiled.replace('export function', 'function')
  const context = vm.createContext({})
  vm.runInContext(`${body}; globalThis.installCommand = installCommand`, context)
  return context.installCommand
}

test('installCommand adds patch consent only for Tier B modules', async () => {
  const installCommand = await loadInstallCommand()
  assert.equal(installCommand('https://example.test/a.iimod', false), 'iimod install https://example.test/a.iimod')
  assert.equal(
    installCommand('https://example.test/b.iimod', true),
    'iimod install https://example.test/b.iimod --allow-patches',
  )
})
