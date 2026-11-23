import { test, expect } from '@playwright/test'

const SCREENSHOT_DIR = './e2e/screenshots'

test.describe('New Screens — Volume Analysis & Settings', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('#root', { state: 'attached' })
    await page.waitForTimeout(1000)
  })

  test('21 — Volume Analysis screen renders', async ({ page }) => {
    // Click Volume tab
    const volumeTab = page.getByRole('button', { name: 'Volume' })
    await volumeTab.click()
    await page.waitForTimeout(500)

    // Wait for volume components to render
    await page.waitForSelector('text=VOLUME PROFILE', { timeout: 5000 })
    await page.waitForSelector('text=VWAP & BANDS', { timeout: 5000 })
    await page.waitForSelector('text=VOLUME SPIKE DETECTOR', { timeout: 5000 })
    await page.waitForSelector('text=CUMULATIVE VOLUME DELTA', { timeout: 5000 })
    await page.waitForSelector('text=ORDER FLOW IMBALANCE', { timeout: 5000 })

    // Take screenshot
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/volume-analysis.png`,
      fullPage: true
    })

    // Verify volume spike table has data
    const spikes = await page.locator('table tbody tr').count()
    expect(spikes).toBeGreaterThan(0)
  })

  test('22 — Settings screen renders all sections', async ({ page }) => {
    // Click Settings tab
    const settingsTab = page.getByRole('button', { name: 'Settings' })
    await settingsTab.click()
    await page.waitForTimeout(500)

    // Wait for default section (connections) to render
    await page.waitForSelector('text=Connection Settings', { timeout: 5000 })

    // Take screenshot of connections section
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/settings-connections.png`,
      fullPage: true
    })

    // Test Exchange Configuration section
    await page.click('button:has-text("Exchange Configuration")')
    await page.waitForTimeout(300)
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/settings-exchanges.png`,
      fullPage: true
    })

    // Test Risk Limits section
    await page.click('button:has-text("Risk Limits")')
    await page.waitForTimeout(300)
    await page.waitForSelector('text=Max Position Size per Strategy', { timeout: 5000 })
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/settings-risk.png`,
      fullPage: true
    })

    // Test Display Preferences section
    await page.click('button:has-text("Display Preferences")')
    await page.waitForTimeout(300)
    await page.waitForSelector('text=Default Chart Timeframe', { timeout: 5000 })
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/settings-display.png`,
      fullPage: true
    })

    // Test Paper Trading section
    await page.click('button:has-text("Paper Trading")')
    await page.waitForTimeout(300)
    await page.waitForSelector('text=Current Mode', { timeout: 5000 })
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/settings-paper.png`,
      fullPage: true
    })

    // Verify paper mode indicator
    const paperIndicator = await page.locator('text=PAPER').count()
    expect(paperIndicator).toBeGreaterThan(0)
  })
})
