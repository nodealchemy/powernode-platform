import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * Parallel Execution Page Object Model
 *
 * Comprehensive POM for Parallel Execution E2E tests.
 * Route: /app/ai/parallel-execution
 */
export class ParallelExecutionPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly sessionCards: Locator;
  readonly createSessionButton: Locator;
  readonly statusFilter: Locator;
  readonly refreshButton: Locator;

  // Create Session Modal
  readonly modal: Locator;
  readonly repositoryPathInput: Locator;
  readonly baseBranchInput: Locator;
  readonly mergeStrategySelect: Locator;
  readonly maxParallelInput: Locator;
  readonly branchSuffixesInput: Locator;
  readonly createButton: Locator;
  readonly cancelModalButton: Locator;

  // Session Detail View
  readonly backToListButton: Locator;
  readonly cancelSessionButton: Locator;
  readonly retryMergeButton: Locator;
  readonly summaryCards: Locator;
  readonly progressBar: Locator;

  // Status badges
  readonly sessionStatusBadge: Locator;
  readonly connectionBadge: Locator;

  // Tabs
  readonly agentsTab: Locator;
  readonly timelineTab: Locator;
  readonly graphTab: Locator;
  readonly mergesTab: Locator;
  readonly configTab: Locator;

  // Agent Lanes
  readonly agentLanesPanel: Locator;
  readonly agentLanes: Locator;

  // Timeline View
  readonly timelineView: Locator;
  readonly timelineSvg: Locator;

  // Merge Status
  readonly mergeStatusPanel: Locator;
  readonly mergeOperations: Locator;
  readonly conflictFiles: Locator;

  // Configuration Panel
  readonly configPanel: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.sessionCards = page.locator('[class*="Card"]').filter({ has: page.locator('[class*="cursor-pointer"]') });
    this.createSessionButton = page.getByRole('button', { name: /new session/i });
    this.statusFilter = page.locator('select').first();
    this.refreshButton = page.locator('button').filter({ has: page.locator('svg.lucide-refresh-cw') });

    // Create Modal
    this.modal = page.locator('[role="dialog"]');
    this.repositoryPathInput = this.modal.locator('input').first();
    this.baseBranchInput = this.modal.locator('input').nth(1);
    this.mergeStrategySelect = this.modal.locator('select');
    this.maxParallelInput = this.modal.locator('input[type="number"]');
    this.branchSuffixesInput = this.modal.locator('input').last();
    this.createButton = this.modal.getByRole('button', { name: /create session/i });
    this.cancelModalButton = this.modal.getByRole('button', { name: /cancel/i });

    // Detail View
    this.backToListButton = page.getByRole('button', { name: /back to list/i });
    this.cancelSessionButton = page.getByRole('button', { name: /cancel/i }).last();
    this.retryMergeButton = page.getByRole('button', { name: /retry merge/i });
    this.summaryCards = page.locator('[class*="grid-cols-4"]').locator('[class*="Card"]');
    this.progressBar = page.locator('[class*="rounded-full"][class*="overflow-hidden"]').first();

    // Status badges
    this.sessionStatusBadge = page.locator('[class*="Badge"]').first();
    this.connectionBadge = page.locator('[class*="Badge"]').nth(1);

    // Tabs
    this.agentsTab = page.getByRole('tab', { name: /agents/i });
    this.timelineTab = page.getByRole('tab', { name: /timeline/i });
    this.graphTab = page.getByRole('tab', { name: /graph/i });
    this.mergesTab = page.getByRole('tab', { name: /merges/i });
    this.configTab = page.getByRole('tab', { name: /configuration/i });

    // Agent Lanes
    this.agentLanesPanel = page.locator('[class*="grid"]').filter({ has: page.locator('[class*="AgentLane"], [class*="lane"]') });
    this.agentLanes = page.locator('[class*="Card"]').filter({ has: page.locator('text=commits') });

    // Timeline
    this.timelineView = page.locator('[class*="overflow-x-auto"]').filter({ has: page.locator('svg') });
    this.timelineSvg = page.locator('svg').filter({ has: page.locator('rect') });

    // Merge Status
    this.mergeStatusPanel = page.locator('[class*="space-y"]').filter({ hasText: /merge/i });
    this.mergeOperations = page.locator('[class*="border"]').filter({ hasText: /\u2192/ });
    this.conflictFiles = page.locator('[class*="font-mono"]').filter({ has: page.locator('svg.lucide-file-code') });

    // Config
    this.configPanel = page.locator('[class*="space-y"]').filter({ hasText: 'Session Configuration' });
  }

  async goto() {
    await this.page.goto(ROUTES.parallelExecution);
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/parallel|execution|session/i);
  }

  async clickCreateSession() {
    await this.createSessionButton.click();
    await expect(this.modal).toBeVisible();
  }

  async clickSessionCard(index: number) {
    const card = this.page.locator('[class*="Card"][class*="cursor-pointer"]').nth(index);
    await card.click();
    await this.page.waitForLoadState('networkidle');
  }

  async getSessionCount(): Promise<number> {
    return await this.page.locator('[class*="Card"][class*="cursor-pointer"]').count();
  }

  async switchTab(tabName: string) {
    const tab = this.page.getByRole('tab', { name: new RegExp(tabName, 'i') });
    await tab.click();
  }

  async goBack() {
    await this.backToListButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async filterByStatus(status: string) {
    await this.statusFilter.selectOption(status);
    await this.page.waitForLoadState('networkidle');
  }

  async refreshList() {
    await this.refreshButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async getStatusText(): Promise<string> {
    return (await this.sessionStatusBadge.textContent()) || '';
  }
}
