import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * A2A Tasks Page Object Model
 *
 * Encapsulates Agent-to-Agent task management interactions for Playwright tests.
 * Supports task listing, detail views, event streams, and status monitoring.
 */
export class A2aTasksPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly taskList: Locator;
  readonly refreshButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;

  // Task Detail
  readonly backToListButton: Locator;
  readonly taskDetailPanel: Locator;
  readonly eventStream: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.taskList = page.locator('[data-testid="task-list"], table tbody tr, [class*="task-item"], [class*="card"]');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i], input[placeholder*="filter" i]');
    this.statusFilter = page.locator('select, [role="combobox"]').first();

    // Detail view
    this.backToListButton = page.getByRole('button', { name: /back|list/i });
    this.taskDetailPanel = page.locator('[class*="detail"], [class*="panel"], [data-testid="task-detail"]');
    this.eventStream = page.locator('[data-testid="event-stream"], [class*="event-stream"], [class*="events"]');
  }

  /**
   * Navigate to A2A tasks page
   */
  async goto() {
    await this.page.goto(ROUTES.a2aTasks);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
    await this.page.waitForTimeout(1000);
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/a2a|task|agent-to-agent/i);
  }

  /**
   * Get task row by index
   */
  getTaskRow(index: number): Locator {
    return this.taskList.nth(index);
  }

  /**
   * Click on a task to view details
   */
  async openTaskDetail(index: number = 0) {
    const taskRow = this.taskList.nth(index);
    if (await taskRow.count() > 0) {
      await taskRow.click();
      await this.page.waitForTimeout(500);
    }
  }

  /**
   * Click back to list from detail view
   */
  async backToList() {
    if (await this.backToListButton.count() > 0) {
      await this.backToListButton.click();
    }
  }

  /**
   * Verify task detail view is visible
   */
  async verifyDetailViewOpen() {
    await expect(
      this.page.locator(':text("Task Details"), :text("Details"), :text("Back to List")')
    ).toBeVisible();
  }

  /**
   * Verify event stream is visible
   */
  async verifyEventStreamVisible() {
    const hasEventStream = await this.eventStream.count() > 0;
    return hasEventStream;
  }

  /**
   * Get task count
   */
  async getTaskCount(): Promise<number> {
    return await this.taskList.count();
  }

  /**
   * Verify empty state
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No tasks"), :text("Monitor"), :text("no tasks")')
    ).toBeVisible();
  }

  /**
   * Refresh task list
   */
  async refresh() {
    if (await this.refreshButton.count() > 0) {
      await this.refreshButton.click();
    }
  }

  /**
   * Search tasks
   */
  async search(query: string) {
    if (await this.searchInput.count() > 0) {
      await this.searchInput.first().fill(query);
    }
  }

  /**
   * Clear search
   */
  async clearSearch() {
    if (await this.searchInput.count() > 0) {
      await this.searchInput.first().clear();
    }
  }
}
