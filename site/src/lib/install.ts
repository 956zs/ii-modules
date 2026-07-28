export const INSTALL_IIMOD_COMMAND =
  `sh -c 'script=$(curl --fail --location --silent --show-error https://ii.n1cat.xyz/install-iimod.sh) && [ -n "$script" ] && sh -c "$script"'`

export function installCommand(url: string, tierB: boolean): string {
  return `iimod install ${url}${tierB ? ' --allow-patches' : ''}`
}
