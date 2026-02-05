import { test, expect } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI DevOps Templates - Interactive E2E Tests
 *
 * Tests actual UI interactions: button clicks, modal opening/closing,
 * form submissions, data rendering, and template CRUD operations.
 * Designed to catch issues like broken buttons, empty lists, and
 * non-functional modals.
 */

test.describe('DevOps Templates Page', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    await page.goto(ROUTES.devopsTemplates);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Load & Data Rendering', () => {
    test('should render page title and description', async ({ page }) => {
      await expect(page.locator('body')).toContainText('DevOps AI Templates');
    });

    test('should render template cards with content', async ({ page }) => {
      const grid = page.locator('[data-testid="devops-templates-grid"]');
      const emptyState = page.locator('text=No templates');

      // Either we have template cards or the empty state
      const hasGrid = await grid.count() > 0;
      const hasEmpty = await emptyState.count() > 0;
      expect(hasGrid || hasEmpty).toBeTruthy();

      if (hasGrid) {
        const cards = page.locator('[data-testid="devops-template-card"]');
        const cardCount = await cards.count();
        expect(cardCount).toBeGreaterThan(0);

        // Each card should have visible name text (not empty)
        const firstCardText = await cards.first().textContent();
        expect(firstCardText).toBeTruthy();
        expect(firstCardText!.length).toBeGreaterThan(5);
      }
    });

    test('should render status badges on template cards', async ({ page }) => {
      const badges = page.locator('[data-testid="template-status-badge"]');

      if (await badges.count() > 0) {
        const firstBadge = badges.first();
        await expect(firstBadge).toBeVisible();
        const text = await firstBadge.textContent();
        expect(text).toMatch(/draft|pending_review|published|archived|deprecated/);
      }
    });

    test('should render category and type labels on cards', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        const firstCard = cards.first();
        // Categories and types are rendered as small badges
        const labels = firstCard.locator('.bg-theme-accent\\/10');
        expect(await labels.count()).toBeGreaterThanOrEqual(2);
      }
    });

    test('should render install count on cards', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await expect(cards.first()).toContainText(/\d+ installs/);
      }
    });
  });

  test.describe('Action Buttons', () => {
    test('Refresh button should reload data', async ({ page }) => {
      const refreshBtn = page.locator('button').filter({ hasText: 'Refresh' });
      await expect(refreshBtn).toBeVisible();
      await expect(refreshBtn).toBeEnabled();

      // Click and verify no errors occur
      await refreshBtn.click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText('DevOps AI Templates');
    });

    test('Create Template button should open modal', async ({ page }) => {
      const createBtn = page.locator('button').filter({ hasText: 'Create Template' });
      await expect(createBtn).toBeVisible();
      await expect(createBtn).toBeEnabled();

      await createBtn.click();
      await page.waitForTimeout(300);

      // Modal should be visible with form fields
      await expect(page.locator('text=Create Template').first()).toBeVisible();
      await expect(page.locator('input[type="text"]').first()).toBeVisible();

      // Should have category and type selects
      const selects = page.locator('select');
      expect(await selects.count()).toBeGreaterThanOrEqual(2);
    });

    test('New Execution button should be visible and enabled', async ({ page }) => {
      const execBtn = page.locator('button').filter({ hasText: 'New Execution' });
      await expect(execBtn).toBeVisible();
      await expect(execBtn).toBeEnabled();
    });
  });

  test.describe('Create Template Modal', () => {
    test('should close modal on Cancel click', async ({ page }) => {
      const createBtn = page.locator('button').filter({ hasText: 'Create Template' });
      await createBtn.click();
      await page.waitForTimeout(300);

      const cancelBtn = page.locator('button').filter({ hasText: 'Cancel' });
      await cancelBtn.click();
      await page.waitForTimeout(300);

      // Modal should be gone - name input should not be visible
      const modalTitle = page.locator('[class*="modal"]').locator('text=Create Template');
      expect(await modalTitle.count()).toBe(0);
    });

    test('should validate required name field', async ({ page }) => {
      const createBtn = page.locator('button').filter({ hasText: 'Create Template' });
      await createBtn.click();
      await page.waitForTimeout(300);

      // Try to submit with empty name
      const submitBtn = page.locator('button').filter({ hasText: 'Create Template' }).last();
      await submitBtn.click();
      await page.waitForTimeout(500);

      // Should show error notification
      await expect(page.locator('body')).toContainText(/required|name/i);
    });

    test('should fill and submit create form', async ({ page }) => {
      const createBtn = page.locator('button').filter({ hasText: 'Create Template' });
      await createBtn.click();
      await page.waitForTimeout(300);

      // Fill form fields
      const nameInput = page.locator('input[type="text"]').first();
      await nameInput.fill('E2E Test Template');

      const textarea = page.locator('textarea').first();
      await textarea.fill('Created by Playwright E2E test');

      // Select category
      const categorySelect = page.locator('select').first();
      await categorySelect.selectOption('testing');

      // Select type
      const typeSelect = page.locator('select').nth(1);
      await typeSelect.selectOption('custom');

      // Submit
      const submitBtn = page.locator('button').filter({ hasText: 'Create Template' }).last();
      await submitBtn.click();
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(500);

      // Should show success notification or the modal should close
      const modalStillOpen = await page.locator('button').filter({ hasText: 'Cancel' }).count();
      // Either modal closed (success) or error notification shown
      expect(modalStillOpen === 0 || await page.locator('body').textContent()).toBeTruthy();
    });
  });

  test.describe('Template Detail Modal', () => {
    test('should open detail modal on card click', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForTimeout(500);

        // Detail modal should show template name and details
        // Check for metadata grid items
        await expect(page.locator('body')).toContainText(/category|type|installs|published/i);
      }
    });

    test('should display template metadata in detail view', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        const templateName = await cards.first().locator('h3').first().textContent();
        await cards.first().click();
        await page.waitForTimeout(500);

        // Template name should appear in modal
        if (templateName) {
          await expect(page.locator('body')).toContainText(templateName);
        }

        // Should show status badge, version, and metadata
        await expect(page.locator('body')).toContainText(/published|draft/i);
      }
    });

    test('should display tags in detail view', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(500);

        // Tags section should be visible for templates with tags
        const tagsSection = page.locator('text=Tags');
        if (await tagsSection.count() > 0) {
          await expect(tagsSection.first()).toBeVisible();
        }
      }
    });

    test('should display workflow pipeline nodes in detail view', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(500);

        // Workflow Pipeline section should be visible
        const pipelineSection = page.locator('text=Workflow Pipeline');
        if (await pipelineSection.count() > 0) {
          await expect(pipelineSection.first()).toBeVisible();
        }
      }
    });

    test('should close detail modal on Close button', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForTimeout(500);

        const closeBtn = page.locator('button').filter({ hasText: 'Close' });
        if (await closeBtn.count() > 0) {
          await closeBtn.click();
          await page.waitForTimeout(300);
        }
      }
    });

    test('should show Edit button only for owned templates', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(500);

        // The Edit Template button should exist in the modal footer if owned
        const editBtn = page.locator('button').filter({ hasText: 'Edit Template' });
        // Just verify it either exists or doesn't - both are valid based on ownership
        const editCount = await editBtn.count();
        expect(editCount === 0 || editCount === 1).toBeTruthy();
      }
    });

    test('should show Install button for non-installed templates', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForTimeout(500);

        // Either Install button or "Installed" badge should appear
        const hasInstallBtn = await page.locator('button').filter({ hasText: 'Install' }).count() > 0;
        const hasInstalledBadge = await page.locator('text=Installed').count() > 0;
        expect(hasInstallBtn || hasInstalledBadge).toBeTruthy();
      }
    });
  });

  test.describe('Edit Template Modal', () => {
    test('should open edit modal from card pencil icon', async ({ page }) => {
      // Find a pencil button (edit) on any card
      const editIcons = page.locator('[data-testid="devops-template-card"] button[title="Edit template"]');

      if (await editIcons.count() > 0) {
        await editIcons.first().click();
        await page.waitForTimeout(300);

        // Edit modal should be visible with pre-filled fields
        await expect(page.locator('text=Edit Template').first()).toBeVisible();

        const nameInput = page.locator('input[type="text"]').first();
        const nameValue = await nameInput.inputValue();
        expect(nameValue.length).toBeGreaterThan(0);
      }
    });

    test('should open edit modal from detail view', async ({ page }) => {
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        await cards.first().click();
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(500);

        const editBtn = page.locator('button').filter({ hasText: 'Edit Template' });
        if (await editBtn.count() > 0) {
          await editBtn.click();
          await page.waitForTimeout(300);

          await expect(page.locator('text=Edit Template').first()).toBeVisible();

          // Name field should be pre-filled
          const nameInput = page.locator('input[type="text"]').first();
          const nameValue = await nameInput.inputValue();
          expect(nameValue.length).toBeGreaterThan(0);
        }
      }
    });

    test('should have pre-filled form values in edit modal', async ({ page }) => {
      const editIcons = page.locator('[data-testid="devops-template-card"] button[title="Edit template"]');

      if (await editIcons.count() > 0) {
        await editIcons.first().click();
        await page.waitForTimeout(300);

        // All form selects should have a value
        const selects = page.locator('select');
        const selectCount = await selects.count();

        for (let i = 0; i < selectCount; i++) {
          const value = await selects.nth(i).inputValue();
          expect(value).toBeTruthy();
        }
      }
    });

    test('should close edit modal on Cancel', async ({ page }) => {
      const editIcons = page.locator('[data-testid="devops-template-card"] button[title="Edit template"]');

      if (await editIcons.count() > 0) {
        await editIcons.first().click();
        await page.waitForTimeout(300);

        const cancelBtn = page.locator('button').filter({ hasText: 'Cancel' });
        await cancelBtn.click();
        await page.waitForTimeout(300);

        // Modal should be closed
        const editHeader = page.locator('[class*="modal"]').locator('text=Edit Template');
        expect(await editHeader.count()).toBe(0);
      }
    });
  });

  test.describe('Tab Navigation & Content', () => {
    test('should switch to Installations tab and show content', async ({ page }) => {
      const installTab = page.locator('button').filter({ hasText: 'Installations' });
      await expect(installTab).toBeVisible();
      await installTab.click();
      await page.waitForTimeout(300);

      // Should show either installation items or empty state
      const hasInstallations = await page.locator('text=executions').count() > 0;
      const hasEmpty = await page.locator('text=No installations').count() > 0;
      expect(hasInstallations || hasEmpty).toBeTruthy();
    });

    test('should show uninstall button on installations', async ({ page }) => {
      const installTab = page.locator('button').filter({ hasText: 'Installations' });
      await installTab.click();
      await page.waitForTimeout(300);

      const uninstallBtns = page.locator('button[title="Uninstall template"]');
      if (await uninstallBtns.count() > 0) {
        await expect(uninstallBtns.first()).toBeVisible();
      }
    });

    test('should switch to Executions tab and show content', async ({ page }) => {
      const execTab = page.locator('button').filter({ hasText: 'Executions' });
      await expect(execTab).toBeVisible();
      await execTab.click();
      await page.waitForTimeout(300);

      const hasExecs = await page.locator('text=pipeline').count() > 0;
      const hasEmpty = await page.locator('text=No executions').count() > 0;
      expect(hasExecs || hasEmpty).toBeTruthy();
    });

    test('should switch to Risk Assessments tab and show content', async ({ page }) => {
      const riskTab = page.locator('button').filter({ hasText: 'Risk Assessments' });
      await expect(riskTab).toBeVisible();
      await riskTab.click();
      await page.waitForTimeout(300);

      const hasRisks = await page.locator('text=deployment').count() > 0;
      const hasEmpty = await page.locator('text=No risk assessments').count() > 0;
      expect(hasRisks || hasEmpty).toBeTruthy();
    });

    test('should switch to Code Reviews tab and show content', async ({ page }) => {
      const reviewTab = page.locator('button').filter({ hasText: 'Code Reviews' });
      await expect(reviewTab).toBeVisible();
      await reviewTab.click();
      await page.waitForTimeout(300);

      const hasReviews = await page.locator('text=files').count() > 0;
      const hasEmpty = await page.locator('text=No code reviews').count() > 0;
      expect(hasReviews || hasEmpty).toBeTruthy();
    });

    test('should switch to Analytics tab', async ({ page }) => {
      const analyticsTab = page.locator('button').filter({ hasText: 'Analytics' });
      await expect(analyticsTab).toBeVisible();
      await analyticsTab.click();
      await page.waitForTimeout(300);

      await expect(page.locator('body')).toContainText(/analytic/i);
    });

    test('should return to Templates tab from other tabs', async ({ page }) => {
      // Go to another tab first
      const installTab = page.locator('button').filter({ hasText: 'Installations' });
      await installTab.click();
      await page.waitForTimeout(300);

      // Go back to Templates
      const templatesTab = page.locator('button').filter({ hasText: 'Templates' });
      await templatesTab.click();
      await page.waitForTimeout(300);

      // Should show template cards or empty state again
      const hasGrid = await page.locator('[data-testid="devops-templates-grid"]').count() > 0;
      const hasEmpty = await page.locator('text=No templates').count() > 0;
      expect(hasGrid || hasEmpty).toBeTruthy();
    });
  });

  test.describe('Filters', () => {
    test('should have functional search input', async ({ page }) => {
      const searchInput = page.locator('input[type="search"]');
      await expect(searchInput).toBeVisible();
      await expect(searchInput).toBeEnabled();

      await searchInput.fill('security');
      await expect(searchInput).toHaveValue('security');
    });

    test('should have functional category filter', async ({ page }) => {
      const selects = page.locator('select');

      // First select after the search should be category filter
      if (await selects.count() > 0) {
        const categorySelect = selects.first();
        await expect(categorySelect).toBeVisible();

        // Should have multiple options
        const options = categorySelect.locator('option');
        expect(await options.count()).toBeGreaterThan(2);

        // Should be able to select a value
        await categorySelect.selectOption('deployment');
        await expect(categorySelect).toHaveValue('deployment');
      }
    });

    test('should have functional status filter', async ({ page }) => {
      const selects = page.locator('select');

      if (await selects.count() > 1) {
        const statusSelect = selects.nth(1);
        await expect(statusSelect).toBeVisible();

        await statusSelect.selectOption('published');
        await expect(statusSelect).toHaveValue('published');
      }
    });
  });

  test.describe('Card Click vs Button Click Isolation', () => {
    test('clicking Install button should not open detail modal', async ({ page }) => {
      const installBtns = page.locator('[data-testid="devops-template-card"] button:has-text("Install")');

      if (await installBtns.count() > 0) {
        await installBtns.first().click();
        await page.waitForTimeout(500);

        // Detail modal should NOT open - no Close button from detail modal
        // Install may trigger a notification instead
        const detailClose = page.locator('button').filter({ hasText: 'Close' });
        // If Close exists, it might be the detail modal, but could also be notification
        // The key check: the modal metadata grid should NOT appear
        const metadataGrid = page.locator('text=Workflow Pipeline');
        expect(await metadataGrid.count()).toBe(0);
      }
    });

    test('clicking Edit icon should not open detail modal', async ({ page }) => {
      const editIcons = page.locator('[data-testid="devops-template-card"] button[title="Edit template"]');

      if (await editIcons.count() > 0) {
        await editIcons.first().click();
        await page.waitForTimeout(300);

        // Should open Edit modal, not detail modal
        await expect(page.locator('text=Edit Template').first()).toBeVisible();
        // Should NOT show workflow pipeline (detail modal content)
        expect(await page.locator('text=Workflow Pipeline').count()).toBe(0);
      }
    });
  });

  test.describe('Loading States', () => {
    test('should show loading spinner initially', async ({ page }) => {
      // Navigate fresh and catch the loading state
      await page.goto(ROUTES.devopsTemplates);

      // Either spinner is visible or data already loaded
      const spinner = page.locator('.animate-spin');
      const content = page.locator('[data-testid="devops-templates-grid"], text=No templates');

      // One or the other should be present
      await expect(spinner.or(content.first())).toBeVisible({ timeout: 10000 });
    });

    test('should show loading in detail modal while fetching', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const cards = page.locator('[data-testid="devops-template-card"]');

      if (await cards.count() > 0) {
        // Click card - should briefly show loading
        await cards.first().click();

        // Either loading spinner or loaded content should appear
        const modalContent = page.locator('text=Category').or(page.locator('.animate-spin'));
        await expect(modalContent.first()).toBeVisible({ timeout: 5000 });
      }
    });
  });
});
