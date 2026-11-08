import { app } from 'electron'

export const DEV_SERVER_URL = 'http://localhost:5173'

export function isDevMode(): boolean {
  return !app.isPackaged && process.env.NODE_ENV === 'development'
}

/** True only for the app's own renderer: the dev server in development, the bundled index.html when packaged. */
export function isTrustedUrl(url: string | undefined | null, dev: boolean = isDevMode()): boolean {
  if (!url) return false
  try {
    const u = new URL(url)
    if (dev) return u.origin === DEV_SERVER_URL
    return u.protocol === 'file:' && u.pathname.endsWith('/renderer/index.html')
  } catch {
    return false
  }
}

export function isTrustedSender(event: { senderFrame?: { url: string } | null }): boolean {
  return isTrustedUrl(event.senderFrame?.url)
}
