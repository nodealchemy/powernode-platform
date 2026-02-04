import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_AGENT_TEAM } from '../../fixtures/test-data';

/**
 * AI Agent Teams Page Object Model
 *
 * Encapsulates agent team management interactions for Playwright tests.
 * Corresponds to manual testing Phase 5: Agent Teams
 */
export class AgentTeamsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly teamCards: Locator;
  readonly createTeamButton: Locator;
  readonly statusFilter: Locator;
  readonly typeFilter: Locator;

  // Create Team Modal
  readonly nameInput: Locator;
  readonly descriptionInput: Locator;
  readonly typeSelect: Locator;
  readonly saveButton: Locator;
  readonly cancelButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.teamCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="team"]');
    this.createTeamButton = page.getByRole('button', { name: /create team/i });
    this.statusFilter = page.locator('select[name*="status"], [aria-label*="status"]');
    this.typeFilter = page.locator('select[name*="type"], [aria-label*="type"]');

    // Modal inputs
    this.nameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.descriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.typeSelect = page.locator('select[name="type"], [name="team_type"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });
  }

  /**
   * Navigate to agent teams page
   */
  async goto() {
    await this.page.goto(ROUTES.agentTeams);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/team/i);
  }

  /**
   * Click create team button
   */
  async clickCreateTeam() {
    await this.createTeamButton.click();
  }

  /**
   * Verify create modal is open
   */
  async verifyCreateModalOpen() {
    await expect(
      this.page.locator('[role="dialog"], [class*="modal"]')
    ).toBeVisible();
  }

  /**
   * Fill create team form
   */
  async fillTeamForm(data: Partial<typeof TEST_AGENT_TEAM> = TEST_AGENT_TEAM) {
    if (data.name) {
      await this.nameInput.fill(data.name);
    }
    if (data.description) {
      await this.descriptionInput.fill(data.description);
    }
    // Type select may need special handling
  }

  /**
   * Save team form
   */
  async saveTeam() {
    await this.saveButton.click();
  }

  /**
   * Create a new agent team
   */
  async createTeam(data: Partial<typeof TEST_AGENT_TEAM> = TEST_AGENT_TEAM) {
    await this.clickCreateTeam();
    await this.verifyCreateModalOpen();
    await this.fillTeamForm(data);
    await this.saveTeam();
  }

  /**
   * Get team card by name
   */
  getTeamCard(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), [class*="Card"]:has-text("${name}")`);
  }

  /**
   * Verify team card exists
   */
  async verifyTeamExists(name: string) {
    const card = this.getTeamCard(name);
    await expect(card).toBeVisible();
  }

  /**
   * Click execute on a team
   */
  async clickExecute(teamName: string) {
    const card = this.getTeamCard(teamName);
    const executeButton = card.getByRole('button', { name: /execute|run/i });
    await executeButton.click();
  }

  /**
   * Enter team execution task
   */
  async enterExecutionTask(task: string) {
    const taskInput = this.page.locator('textarea[placeholder*="task" i], input[placeholder*="task" i], textarea').first();
    await taskInput.fill(task);
  }

  /**
   * Submit team execution
   */
  async submitExecution() {
    const submitButton = this.page.getByRole('button', { name: /execute|run|start/i });
    await submitButton.click();
  }

  /**
   * Wait for team execution to start
   */
  async waitForExecutionStart() {
    await this.page.waitForSelector('[class*="execution"], [class*="running"], :text("Running")', {
      timeout: 30000,
    });
  }

  /**
   * Verify execution monitor is visible
   */
  async verifyExecutionMonitor() {
    await expect(
      this.page.locator('[class*="monitor"], [class*="execution-status"]')
    ).toBeVisible();
  }

  /**
   * Verify agent-by-agent progress
   */
  async verifyAgentProgress() {
    // Look for individual agent status indicators
    await expect(
      this.page.locator('[class*="agent-status"], [class*="step"]')
    ).toBeVisible();
  }

  /**
   * Wait for team execution to complete
   */
  async waitForExecutionComplete() {
    await this.page.waitForSelector(':text("Completed"), :text("Success"), [class*="complete"]', {
      timeout: 180000, // 3 minutes for multi-agent execution
    });
  }

  /**
   * Click edit on a team
   */
  async clickEdit(teamName: string) {
    const card = this.getTeamCard(teamName);
    const editButton = card.getByRole('button', { name: /edit/i });
    await editButton.click();
  }

  /**
   * Click delete on a team
   */
  async clickDelete(teamName: string) {
    const card = this.getTeamCard(teamName);
    const deleteButton = card.getByRole('button', { name: /delete/i });
    await deleteButton.click();
  }

  /**
   * Confirm deletion
   */
  async confirmDelete() {
    const confirmButton = this.page.getByRole('button', { name: /confirm|yes|delete/i });
    await confirmButton.click();
  }

  /**
   * Filter by status
   */
  async filterByStatus(status: string) {
    await this.statusFilter.click();
    await this.page.locator(`:text("${status}")`).click();
  }

  /**
   * Filter by type
   */
  async filterByType(type: 'Hierarchical' | 'Mesh' | 'Sequential' | 'Parallel') {
    await this.typeFilter.click();
    await this.page.locator(`:text("${type}")`).click();
  }

  /**
   * Verify empty state is shown
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No teams"), :text("Create Team"), :text("Get started")')
    ).toBeVisible();
  }

  /**
   * Get count of team cards
   */
  async getTeamCount(): Promise<number> {
    return await this.teamCards.count();
  }

  /**
   * Verify team type options exist
   */
  async verifyTypeOptions() {
    await expect(
      this.page.locator(':text("Hierarchical"), :text("Sequential"), :text("Parallel")')
    ).toBeVisible();
  }
}
