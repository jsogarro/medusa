import { existsSync } from 'node:fs'
import path from 'node:path'
import { test, expect, type Page } from '@playwright/test'

const DEV_SERVER_URL = 'http://localhost:5175/'
const BUILT_RENDERER_DIR = path.resolve(__dirname, '../out/renderer')
const BUILT_RENDERER_INDEX = path.join(BUILT_RENDERER_DIR, 'index.html')
const STATIC_FALLBACK_PAGES = new WeakSet<Page>()
let appSource: 'dev-server' | 'built-renderer' | undefined

function assertBuiltRendererExists() {
  if (!existsSync(BUILT_RENDERER_INDEX)) {
    throw new Error(
      `Renderer build not found at ${BUILT_RENDERER_INDEX}. Run npm run build or start ${DEV_SERVER_URL}.`
    )
  }
}

function contentTypeFor(filePath: string) {
  const ext = path.extname(filePath)
  const contentTypes: Record<string, string> = {
    '.css': 'text/css',
    '.html': 'text/html',
    '.js': 'text/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.svg': 'image/svg+xml'
  }

  return contentTypes[ext] || 'application/octet-stream'
}

async function installBuiltRendererFallback(page: Page) {
  if (STATIC_FALLBACK_PAGES.has(page)) return

  assertBuiltRendererExists()
  STATIC_FALLBACK_PAGES.add(page)

  await page.route(`${DEV_SERVER_URL}**`, async (route) => {
    const url = new URL(route.request().url())
    const pathname = decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname)
    const filePath = path.resolve(BUILT_RENDERER_DIR, `.${pathname}`)
    const relativePath = path.relative(BUILT_RENDERER_DIR, filePath)

    if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
      await route.abort()
      return
    }

    if (!existsSync(filePath)) {
      await route.fulfill({ status: 404, body: 'Not found' })
      return
    }

    await route.fulfill({
      path: filePath,
      contentType: contentTypeFor(filePath)
    })
  })
}

async function resolveAppUrl(page: Page) {
  if (appSource === 'dev-server') return DEV_SERVER_URL
  if (appSource === 'built-renderer') {
    await installBuiltRendererFallback(page)
    return DEV_SERVER_URL
  }

  try {
    const response = await page.request.get(DEV_SERVER_URL, { timeout: 1000 })
    if (response.ok()) {
      appSource = 'dev-server'
      return DEV_SERVER_URL
    }
  } catch {
    // Local socket binding is unavailable in some sandboxes; route built assets instead.
  }

  appSource = 'built-renderer'
  await installBuiltRendererFallback(page)
  return DEV_SERVER_URL
}

async function openTradingWorkspace(page: Page) {
  await page.goto(await resolveAppUrl(page))
  await page.waitForSelector('#root', { state: 'attached' })
  await page.waitForSelector('body:not(:empty)', { timeout: 5000 })
  await page.getByRole('button', { name: 'Trading' }).click()
  await expect(page.getByText('Trade Ticket').first()).toBeVisible()
}

test.describe('Alpaca asset switcher', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(await resolveAppUrl(page))
    await page.evaluate(() => localStorage.clear())
  })

  test('switches asset classes, gates options orders, and persists context', async ({ page }) => {
    await openTradingWorkspace(page)

    const ticket = page.locator('form').filter({ hasText: 'Asset Class' }).first()

    await ticket.getByRole('button', { name: 'Options asset class' }).click()
    await expect(ticket.getByLabel('Exchange')).toHaveValue('alpaca')
    await expect(ticket.getByRole('textbox', { name: 'Contract' })).toHaveValue(
      'AAPL250117C00150000'
    )
    await expect(ticket.getByRole('button', { name: 'Market' })).toBeDisabled()
    await expect(ticket.getByText('Alpaca Options')).toBeVisible()

    const optionContext = await page.evaluate(() => {
      return JSON.parse(localStorage.getItem('medusa-trading-asset-context') || '{}')
    })
    expect(optionContext).toMatchObject({
      assetClass: 'option',
      symbol: 'AAPL250117C00150000',
      exchange: 'alpaca'
    })

    await ticket.getByRole('button', { name: 'Equity asset class' }).click()
    await expect(ticket.getByLabel('Symbol')).toHaveValue('AAPL')
    await expect(ticket.getByRole('button', { name: 'Market' })).toBeEnabled()
    await expect(ticket.getByText('Alpaca Paper')).toBeVisible()

    await ticket.getByRole('button', { name: 'Crypto asset class' }).click()
    await expect(ticket.getByLabel('Pair')).toHaveValue('BTCUSD')
    await expect(ticket.getByLabel('Exchange')).toHaveValue('bitstamp')

    await ticket.getByRole('button', { name: 'Options asset class' }).click()
    await page.reload()
    await openTradingWorkspace(page)

    const persistedTicket = page.locator('form').filter({ hasText: 'Asset Class' }).first()
    await expect(
      persistedTicket.getByRole('button', { name: 'Options asset class' })
    ).toHaveAttribute('aria-pressed', 'true')
    await expect(persistedTicket.getByRole('textbox', { name: 'Contract' })).toHaveValue(
      'AAPL250117C00150000'
    )
  })
})
