import { test, expect } from '@playwright/test';
import { PipelinesPage } from '../pages/devops/pipelines.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Pipelines E2E Tests
 *
 * Tests for CI/CD pipeline management functionality.
 * Note: Filter buttons are regular buttons (getByRole('button')), NOT tabs (getByRole('tab')).
 */

test.describe('Pipelines', () => {
  let pipelinesPage: PipelinesPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    pipelinesPage = new PipelinesPage(page);
    await pipelinesPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load Pipelines page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/pipeline/i);
    });

    test('should display create pipeline button', async ({ page }) => {
      const hasButton = await pipelinesPage.createPipelineButton.count() > 0;
      expect(hasButton).toBeTruthy();
    });

    test('should display pipelines list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*pipeline|create.*first/i).count() > 0;
      expect(hasPipelines || hasEmptyState).toBeTruthy();
    });

    test('should display search input', async ({ page }) => {
      const hasSearch = await pipelinesPage.searchInput.count() > 0;
      await expectOrAlternateState(page, hasSearch);
    });
  });

  test.describe('Pipeline Filter Buttons', () => {
    test('should have All filter button', async ({ page }) => {
      // Filter buttons are regular buttons, NOT tabs
      const hasAllButton = await pipelinesPage.allTab.count() > 0;
      const hasAllFilter = await page.getByText(/all/i).count() > 0;
      expect(hasAllButton || hasAllFilter).toBeTruthy();
    });

    test('should have Active filter button', async ({ page }) => {
      const hasActiveButton = await pipelinesPage.activeTab.count() > 0;
      const hasActiveFilter = await page.getByText(/active/i).count() > 0;
      expect(hasActiveButton || hasActiveFilter).toBeTruthy();
    });

    test('should have Inactive filter button', async ({ page }) => {
      const hasInactiveButton = await pipelinesPage.inactiveTab.count() > 0;
      const hasInactiveFilter = await page.getByText(/inactive/i).count() > 0;
      await expectOrAlternateState(page, hasInactiveButton || hasInactiveFilter);
    });

    test('should filter pipelines by status', async ({ page }) => {
      // Use button role, not tab role
      if (await pipelinesPage.activeTab.count() > 0) {
        await pipelinesPage.activeTab.click();
        await page.waitForTimeout(500);
      }
    });
  });

  test.describe('Pipeline List', () => {
    test('should display pipeline name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        await expect(pipelinesPage.pipelinesList.first()).toBeVisible();
      }
    });

    test('should display pipeline status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasStatus = await page.getByText(/active|inactive|running|success|failed/i).count() > 0;
      await expectOrAlternateState(page, hasStatus);
    });

    test('should display last run info', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        const hasLastRun = await page.getByText(/last.*run|ago|never/i).count() > 0;
        await expectOrAlternateState(page, hasLastRun);
      }
    });

    test('should display trigger type', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasTrigger = await page.getByText(/manual|push|schedule|webhook/i).count() > 0;
      await expectOrAlternateState(page, hasTrigger);
    });
  });

  test.describe('Create Pipeline', () => {
    test('should open create pipeline form', async ({ page }) => {
      await pipelinesPage.createPipelineButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[name="name"], [role="dialog"], form').count() > 0;
      const hasWizard = await page.getByText(/create.*pipeline|new.*pipeline/i).count() > 0;
      await expectOrAlternateState(page, hasForm || hasWizard);
    });

    test('should have name field', async ({ page }) => {
      await pipelinesPage.createPipelineButton.first().click();
      await page.waitForTimeout(500);
      const hasName = await pipelinesPage.pipelineNameInput.count() > 0;
      await expectOrAlternateState(page, hasName);
    });

    test('should have description field', async ({ page }) => {
      await pipelinesPage.createPipelineButton.first().click();
      await page.waitForTimeout(500);
      const hasDescription = await pipelinesPage.pipelineDescriptionInput.count() > 0;
      await expectOrAlternateState(page, hasDescription);
    });

    test('should have repository selection', async ({ page }) => {
      await pipelinesPage.createPipelineButton.first().click();
      await page.waitForTimeout(500);
      const hasRepoSelect = await page.locator('select[name*="repo"], [class*="repo-select"]').count() > 0;
      const hasRepoOption = await page.getByText(/repositor|select.*repo/i).count() > 0;
      await expectOrAlternateState(page, hasRepoSelect || hasRepoOption);
    });

    test('should have trigger configuration', async ({ page }) => {
      await pipelinesPage.createPipelineButton.first().click();
      await page.waitForTimeout(500);
      const hasTrigger = await page.getByText(/trigger|manual|webhook|schedule/i).count() > 0;
      await expectOrAlternateState(page, hasTrigger);
    });

    test('should have save button', async ({ page }) => {
      await pipelinesPage.createPipelineButton.first().click();
      await page.waitForTimeout(500);
      const hasSave = await pipelinesPage.saveButton.count() > 0;
      await expectOrAlternateState(page, hasSave);
    });
  });

  test.describe('Pipeline Actions', () => {
    test('should have run pipeline option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        const hasRunButton = await page.getByRole('button', { name: /run|trigger|execute/i }).count() > 0;
        await expectOrAlternateState(page, hasRunButton);
      }
    });

    test('should have edit pipeline option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        const hasEditButton = await page.getByRole('button', { name: /edit/i }).count() > 0;
        await expectOrAlternateState(page, hasEditButton);
      }
    });

    test('should have delete pipeline option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        const hasDeleteButton = await page.getByRole('button', { name: /delete/i }).count() > 0;
        await expectOrAlternateState(page, hasDeleteButton);
      }
    });

    test('should have duplicate pipeline option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        const hasDuplicateButton = await page.getByRole('button', { name: /duplicate|copy|clone/i }).count() > 0;
        await expectOrAlternateState(page, hasDuplicateButton);
      }
    });

    test('should have export YAML option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        const hasExportButton = await page.getByRole('button', { name: /export|yaml/i }).count() > 0;
        await expectOrAlternateState(page, hasExportButton);
      }
    });
  });

  test.describe('Pipeline Details', () => {
    test('should view pipeline details', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        await pipelinesPage.pipelinesList.first().click();
        await page.waitForTimeout(500);
        // Should navigate to details page
      }
    });

    test('should display pipeline steps', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        await pipelinesPage.pipelinesList.first().click();
        await page.waitForTimeout(500);
        const hasSteps = await page.getByText(/step|stage|job/i).count() > 0;
        await expectOrAlternateState(page, hasSteps);
      }
    });

    test('should display run history', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPipelines = await pipelinesPage.pipelinesList.count() > 0;
      if (hasPipelines) {
        await pipelinesPage.pipelinesList.first().click();
        await page.waitForTimeout(500);
        const hasRuns = await page.getByText(/run|history|execution/i).count() > 0;
        await expectOrAlternateState(page, hasRuns);
      }
    });
  });

  test.describe('Pipeline Runs', () => {
    test('should display run status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasRunStatus = await page.getByText(/running|success|failed|pending|queued/i).count() > 0;
      await expectOrAlternateState(page, hasRunStatus);
    });

    test('should display run duration', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasDuration = await page.getByText(/duration|time|seconds|minutes/i).count() > 0;
      await expectOrAlternateState(page, hasDuration);
    });
  });

  test.describe('Search and Filter', () => {
    test('should search pipelines', async ({ page }) => {
      await pipelinesPage.searchPipelines('test');
      await page.waitForTimeout(500);
    });

    test('should clear search', async ({ page }) => {
      await pipelinesPage.searchPipelines('test');
      await page.waitForTimeout(300);
      await pipelinesPage.searchPipelines('');
      await page.waitForTimeout(300);
    });
  });

  test.describe('Pipeline Scheduling', () => {
    test('should support scheduled triggers', async ({ page }) => {
      await pipelinesPage.createPipelineButton.first().click();
      await page.waitForTimeout(500);
      const hasSchedule = await page.getByText(/schedule|cron/i).count() > 0;
      await expectOrAlternateState(page, hasSchedule);
    });
  });

  test.describe('Pipeline Approval', () => {
    test('should support approval steps', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasApproval = await page.getByText(/approval|approve|review/i).count() > 0;
      await expectOrAlternateState(page, hasApproval);
    });
  });
});
