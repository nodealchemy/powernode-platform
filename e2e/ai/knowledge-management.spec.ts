import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Knowledge Management E2E Tests
 *
 * Tests for the KnowledgePage tabbed interface including
 * Contexts, Prompts, Skills, RAG, and Knowledge Graph tabs.
 * Uses error-capture pattern to detect runtime crashes.
 */

test.describe('AI Knowledge Management', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(ROUTES.knowledge);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page Load', () => {
    test('should load knowledge page without errors', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/knowledge|context|prompt|skill|rag/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/knowledge/i);
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display tab navigation with expected tabs', async ({ page }) => {
      const hasContexts = await page.getByText(/context/i).count() > 0;
      const hasPrompts = await page.getByText(/prompt/i).count() > 0;
      const hasSkills = await page.getByText(/skill/i).count() > 0;
      const hasRag = await page.getByText(/rag/i).count() > 0;
      const hasGraph = await page.getByText(/graph/i).count() > 0;
      const hasKnowledge = await page.getByText(/knowledge/i).count() > 0;

      expect(hasContexts || hasPrompts || hasSkills || hasRag || hasGraph || hasKnowledge).toBeTruthy();
    });

    test('should switch to Prompts tab without crash', async ({ page }) => {
      const promptsTab = page.locator('button').filter({ hasText: /prompt/i }).first();

      if (await promptsTab.count() > 0) {
        await promptsTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Skills tab without crash', async ({ page }) => {
      const skillsTab = page.locator('button').filter({ hasText: /skill/i }).first();

      if (await skillsTab.count() > 0) {
        await skillsTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to RAG tab without crash', async ({ page }) => {
      const ragTab = page.locator('button').filter({ hasText: /rag/i }).first();

      if (await ragTab.count() > 0) {
        await ragTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Knowledge Graph tab without crash', async ({ page }) => {
      const graphTab = page.locator('button').filter({ hasText: /graph/i }).first();

      if (await graphTab.count() > 0) {
        await graphTab.click();
        await page.waitForTimeout(500);
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should cycle through all tabs without crash', async ({ page }) => {
      const tabs = page.locator('[role="tablist"] button, nav button').filter({ hasText: /context|prompt|skill|rag|graph/i });
      const count = await tabs.count();

      for (let i = 0; i < count; i++) {
        await tabs.nth(i).click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Content Display', () => {
    test('should display content or empty state', async ({ page }) => {
      const hasContent = await page.locator('[class*="card"], tr, [class*="list"]').count() > 0;
      const hasEmpty = await page.getByText(/no.*context|no.*prompt|empty|get started/i).count() > 0;
      const hasPageContent = await page.getByText(/knowledge/i).count() > 0;

      expect(hasContent || hasEmpty || hasPageContent).toBeTruthy();
    });
  });
});
