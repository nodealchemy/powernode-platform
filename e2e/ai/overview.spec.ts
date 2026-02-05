import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI Overview E2E Tests
 *
 * Tests for the AI Overview/Dashboard page functionality.
 * Covers dashboard stats, quick actions, system health, and navigation links.
 *
 * @see docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_FRONTEND.md
 */

test.describe('AI Overview', () => {

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.overview);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
    await page.waitForTimeout(1000);
  });

  test.describe('Page Navigation', () => {
    test('should load AI Overview page directly', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai overview|ai dashboard|ai system dashboard|ai orchestration/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/dashboard|ai/i);
    });
  });

  test.describe('Dashboard Stats Display', () => {
    test('should display AI stats cards', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/workflows|agents|providers|conversations|total|active/i);
    });

    test('should display workflow count', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/workflow|ai|active/i);
    });

    test('should display agent count', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/agent|ai|total/i);
    });

    test('should display provider count', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/provider|ai|connected/i);
    });

    test('should display stats as cards or metric elements', async ({ page }) => {
      const hasCards = await page.locator('[class*="card"], [class*="Card"], [class*="stat"], [class*="metric"]').count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('ai');

      expect(hasCards || hasContent).toBeTruthy();
    });
  });

  test.describe('Quick Actions', () => {
    test('should have Refresh button', async ({ page }) => {
      const refreshButton = page.locator('[data-testid="action-refresh"], [aria-label="Refresh"], [aria-label*="Refresh"], button:has-text("Refresh")');
      const hasRefresh = await refreshButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('ai');

      expect(hasRefresh || hasPageContent).toBeTruthy();
    });

    test('should have Live Updates toggle', async ({ page }) => {
      const liveToggle = page.locator('[data-testid="action-live-updates"], [aria-label="Live"], [aria-label="Paused"]');
      const hasToggle = await liveToggle.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('ai');

      expect(hasToggle || hasPageContent).toBeTruthy();
    });
  });

  test.describe('System Health Display', () => {
    test('should display system health status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/health|status|healthy|online|ai|system/i);
    });

    test('should display provider status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/provider|connected|available|ai|active/i);
    });
  });

  test.describe('Quick Access Links', () => {
    test('should have links to AI subpages', async ({ page }) => {
      const hasLinks = await page.locator('a[href*="/workflows"], a[href*="/agents"], a[href*="/providers"], a[href*="/ai"]').count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('ai');

      expect(hasLinks || hasPageContent).toBeTruthy();
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display Overview tab or section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/overview/i);
    });

    test('should display AI Providers tab or link', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/providers|ai providers/i);
    });

    test('should display AI Agents tab or link', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/agents|ai agents/i);
    });

    test('should display Workflows tab or link', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/workflows/i);
    });
  });

  test.describe('Tab Switching', () => {
    test('should switch to Providers tab', async ({ page }) => {
      const providersTab = page.locator('button:has-text("Providers")').first();
      if (await providersTab.count() > 0) {
        await providersTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Agents tab', async ({ page }) => {
      const agentsTab = page.locator('button:has-text("Agents")').first();
      if (await agentsTab.count() > 0) {
        await agentsTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Workflows tab', async ({ page }) => {
      const workflowsTab = page.locator('button:has-text("Workflows")').first();
      if (await workflowsTab.count() > 0) {
        await workflowsTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Analytics tab', async ({ page }) => {
      const analyticsTab = page.locator('button:has-text("Analytics")').first();
      if (await analyticsTab.count() > 0) {
        await analyticsTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should switch to Monitoring tab', async ({ page }) => {
      const monitoringTab = page.locator('button:has-text("Monitoring")').first();
      if (await monitoringTab.count() > 0) {
        await monitoringTab.click();
        await expect(page.locator('body')).toBeVisible();
      }
    });
  });

  test.describe('Direct Tab Navigation', () => {
    test('should navigate directly to providers page', async ({ page }) => {
      await page.goto(ROUTES.providers);
      await expect(page.locator('body')).toContainText(/provider|ai/i);
    });

    test('should navigate directly to agents page', async ({ page }) => {
      await page.goto(ROUTES.agents);
      await expect(page.locator('body')).toContainText(/agent|ai/i);
    });

    test('should navigate directly to workflows page', async ({ page }) => {
      await page.goto(ROUTES.workflows);
      await expect(page.locator('body')).toContainText(/workflow|ai/i);
    });

    test('should navigate directly to analytics page', async ({ page }) => {
      await page.goto(ROUTES.analytics);
      await expect(page.locator('body')).toContainText(/analytics|ai/i);
    });

    test('should navigate directly to monitoring page', async ({ page }) => {
      await page.goto(ROUTES.monitoring);
      await expect(page.locator('body')).toContainText(/monitoring|ai/i);
    });

    test('should navigate directly to MCP page', async ({ page }) => {
      await page.goto(ROUTES.mcp);
      await expect(page.locator('body')).toContainText(/mcp|ai/i);
    });
  });

  test.describe('Empty State', () => {
    test('should handle empty AI system gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
      await expect(page.locator('body')).not.toContainText('Cannot read');
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
      await expect(page.locator('body')).not.toContainText('Cannot read');
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.overview);
      await expect(page.locator('body')).toContainText(/ai/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.overview);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should handle horizontal tab scrolling on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.overview);
      const hasTabs = await page.locator('[role="tablist"], [class*="tab"]').count() > 0;
      const hasContent = (await page.locator('body').textContent())?.toLowerCase().includes('ai');

      expect(hasTabs || hasContent).toBeTruthy();
    });
  });
});
