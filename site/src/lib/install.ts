export function installCommand(url: string, tierB: boolean): string {
  return `iimod install ${url}${tierB ? ' --allow-patches' : ''}`
}
