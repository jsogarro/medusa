import { test } from '@playwright/test'

test('diagnose blank page', async ({ page }) => {
  const errors: string[] = []
  const pageErrors: string[] = []

  page.on('console', msg => {
    errors.push(`[${msg.type()}] ${msg.text()}`)
  })
  page.on('pageerror', err => {
    pageErrors.push(err.message)
  })

  await page.goto('http://localhost:5175/')
  await page.waitForTimeout(3000)

  const rootHTML = await page.evaluate(() => document.getElementById('root')?.innerHTML || 'EMPTY')

  console.log('\n=== ROOT HTML ===')
  console.log(rootHTML.substring(0, 500))
  console.log('\n=== PAGE ERRORS ===')
  pageErrors.forEach(e => console.log(e))
  console.log('\n=== CONSOLE MESSAGES ===')
  errors.forEach(e => console.log(e))
})
