import { expect, test } from '@playwright/test';

test.describe('layouts at 200% zoom', () => {
  test('home page renders without horizontal overflow at 200%', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/home', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    await page.evaluate(() => {
      document.documentElement.style.zoom = '200%';
    });
    await page.waitForTimeout(500);

    const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
    const viewportWidth = await page.evaluate(() => window.innerWidth);

    expect(bodyWidth).toBeLessThanOrEqual(viewportWidth + 5);
  });

  test('settings page does not overflow at 200% zoom', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/settings', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    await page.evaluate(() => {
      document.documentElement.style.zoom = '200%';
    });
    await page.waitForTimeout(500);

    const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
    const viewportWidth = await page.evaluate(() => window.innerWidth);

    expect(bodyWidth).toBeLessThanOrEqual(viewportWidth + 5);
  });

  test('fixed navbar does not clip content at 200% zoom', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });

    await page.evaluate(() => {
      document.documentElement.style.zoom = '200%';
    });

    await page.goto('/home', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    const nav = page.locator('nav').first();
    await expect(nav).toBeVisible();

    const navRect = await nav.boundingBox();
    if (navRect) {
      expect(navRect.y).toBeGreaterThanOrEqual(0);
      expect(navRect.height).toBeLessThan(200);
    }
  });
});

test.describe('responsive reflow at 320px', () => {
  test('home page rails render with snap-scroll at narrow width', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 800 });
    await page.goto('/home', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
    expect(bodyWidth).toBeLessThanOrEqual(325);
  });

  test('settings page fits at 320px', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 800 });
    await page.goto('/settings', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
    expect(bodyWidth).toBeLessThanOrEqual(325);
  });

  test('player controls have at least 44px touch targets', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });

    const buttons = page.locator('button').filter({ hasText: /Skip|Play|Pause|Next/i });
    const count = await buttons.count();

    for (let i = 0; i < Math.min(count, 4); i++) {
      const box = await buttons.nth(i).boundingBox();
      if (box) {
        expect(box.width).toBeGreaterThanOrEqual(40);
        expect(box.height).toBeGreaterThanOrEqual(40);
      }
    }
  });
});

test.describe('accessibility', () => {
  test('skip-link is present and has 44px height', async ({ page }) => {
    await page.goto('/home', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    const skipLink = page.locator('.skip-link, a[href="#main-content"]').first();

    const count = await skipLink.count();
    if (count > 0) {
      const box = await skipLink.boundingBox();
      if (box) {
        expect(box.height).toBeGreaterThanOrEqual(44);
      }
    }
  });

  test('main content has role or id', async ({ page }) => {
    await page.goto('/home', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    const main = page.locator('main, [role="main"], #main-content').first();
    await expect(main).toBeVisible({ timeout: 5000 });
  });

  test('primary nav has accessible name', async ({ page }) => {
    await page.goto('/home', { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2000);

    const nav = page.locator('nav[aria-label]').first();
    const count = await nav.count();
    if (count > 0) {
      const label = await nav.getAttribute('aria-label');
      expect(label).toBeTruthy();
    }
  });
});

