import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it, vi } from 'vitest'

vi.mock('electron', () => ({ app: { isPackaged: true } }))

import { pathToFileURL } from 'node:url'
import { isTrustedSender, isTrustedUrl, RENDERER_FILE } from './security'

const OWN_PAGE = pathToFileURL(RENDERER_FILE).href

describe('isTrustedUrl', () => {
  it('packaged: only the bundled renderer page', () => {
    expect(isTrustedUrl(`${OWN_PAGE}?widget=a`, false)).toBe(true)
    // Any other file that merely ends in /renderer/index.html is not the app's page.
    expect(isTrustedUrl('file:///tmp/evil/renderer/index.html', false)).toBe(false)
    expect(isTrustedUrl('file://evil-host/renderer/index.html', false)).toBe(false)
    expect(isTrustedUrl('file:///etc/passwd', false)).toBe(false)
    expect(isTrustedUrl('https://evil.example/renderer/index.html', false)).toBe(false)
    expect(isTrustedUrl('http://localhost:5173/', false)).toBe(false)
  })

  it('dev: only the vite dev server origin', () => {
    expect(isTrustedUrl('http://localhost:5173/?widget=a', true)).toBe(true)
    expect(isTrustedUrl('http://localhost:5174/', true)).toBe(false)
    expect(isTrustedUrl('http://localhost:5173.evil.com/', true)).toBe(false)
  })

  it('rejects empty and malformed input', () => {
    expect(isTrustedUrl('', false)).toBe(false)
    expect(isTrustedUrl(undefined, false)).toBe(false)
    expect(isTrustedUrl('not a url', false)).toBe(false)
  })

  it('isTrustedSender reads the sender frame (app is packaged in this mock)', () => {
    expect(isTrustedSender({ senderFrame: { url: OWN_PAGE } })).toBe(true)
    expect(isTrustedSender({ senderFrame: { url: 'https://evil.example/' } })).toBe(false)
    expect(isTrustedSender({ senderFrame: null })).toBe(false)
  })
})

describe('renderer CSP', () => {
  const csp = readFileSync(join(__dirname, '../renderer/index.html'), 'utf8')
  const directive = (name: string) => new RegExp(`${name}\\s+([^;]+);`).exec(csp)?.[1].trim().split(/\s+/) ?? []

  it('connect-src allows only the dev server, never an arbitrary localhost port', () => {
    expect(directive('connect-src')).toEqual(['self'].map((s) => `'${s}'`).concat(['ws://localhost:5173', 'http://localhost:5173']))
  })
})
