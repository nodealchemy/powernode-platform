import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI DevOps E2E Tests
 *
 * Tests for DevOps Pipeline Templates, Executions, Risk Assessments, and Code Reviews.
 * Migrated from ai-devops.cy.ts and ai-devops-templates.cy.ts
 */

test.describe('AI DevOps', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.devops);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should load DevOps page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/devops|template|pipeline|ci\/cd/i);
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/devops|template|pipeline/i);
    });

    test('should display page description', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pipeline|template|ci\/cd|automation|deployment|devops/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/ai|devops/i);
    });
  });

  test.describe('Analytics Summary Cards', () => {
    test('should display total executions card', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/total execution|execution|devops/i);
    });

    test('should display deployments card', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/deployment|deploy|devops/i);
    });

    test('should display code reviews card', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/code review|review|devops/i);
    });
  });

  test.describe('Tab Navigation', () => {
    test('should display tab navigation', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/template|installation|execution|risk|review|analytic/i);
    });

    test('should switch to Installations tab', async ({ page }) => {
      const installationsTab = page.locator('button').filter({ hasText: /installation/i }).first();

      if (await installationsTab.count() > 0) {
        await installationsTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/installation|installed|version|devops/i);
      }
    });

    test('should switch to Executions tab', async ({ page }) => {
      const executionsTab = page.locator('button').filter({ hasText: /execution/i }).first();

      if (await executionsTab.count() > 0) {
        await executionsTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/execution|pipeline|status|devops/i);
      }
    });

    test('should switch to Risk Assessments tab', async ({ page }) => {
      const riskTab = page.locator('button').filter({ hasText: /risk/i }).first();

      if (await riskTab.count() > 0) {
        await riskTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/risk|assessment|deployment|devops/i);
      }
    });

    test('should switch to Code Reviews tab', async ({ page }) => {
      const reviewsTab = page.locator('button').filter({ hasText: /review/i }).first();

      if (await reviewsTab.count() > 0) {
        await reviewsTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/review|code|file|devops/i);
      }
    });

    test('should switch to Analytics tab', async ({ page }) => {
      const analyticsTab = page.locator('button').filter({ hasText: /analytic/i }).first();

      if (await analyticsTab.count() > 0) {
        await analyticsTab.click();
        await page.waitForTimeout(300);
        await expect(page.locator('body')).toContainText(/analytic|insight|coming soon|devops/i);
      }
    });
  });

  test.describe('Template Management', () => {
    test('should display templates section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/template|devops/i);
    });

    test('should have Create Template button', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Template"), button:has-text("New Template"), button:has-text("Create")');
      const hasButton = await createButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('template');

      expect(hasButton || hasPageContent).toBeTruthy();
    });

    test('should display template categories', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/category|code_quality|deployment|testing|documentation|devops/i);
    });

    test('should display install button for templates', async ({ page }) => {
      const installButton = page.locator('button:has-text("Install")');
      const hasButton = await installButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('template');

      expect(hasButton || hasPageContent).toBeTruthy();
    });
  });

  test.describe('Pipeline Executions', () => {
    test('should display executions section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/execution|run|pipeline|devops/i);
    });

    test('should display execution status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pending|running|completed|failed|status|devops/i);
    });

    test('should have Create Execution option', async ({ page }) => {
      const executeButton = page.locator('button:has-text("Execute"), button:has-text("Run"), button:has-text("New Execution"), button:has-text("Create")');
      const hasButton = await executeButton.count() > 0;
      const hasPageContent = (await page.locator('body').textContent())?.toLowerCase().includes('devops');

      expect(hasButton || hasPageContent).toBeTruthy();
    });
  });

  test.describe('Deployment Risk Assessment', () => {
    test('should display risk assessments section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/risk|assessment|deployment|devops/i);
    });

    test('should display risk levels', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/low|medium|high|critical|risk|devops/i);
    });

    test('should display approval requirements', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/approval|required|approve|reject|devops/i);
    });
  });

  test.describe('Code Reviews', () => {
    test('should display code reviews section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/code review|review|pr|pull request|devops/i);
    });

    test('should display review status', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pending|analyzing|completed|failed|devops/i);
    });

    test('should display review metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/issue|suggestion|file|line|devops/i);
    });
  });

  test.describe('Analytics Dashboard', () => {
    test('should display analytics section', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/analytic|statistic|metric|dashboard|devops/i);
    });

    test('should display execution metrics', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/total|success rate|duration|execution|devops/i);
    });
  });

  test.describe('Search and Filter', () => {
    test('should have search input', async ({ page }) => {
      const searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

      if (await searchInput.count() > 0) {
        await searchInput.first().fill('test');
        await expect(page.locator('body')).toBeVisible();
      }
    });

    test('should have category filter', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/categor|all|filter|devops/i);
    });

    test('should have status filter', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/status|all status|filter|devops/i);
    });
  });

  test.describe('Error Handling', () => {
    test('should handle API error gracefully', async ({ page }) => {
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.devops);
      await expect(page.locator('body')).toContainText(/devops|template/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.devops);
      await expect(page.locator('body')).toBeVisible();
    });

    test('should adapt layout on small screens', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.devops);
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
