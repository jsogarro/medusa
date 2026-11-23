import { KdbApi, PopOutApi, SymbolLinkApi } from '../main/preload'

declare global {
  interface Window {
    kdb: KdbApi
    popOutWidget: (widgetId: string, config: any) => Promise<void>
    symbolLink: SymbolLinkApi
  }
}

export {}
