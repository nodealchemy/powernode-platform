import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * Parallel Execution Page Object Model
 *
 * Comprehensive POM for Parallel Execution E2E tests.
 * Route: /app/ai/parallel-execution
 *
 * Selector strategy:
 * - Card component renders as <div class="... bg-theme-surface ... cursor-pointer ...">
 *   (no literal "Card" in class names)
 * - Badge component renders as <span class="badge-theme badge-theme-* ...">
 *   (no literal "Badge" in class names)
 * - TabsTrigger renders as <button> without role="tab"
 *   (inside a flex container with border-b)
 * - Modal renders with role="dialog" (works with standard selector)
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

  // Tabs (TabsTrigger renders as plain <button> inside flex border-b container)
  readonly tabsContainer: Locator;
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
    this.pageTitle = page.locator('h1').first();

    // Session cards: Card component renders as div with bg-theme-surface and cursor-pointer
    this.sessionCards = page.locator('[class*="cursor-pointer"][class*="bg-theme-surface"]');
    this.createSessionButton = page.getByRole('button', { name: /new session/i });
    this.statusFilter = page.locator('select').first();
    this.refreshButton = page.locator('button').filter({ has: page.locator('svg[class*="lucide-refresh"]') });

    // Create Modal - Modal component uses role="dialog"
    this.modal = page.locator('[role="dialog"]');
    this.repositoryPathInput = this.modal.locator('input').first();
    this.baseBranchInput = this.modal.locator('input').nth(1);
    this.mergeStrategySelect = this.modal.locator('select');
    this.maxParallelInput = this.modal.locator('input[type="number"]');
    this.branchSuffixesInput = this.modal.locator('input').last();
    this.createButton = this.modal.getByRole('button', { name: /create session/i });
    this.cancelModalButton = this.modal.getByRole('button', { name: /cancel/i });

    // Detail View - PageContainer actions use aria-label and data-testid
    this.backToListButton = page.locator('[data-testid="action-back"]');
    this.cancelSessionButton = page.locator('[data-testid="action-cancel"]');
    this.retryMergeButton = page.getByRole('button', { name: /retry merge/i });
    // SessionSummaryCards uses grid-cols-4 with Card children (bg-theme-surface)
    this.summaryCards = page.locator('[class*="grid-cols-4"]').locator('[class*="bg-theme-surface"]');
    this.progressBar = page.locator('[class*="rounded-full"][class*="overflow-hidden"]').first();

    // Status badges - Badge component uses badge-theme classes
    this.sessionStatusBadge = page.locator('[class*="badge-theme"]').first();
    this.connectionBadge = page.locator('[class*="badge-theme"]').nth(1);

    // Tabs - TabsTrigger renders as <button> inside a TabsList flex container with border-b
    this.tabsContainer = page.locator('[class*="border-b"][class*="bg-theme-surface"]');
    this.agentsTab = this.tabsContainer.getByRole('button', { name: /agents/i });
    this.timelineTab = this.tabsContainer.getByRole('button', { name: /timeline/i });
    this.graphTab = this.tabsContainer.getByRole('button', { name: /graph/i });
    this.mergesTab = this.tabsContainer.getByRole('button', { name: /merges/i });
    this.configTab = this.tabsContainer.getByRole('button', { name: /configuration/i });

    // Agent Lanes - grid of AgentLane cards (bg-theme-bg-primary border)
    this.agentLanesPanel = page.locator('[class*="grid"][class*="gap-4"]').filter({
      has: page.locator('[class*="bg-theme-bg-primary"]'),
    });
    this.agentLanes = page.locator('[class*="bg-theme-bg-primary"][class*="border"][class*="rounded-lg"]');

    // Timeline
    this.timelineView = page.locator('[class*="overflow-x-auto"]').filter({ has: page.locator('svg') });
    this.timelineSvg = page.locator('svg').filter({ has: page.locator('rect') });

    // Merge Status
    this.mergeStatusPanel = page.locator('[class*="space-y"]').filter({ hasText: /merge/i });
    this.mergeOperations = page.locator('[class*="bg-theme-bg-primary"][class*="border"]').filter({ hasText: /\u2192/ });
    this.conflictFiles = page.locator('[class*="font-mono"]');

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
    const card = this.sessionCards.nth(index);
    await card.click();
    await this.page.waitForLoadState('networkidle');
  }

  async getSessionCount(): Promise<number> {
    return await this.sessionCards.count();
  }

  async switchTab(tabName: string) {
    const tab = this.tabsContainer.getByRole('button', { name: new RegExp(tabName, 'i') });
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
