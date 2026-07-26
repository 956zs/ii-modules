import { CommandBlock } from '@/components/command-block'
import type { RegistryModule, VersionState } from '@/lib/types'

const INSTALL_IIMOD_COMMAND =
  'curl -fsSL -o iimod https://github.com/956zs/ii-modules/releases/latest/download/iimod-linux-x86_64 && chmod +x iimod && sudo install iimod /usr/local/bin/iimod'

interface HeroProps {
  firstModule?: RegistryModule
  firstModuleVersion?: VersionState
}

export function Hero({ firstModule, firstModuleVersion }: HeroProps) {
  const packageUrl =
    firstModuleVersion?.status === 'success' ? firstModuleVersion.data.url : firstModule?.origin

  return (
    <section className="mx-auto flex max-w-4xl flex-col items-center gap-6 px-6 pt-20 pb-16 text-center">
      <span className="rounded-full border border-border bg-card/60 px-3 py-1 font-mono text-xs tracking-wide text-muted-foreground uppercase">
        IIMP · illogical-impulse Module Protocol
      </span>
      <h1 className="font-heading text-4xl font-semibold tracking-tight text-balance sm:text-5xl">
        給 illogical-impulse 桌面的
        <br />
        社群模塊協議
      </h1>
      <p className="max-w-2xl text-base text-muted-foreground sm:text-lg">
        IIMP 讓 Quickshell 模塊像套件一樣安裝、更新與分享——每個模塊自帶更新來源，
        清單只負責索引，版本永遠即時。
      </p>
      <div className="mt-4 grid w-full max-w-2xl gap-3 text-left">
        <CommandBlock label="安裝 iimod（來自 GitHub Releases）" command={INSTALL_IIMOD_COMMAND} />
        {packageUrl ? (
          <CommandBlock
            label={firstModule ? `安裝 ${firstModule.name.zh_TW}` : '安裝模塊'}
            command={`iimod install ${packageUrl}`}
          />
        ) : null}
      </div>
    </section>
  )
}
