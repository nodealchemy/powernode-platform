import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * Ralph Loops Page Object Model
 *
 * Comprehensive POM for Ralph Loops E2E tests.
 * Route: /app/ai/ralph-loops
 */
export class RalphLoopsPage {
  readonly page: Page;

  // List view
  readonly newLoopButton: Locator;
  readonly statusFilter: Locator;
  readonly agentFilter: Locator;
  readonly refreshButton: Locator;
  readonly loopCards: Locator;
  readonly emptyState: Locator;

  // Detail view
  readonly backButton: Locator;
  readonly startButton: Locator;
  readonly pauseButton: Locator;
  readonly resumeButton: Locator;
  readonly cancelButton: Locator;
  readonly resetButton: Locator;
  readonly runOneButton: Locator;
  readonly settingsButton: Locator;
  readonly statusBadge: Locator;

  // Run All / Stop Run All
  readonly runAllButton: Locator;
  readonly stopRunAllButton: Locator;

  // Live Execution Panel
  readonly liveExecutionHeader: Locator;
  readonly liveExecutionWaiting: Locator;

  // Stats cards
  readonly iterationsCard: Locator;
  readonly tasksCard: Locator;
  readonly progressCard: Locator;
  readonly agentCard: Locator;

  // Tabs
  readonly tasksTab: Locator;
  readonly iterationsTab: Locator;
  readonly progressTab: Locator;
  readonly scheduleTab: Locator;

  // Create dialog
  readonly dialog: Locator;
  readonly dialogNameInput: Locator;
  readonly dialogDescriptionInput: Locator;
  readonly dialogAgentSelect: Locator;
  readonly dialogMaxIterations: Locator;
  readonly dialogCreateButton: Locator;
  readonly dialogCancelButton: Locator;

  constructor(page: Page) {
    this.page = page;

    // List view
    this.newLoopButton = page.getByRole('button', { name: /new loop/i });
    this.statusFilter = page.locator('select').first();
    this.agentFilter = page.locator('select').nth(1);
    this.refreshButton = page.locator('button').filter({ has: page.locator('svg.lucide-refresh-cw') });
    this.loopCards = page.locator('[class*="Card"]').filter({ has: page.locator('[class*="card"]') });
    this.emptyState = page.locator('text=No loops found');

    // Detail view actions
    this.backButton = page.getByRole('button', { name: /back to list/i });
    this.startButton = page.getByRole('button', { name: /start loop/i });
    this.pauseButton = page.getByRole('button', { name: /^pause$/i });
    this.resumeButton = page.getByRole('button', { name: /^resume$/i });
    this.cancelButton = page.getByRole('button', { name: /^cancel$/i });
    this.resetButton = page.getByRole('button', { name: /^reset$/i });
    this.runOneButton = page.getByRole('button', { name: /run one/i });
    this.settingsButton = page.getByRole('button', { name: /settings/i });
    this.statusBadge = page.locator('[class*="Badge"]').first();

    // Run All / Stop Run All
    this.runAllButton = page.locator('[data-testid="action-run-all"]');
    this.stopRunAllButton = page.locator('[data-testid="action-stop-run-all"]');

    // Live Execution Panel
    this.liveExecutionHeader = page.locator('text=Live Execution');
    this.liveExecutionWaiting = page.locator('text=Waiting for iteration results...');

    // Stats cards (by content text)
    this.iterationsCard = page.locator('text=Iterations').locator('..');
    this.tasksCard = page.locator('text=Tasks Completed').locator('..');
    this.progressCard = page.locator('text=Progress').locator('..').first();
    this.agentCard = page.locator('text=Default Agent').locator('..');

    // Tabs
    this.tasksTab = page.getByRole('tab', { name: /tasks/i });
    this.iterationsTab = page.getByRole('tab', { name: /iterations/i });
    this.progressTab = page.getByRole('tab', { name: /progress/i });
    this.scheduleTab = page.getByRole('tab', { name: /schedule/i });

    // Create dialog
    this.dialog = page.locator('[role="dialog"]');
    this.dialogNameInput = this.dialog.locator('input').first();
    this.dialogDescriptionInput = this.dialog.locator('input').nth(1);
    this.dialogAgentSelect = this.dialog.locator('select');
    this.dialogMaxIterations = this.dialog.locator('input[type="number"]');
    this.dialogCreateButton = this.dialog.getByRole('button', { name: /create loop/i });
    this.dialogCancelButton = this.dialog.getByRole('button', { name: /cancel/i });
  }

  async goto() {
    await this.page.goto(ROUTES.ralphLoops);
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/ralph|loop/i);
  }

  async selectLoopByName(name: string) {
    const card = this.page.locator('[class*="Card"]').filter({ hasText: name }).first();
    await card.click();
    await this.page.waitForLoadState('networkidle');
  }

  async openCreateDialog() {
    await this.newLoopButton.click();
    await expect(this.dialog).toBeVisible();
  }

  async startLoop() {
    await this.startButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async pauseLoop() {
    await this.pauseButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async resumeLoop() {
    await this.resumeButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async runOneIteration() {
    await this.runOneButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async resetLoop() {
    await this.resetButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async goBack() {
    await this.backButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async switchTab(name: 'tasks' | 'iterations' | 'progress' | 'schedule') {
    const tabMap = {
      tasks: this.tasksTab,
      iterations: this.iterationsTab,
      progress: this.progressTab,
      schedule: this.scheduleTab,
    };
    await tabMap[name].click();
  }

  async getStatusText(): Promise<string> {
    return (await this.statusBadge.textContent()) || '';
  }

  async getAgentName(): Promise<string> {
    const agentSection = this.page.locator('text=Default Agent').locator('..');
    return (await agentSection.textContent()) || '';
  }

  async getLoopCount(): Promise<number> {
    const cards = this.page.locator('[class*="cursor-pointer"][class*="Card"]');
    return await cards.count();
  }

  async isRunOneVisible(): Promise<boolean> {
    return await this.runOneButton.isVisible();
  }

  async runAll() {
    await this.runAllButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async stopRunAll() {
    await this.stopRunAllButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async isRunAllVisible(): Promise<boolean> {
    return await this.runAllButton.isVisible();
  }

  async isStopRunAllVisible(): Promise<boolean> {
    return await this.stopRunAllButton.isVisible();
  }

  async isLiveExecutionPanelVisible(): Promise<boolean> {
    return await this.liveExecutionHeader.isVisible();
  }
}
