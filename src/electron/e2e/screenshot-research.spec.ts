import { test } from '@playwright/test'

test('screenshot research screen', async ({ page }) => {
  await page.goto('/')
  await page.waitForSelector('#root', { state: 'attached' })
  await page.waitForTimeout(1500)

  // Click Research tab
  const researchTab = page.locator('button:has-text("Research")').first()
  if (await researchTab.isVisible()) {
    await researchTab.click()
    await page.waitForTimeout(1000)
  }

  await page.screenshot({
    path: './e2e/screenshots/research-screen.png',
    fullPage: true,
  })
})
