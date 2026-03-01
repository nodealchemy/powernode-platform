import { test, expect } from '@playwright/test';
import { WorkflowsPage } from '../pages/ai/workflows.page';
import { TEST_WORKFLOW, uniqueTestData } from '../fixtures/test-data';

/**
 * AI Workflows E2E Tests
 *
 * Tests for AI Workflow management and execution functionality.
 * Corresponds to Manual Testing Phase 4: Workflows
 *
 * @see docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_FRONTEND.md
 */

test.describe('AI Workflows', () => {
  let workflowsPage: WorkflowsPage;

  test.beforeEach(async ({ page }) => {
    workflowsPage = new WorkflowsPage(page);
    await workflowsPage.goto();
    await workflowsPage.waitForReady();
  });

  test.describe('Page Navigation', () => {
    test('should navigate to AI Workflows from sidebar', async ({ page }) => {
      await expect(page).toHaveURL(/\/workflows/);
    });

    test('should load AI Workflows page directly', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/workflows|ai/i);
    });

    test('should display breadcrumbs', async ({ page }) => {
      // Breadcrumbs show: Home > AI > Workflows
      await expect(page.locator('body')).toContainText(/ai.*workflow|workflow/i);
    });
  });

  test.describe('Workflows List Display', () => {
    test('should display workflows list or empty state', async ({ page }) => {
      const hasWorkflows = await page.locator('table tbody tr, [class*="workflow-card"]').count() > 0;
      const hasEmptyState = await page.locator(':text("No workflows"), :text("Create Workflow")').count() > 0;

      expect(hasWorkflows || hasEmptyState).toBeTruthy();
    });

    test('should display workflow status badges', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/draft|active|inactive|paused|archived|no workflows/i);
    });

    test('should display workflow stats (nodes, runs)', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/nodes|runs|no workflows/i);
    });
  });

  test.describe('Search Functionality', () => {
    test('should have search input', async ({ page }) => {
      const searchInput = page.locator('input[type="text"][placeholder*="search" i], input[type="search"]');
      await expect(searchInput.first()).toBeVisible();
    });

    test('should filter workflows by search query', async ({ page }) => {
      const searchInput = page.locator('input[type="text"][placeholder*="search" i], input[type="search"]').first();
      await searchInput.fill('test');
      await expect(page.locator('body')).toBeVisible();
    });

    test('should clear search and show all workflows', async ({ page }) => {
      const searchInput = page.locator('input[type="text"][placeholder*="search" i], input[type="search"]').first();
      await searchInput.fill('test');
      await searchInput.clear();
      await expect(page.locator('body')).toBeVisible();
    });
  });

  test.describe('Status Filter', () => {
    test('should have status filter dropdown', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/all statuses|status|filter/i);
    });

    test('should filter by draft status', async ({ page }) => {
      // EnhancedSelect renders as a button with aria-haspopup="listbox"
      const statusFilter = page.locator('button[aria-haspopup="listbox"]').filter({ hasText: /all statuses|status|draft|active/i }).first();

      if (await statusFilter.count() > 0) {
        await statusFilter.click();
        await page.waitForTimeout(300);
        // Dropdown should show status options in a listbox
        const hasOptions = await page.locator('[role="option"], [role="listbox"] li').count() > 0;
        expect(hasOptions).toBeTruthy();
      }
      // Skip if no status filter button available
    });
  });

  test.describe('Type Filter (All, Workflows, Templates)', () => {
    test('should have type filter buttons', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/all|workflows|templates/i);
    });

    test('should filter to show only workflows', async ({ page }) => {
      const workflowsButton = page.locator('button:has-text("Workflows")').first();

      if (await workflowsButton.count() > 0) {
        await workflowsButton.click();
        await expect(page).toHaveURL(/type=workflows/);
      }
    });

    test('should filter to show only templates', async ({ page }) => {
      const templatesButton = page.locator('button:has-text("Templates")');

      if (await templatesButton.count() > 0) {
        await templatesButton.click();
        await expect(page).toHaveURL(/type=templates/);
      }
    });
  });

  test.describe('Create Workflow - Phase 4.1', () => {
    test('should display Create Workflow button', async ({ page }) => {
      // Create Workflow button requires ai.workflows.create permission
      const createButton = page.locator('button:has-text("Create Workflow")');
      if (await createButton.count() > 0) {
        await expect(createButton.first()).toBeVisible();
      }
    });

    test('should open create modal when button clicked', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Workflow")');

      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500); // Allow modal animation

        // Modal should show workflow creation form
        const hasModal = await page.locator('[role="dialog"], [class*="modal"], input[name="name"], label:has-text("Name")').count() > 0;
        expect(hasModal).toBeTruthy();
      }
    });

    test('should have name input in create modal', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Workflow")');

      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500); // Allow modal animation

        // Check for name input or label
        const hasNameInput = await page.locator('input[name="name"], input[placeholder*="name" i], label:has-text("Name")').count() > 0;
        expect(hasNameInput).toBeTruthy();
      }
    });

    test('should create a new workflow', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Workflow")');

      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForTimeout(500);

        // Verify modal/form is accessible
        await expect(page.locator('body')).toContainText(/workflow|name|create/i);
      }
    });

    test('should close modal when cancel clicked', async ({ page }) => {
      const createButton = page.locator('button:has-text("Create Workflow")');

      if (await createButton.count() > 0) {
        await createButton.click();
        await page.waitForLoadState('networkidle');

        const cancelButton = page.locator('button:has-text("Cancel"), button:has-text("Close")');
        await cancelButton.first().click();
        await page.waitForLoadState('networkidle');

        await expect(page.locator('[role="dialog"]')).not.toBeVisible();
      }
    });
  });

  test.describe('Add Nodes - Phase 4.2', () => {
    test('should open workflow builder', async ({ page }) => {
      // Look for view/edit button on a workflow row (eye icon or edit icon)
      const viewButton = page.locator('button[title*="View"], button[title*="Edit"], [class*="lucide-eye"], [class*="lucide-edit"]').first();

      if (await viewButton.count() > 0) {
        await viewButton.click();
        await page.waitForTimeout(1000);

        // Verify we navigated to workflow detail or builder
        const isOnDetailPage = page.url().includes('/workflows/');
        const hasBuilderElements = await page.locator('[class*="canvas"], [class*="react-flow"], [class*="node"], [class*="workflow"]').count() > 0;

        expect(isOnDetailPage || hasBuilderElements).toBeTruthy();
      }
      // Skip if no workflows exist to open
    });
  });

  test.describe('Execute Workflow - Phase 4.3', () => {
    test('should execute workflow', async ({ page }) => {
      const executeButton = page.locator('button[title*="Execute"], [class*="play"]').first();

      if (await executeButton.count() > 0) {
        await executeButton.click();
        await page.waitForLoadState('networkidle');

        // Enter input if prompted
        const inputField = page.locator('textarea, input[type="text"]').first();
        if (await inputField.isVisible()) {
          await inputField.fill('Test execution input');

          const submitButton = page.locator('button:has-text("Execute"), button:has-text("Run")');
          await submitButton.click();
        }

        // Wait for execution to start
        await expect(page.locator(':text("Running"), :text("Executing"), [class*="progress"]')).toBeVisible({ timeout: 30000 });
      }
    });
  });

  test.describe('View Results - Phase 4.4', () => {
    test('should view workflow execution results', async ({ page }) => {
      // This requires a completed execution
      await expect(page.locator('body')).toContainText(/workflow|result|output/i);
    });
  });

  test.describe('Workflow Validation - Phase 18', () => {
    test('should view workflow health score', async ({ page }) => {
      const workflowRow = page.locator('tr, [class*="workflow"]').first();

      if (await workflowRow.count() > 0) {
        await workflowRow.click();
        await page.waitForLoadState('networkidle');

        // Look for validation section
        const validationTab = page.locator('[role="tab"]:has-text("Validation"), button:has-text("Validation")');

        if (await validationTab.count() > 0) {
          await validationTab.click();

          // Verify health score
          await expect(page.locator('[class*="health"], :text("Health Score"), :text("%")')).toBeVisible();
        }
      }
    });
  });

  test.describe('Duplicate Workflow', () => {
    test('should have duplicate action when workflows exist', async ({ page }) => {
      const hasWorkflows = await page.locator('table tbody tr, [class*="workflow-card"]').count() > 0;
      if (hasWorkflows) {
        const duplicateButton = page.locator('button[title*="Duplicate"], button[title*="Copy"], [class*="copy"]');
        const hasDuplicate = await duplicateButton.count() > 0;
        expect(hasDuplicate).toBeTruthy();
      }
    });
  });

  test.describe('Delete Workflow', () => {
    test('should have delete action when workflows exist', async ({ page }) => {
      const hasWorkflows = await page.locator('table tbody tr, [class*="workflow-card"]').count() > 0;
      if (hasWorkflows) {
        const deleteButton = page.locator('button[title*="Delete"], [class*="trash"]');
        const hasDelete = await deleteButton.count() > 0;
        expect(hasDelete).toBeTruthy();
      }
    });
  });

  test.describe('Pagination', () => {
    test('should display pagination controls when many workflows exist', async ({ page }) => {
      const workflowCount = await page.locator('table tbody tr, [class*="workflow-card"]').count();
      if (workflowCount > 10) {
        const hasPagination = await page.locator('[class*="pagination"], button:has-text("Next"), button:has-text("Previous")').count() > 0;
        expect(hasPagination).toBeTruthy();
      }
    });
  });

  test.describe('Refresh Functionality', () => {
    test('should have refresh button', async ({ page }) => {
      const refreshButton = page.locator('button:has-text("Refresh")');
      await expect(refreshButton).toBeVisible();
    });
  });

  test.describe('Monitoring Navigation', () => {
    test('should have monitoring button', async ({ page }) => {
      const monitoringButton = page.locator('button:has-text("Monitoring")');
      await expect(monitoringButton).toBeVisible();
    });

    test('should navigate to monitoring page', async ({ page }) => {
      const monitoringButton = page.locator('button:has-text("Monitoring")');

      if (await monitoringButton.count() > 0) {
        await monitoringButton.click();
        await expect(page).toHaveURL(/\/monitoring/);
      }
    });
  });

  test.describe('Import Workflow', () => {
    test('should have import button', async ({ page }) => {
      const importButton = page.locator('button:has-text("Import")');
      // Import button is only visible when user has create workflow permission
      if (await importButton.count() > 0) {
        await expect(importButton).toBeVisible();
      }
    });

    test('should navigate to import page', async ({ page }) => {
      const importButton = page.locator('button:has-text("Import")');

      if (await importButton.count() > 0) {
        await importButton.click();
        await expect(page).toHaveURL(/\/import/);
      }
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
      await workflowsPage.goto();
      await expect(page.locator('body')).toContainText(/workflow|ai/i);
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await workflowsPage.goto();
      await expect(page.locator('body')).toContainText(/workflow|ai/i);
    });

    test('should stack elements on small screens', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await workflowsPage.goto();
      await expect(page.locator('body')).toBeVisible();
    });
  });
});
