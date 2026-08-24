#!/usr/bin/env node
// Drift checker for vendored ConfigLoader.qml copies.
//
// Copies are not required to be byte-identical to lib/ConfigLoader.template.qml
// (module schemas differ), but every copy must keep the skeleton invariants
// below. Intentional deviations are declared in allowlist.json per module and
// rule, with a reason.

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const modulesDir = join(repoRoot, "modules");
const allowlistPath = join(dirname(fileURLToPath(import.meta.url)), "allowlist.json");
const allowlist = existsSync(allowlistPath)
  ? JSON.parse(readFileSync(allowlistPath, "utf8"))
  : {};

function stripComments(text) {
  // Good enough for QML lint: drops /* */ blocks and // line tails. String
  // literals containing comment markers are not expected in these files.
  return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}

function extractAdapterBlock(text) {
  const start = text.search(/adapter:\s*JsonAdapter\s*\{/);
  if (start === -1) return null;
  let i = text.indexOf("{", start);
  let depth = 0;
  for (; i < text.length; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth === 0) break;
  }
  return text.slice(start, i + 1);
}

const RULES = {
  "watch-changes": (t) => /\bwatchChanges:\s*true\b/.test(t),
  "block-writes": (t) => /\bblockWrites:\s*true\b/.test(t),
  "atomic-writes": (t) => /\batomicWrites:\s*true\b/.test(t),
  "materializing-guard": (t) => /\bmaterializing\b/.test(t) || /\binternalReload\b/.test(t),
  "ready-flag": (t) => /\bproperty\s+bool\s+ready\b/.test(t),
  "load-failed-file-not-found": (t) =>
    /\bonLoadFailed\b/.test(t) && /FileViewError\.FileNotFound/.test(t),
  "config-path": (t, id) =>
    new RegExp(
      `path:\\s*Directories\\.shellConfig\\s*\\+\\s*"/modules/${id}\\.json"`,
    ).test(t),
  "no-var-in-adapter": (t) => {
    const block = extractAdapterBlock(t);
    if (block === null) return true; // no adapter block; nothing to segfault
    return !/\bproperty\s+var\b/.test(block);
  },
};

let failures = 0;
let checked = 0;

for (const id of readdirSync(modulesDir).sort()) {
  const file = join(modulesDir, id, "ConfigLoader.qml");
  if (!existsSync(file)) continue;
  checked++;
  const text = stripComments(readFileSync(file, "utf8"));
  const allowed = allowlist[id] ?? {};
  for (const [rule, check] of Object.entries(RULES)) {
    const ok = check(text, id);
    if (ok) {
      if (allowed[rule]) {
        console.error(
          `STALE ALLOWLIST ${id}/${rule}: rule passes; remove the entry`,
        );
        failures++;
      }
      continue;
    }
    if (allowed[rule]) {
      console.log(`allowed  ${id}/${rule}: ${allowed[rule]}`);
      continue;
    }
    console.error(`FAIL     ${id}/${rule}`);
    failures++;
  }
}

for (const id of Object.keys(allowlist)) {
  if (!existsSync(join(modulesDir, id, "ConfigLoader.qml"))) {
    console.error(`STALE ALLOWLIST ${id}: module or ConfigLoader.qml missing`);
    failures++;
  }
}

console.log(
  `${checked} ConfigLoader copies checked, ${failures} undeclared deviation(s)`,
);
process.exit(failures === 0 ? 0 : 1);
