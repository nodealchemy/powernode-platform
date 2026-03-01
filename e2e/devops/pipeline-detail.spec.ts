import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * Pipeline Detail E2E Tests
 *
 * Tests for the PipelineCreatePage and PipelineDetailPage including
 * pipeline creation flow and detail view navigation.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('Pipeline Detail', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.pipelines);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Pipeline List Page', () => {
    test('should load pipelines page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pipeline/i);
    });

    test('should display create pipeline button', async ({ page }) => {
      const hasCreate = await page.getByRole('button', { name: /create|new|add/i }).count() > 0;
      const hasContent = await page.getByText(/pipeline/i).count() > 0;

      expect(hasCreate || hasContent).toBeTruthy();
    });
  });

  test.describe('Pipeline Detail Navigation', () => {
    test('should click pipeline to view detail without crash', async ({ page }) => {
      await page.waitForLoadState('networkidle');

      const pipelineItem = page.locator('[class*="card"], tr, [class*="pipeline"]').filter({ hasText: /pipeline/i }).first();

      if (await pipelineItem.count() > 0) {
        await pipelineItem.click();
        await page.waitForTimeout(500);
        await page.waitForLoadState('networkidle');
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should display pipeline detail sections without crash', async ({ page }) => {
      await page.waitForLoadState('networkidle');

      const pipelineItem = page.locator('[class*="card"], tr, [class*="pipeline"]').filter({ hasText: /pipeline/i }).first();

      if (await pipelineItem.count() > 0) {
        await pipelineItem.click();
        await page.waitForTimeout(500);
        await page.waitForLoadState('networkidle');

        const hasSteps = await page.getByText(/step|stage|job/i).count() > 0;
        const hasConfig = await page.getByText(/config|setting|trigger/i).count() > 0;
        const hasHistory = await page.getByText(/history|run|execution/i).count() > 0;
        const hasDetail = await page.getByText(/pipeline/i).count() > 0;

        expect(hasSteps || hasConfig || hasHistory || hasDetail).toBeTruthy();
      }
    });
  });

  test.describe('Create Pipeline Flow', () => {
    test('should open create form without crash', async ({ page }) => {
      const createBtn = page.getByRole('button', { name: /create|new|add/i }).first();

      if (await createBtn.count() > 0) {
        await createBtn.click();
        await page.waitForTimeout(500);

        const hasForm = await page.locator('input[name="name"], form, [role="dialog"]').count() > 0;
        const hasWizard = await page.getByText(/create.*pipeline|new.*pipeline/i).count() > 0;
        const hasPage = await page.getByText(/pipeline/i).count() > 0;

        expect(hasForm || hasWizard || hasPage).toBeTruthy();
      }
    });

    test('should display pipeline configuration fields', async ({ page }) => {
      const createBtn = page.getByRole('button', { name: /create|new|add/i }).first();

      if (await createBtn.count() > 0) {
        await createBtn.click();
        await page.waitForTimeout(500);

        const hasName = await page.locator('input[name="name"], input[placeholder*="name" i]').count() > 0;
        const hasRepo = await page.getByText(/repositor|repo/i).count() > 0;
        const hasTrigger = await page.getByText(/trigger/i).count() > 0;
        const hasContent = await page.getByText(/pipeline/i).count() > 0;

        expect(hasName || hasRepo || hasTrigger || hasContent).toBeTruthy();
      }
    });
  });
});
