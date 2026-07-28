export const INSTALL_IIMOD_COMMAND =
  'sh -c "$(curl -sS https://ii.n1cat.xyz/install-iimod.sh)"'

export function installCommand(url: string, tierB: boolean): string {
  return `iimod install ${url}${tierB ? ' --allow-patches' : ''}`
}
