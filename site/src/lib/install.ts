export const INSTALL_IIMOD_COMMAND =
  "curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 https://ii.n1cat.xyz/install-iimod.sh | sh"

export function installCommand(url: string, tierB: boolean): string {
  return `iimod install ${url}${tierB ? ' --allow-patches' : ''}`
}
