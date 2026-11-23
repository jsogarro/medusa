import { test, expect } from '@playwright/test'

test.describe('Tearsheet Screenshots', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('http://localhost:5175')
    await page.waitForLoadState('networkidle')
    // Click P&L tab
    await page.click('text=P&L')
    await page.waitForTimeout(500)
  })

  test('01 — Returns tab screenshot', async ({ page }) => {
    await page.click('[role="tab"]:has-text("Returns")')
    await page.waitForTimeout(1000)
    await page.screenshot({ path: 'screenshots/tearsheet-returns.png', fullPage: true })
  })

  test('02 — Drawdowns tab screenshot', async ({ page }) => {
    await page.click('[role="tab"]:has-text("Drawdowns")')
    await page.waitForTimeout(1000)
    await page.screenshot({ path: 'screenshots/tearsheet-drawdowns.png', fullPage: true })
  })

  test('03 — Metrics tab screenshot', async ({ page }) => {
    await page.click('[role="tab"]:has-text("Metrics")')
    await page.waitForTimeout(1000)
    await page.screenshot({ path: 'screenshots/tearsheet-metrics.png', fullPage: true })
  })

  test('04 — Rolling tab screenshot', async ({ page }) => {
    await page.click('[role="tab"]:has-text("Rolling")')
    await page.waitForTimeout(1000)
    await page.screenshot({ path: 'screenshots/tearsheet-rolling.png', fullPage: true })
  })

  test('05 — Exposure tab screenshot', async ({ page }) => {
    await page.click('[role="tab"]:has-text("Exposure")')
    await page.waitForTimeout(1000)
    await page.screenshot({ path: 'screenshots/tearsheet-exposure.png', fullPage: true })
  })

  test('06 — Round Trips tab screenshot', async ({ page }) => {
    await page.click('[role="tab"]:has-text("Round Trips")')
    await page.waitForTimeout(1000)
    await page.screenshot({ path: 'screenshots/tearsheet-roundtrips.png', fullPage: true })
  })
})
