const IIMOD_RELEASE_URL = 'https://ii.n1cat.xyz/downloads/iimod/linux-x86_64'
const IIMOD_CHECKSUM_URL = `${IIMOD_RELEASE_URL}.sha256`

const installSteps = [
  'set -eu',
  'iimod_tmp="$(mktemp)"',
  'iimod_sum_tmp="$(mktemp)"',
  'trap \'rm -f "$iimod_tmp" "$iimod_sum_tmp"\' EXIT HUP INT TERM',
  "printf '%s\\n' 'Downloading iimod and checksum...'",
  `curl --fail --location --progress-bar --output "$iimod_tmp" ${IIMOD_RELEASE_URL}`,
  `curl --fail --location --progress-bar --output "$iimod_sum_tmp" ${IIMOD_CHECKSUM_URL}`,
  'iimod_sha="$(cat "$iimod_sum_tmp")"',
  'printf \'%s\\n\' "$iimod_sha" | grep --extended-regexp --quiet \'^[0-9a-fA-F]{64}$\'',
  '(cd "$(dirname "$iimod_tmp")" && printf \'%s  %s\\n\' "$iimod_sha" "$(basename "$iimod_tmp")" | sha256sum --check --status -)',
  "printf '%s\\n' 'Checksum verified.'",
  "printf '%s\\n' 'Installing iimod to /usr/local/bin/iimod (sudo may prompt for your password)...'",
  'sudo install -m 0755 "$iimod_tmp" /usr/local/bin/iimod',
  'iimod --version',
  "printf '%s\\n' 'Installation complete. Next: choose a module below and run its install command.'",
].join(' && ')

export const INSTALL_IIMOD_COMMAND = `sh -c '${installSteps.replaceAll("'", "'\\''")}'`

export function installCommand(url: string, tierB: boolean): string {
  return `iimod install ${url}${tierB ? ' --allow-patches' : ''}`
}
