const IIMOD_RELEASE_URL =
  'https://github.com/956zs/ii-modules/releases/latest/download/iimod-linux-x86_64'

export const INSTALL_IIMOD_COMMAND = [
  'iimod_tmp="$(mktemp)"',
  "printf '%s\\n' 'Downloading iimod...'",
  `curl --fail --location --progress-bar --output "$iimod_tmp" ${IIMOD_RELEASE_URL}`,
  "printf '%s\\n' 'Installing iimod to /usr/local/bin/iimod (sudo may prompt for your password)...'",
  'sudo install -m 0755 "$iimod_tmp" /usr/local/bin/iimod',
  'rm -f "$iimod_tmp"',
  'iimod --version',
  "printf '%s\\n' 'Installation complete. Next: choose a module below and run its install command.'",
].join(' && ')

export function installCommand(url: string, tierB: boolean): string {
  return `iimod install ${url}${tierB ? ' --allow-patches' : ''}`
}
