import { app } from 'electron'
import { join } from 'path'
import { pathToFileURL } from 'url'

export const DEV_SERVER_URL = 'http://localhost:5173'

/** The one renderer page the packaged app loads (windows and the sender check both use this path). */
export const RENDERER_FILE = join(__dirname, '../renderer/index.html')
const RENDERER_PATHNAME = pathToFileURL(RENDERER_FILE).pathname

export function isDevMode(): boolean {
  return !app.isPackaged && process.env.NODE_ENV === 'development'
}

/** True only for the app's own renderer: the dev server in development, the bundled index.html when packaged. */
export function isTrustedUrl(
  url: string | undefined | null,
  dev: boolean = isDevMode(),
  rendererPathname: string = RENDERER_PATHNAME
): boolean {
  if (!url) return false
  try {
    const u = new URL(url)
    if (dev) return u.origin === DEV_SERVER_URL
    return u.protocol === 'file:' && u.host === '' && u.pathname === rendererPathname
  } catch {
    return false
  }
}

export function isTrustedSender(event: { senderFrame?: { url: string } | null }): boolean {
  return isTrustedUrl(event.senderFrame?.url)
}
