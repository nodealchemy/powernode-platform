import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_WORKFLOW } from '../../fixtures/test-data';

/**
 * AI Workflows Page Object Model
 *
 * Encapsulates workflow management interactions for Playwright tests.
 * Corresponds to manual testing Phase 4: Workflows
 */
export class WorkflowsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly workflowList: Locator;
  readonly createWorkflowButton: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly visibilityFilter: Locator;
  readonly typeFilter: Locator;
  readonly refreshButton: Locator;
  readonly monitoringButton: Locator;
  readonly importButton: Locator;

  // Create Workflow Modal
  readonly nameInput: Locator;
  readonly descriptionInput: Locator;
  readonly saveButton: Locator;
  readonly cancelButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.workflowList = page.locator('table tbody tr, [class*="workflow-card"]');
    this.createWorkflowButton = page.getByRole('button', { name: /create workflow/i });
    this.searchInput = page.locator('input[type="text"][placeholder*="search" i], input[type="search"]');
    this.statusFilter = page.locator('button[aria-haspopup="listbox"]').filter({ hasText: /all statuses|status/i }).first();
    this.visibilityFilter = page.locator('button[aria-haspopup="listbox"]').filter({ hasText: /all visibility|visibility/i }).first();
    this.typeFilter = page.locator('button:has-text("All"), button:has-text("Workflows"), button:has-text("Templates")');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.monitoringButton = page.getByRole('button', { name: /monitoring/i });
    this.importButton = page.getByRole('button', { name: /import/i });

    // Modal inputs
    this.nameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.descriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });
  }

  /**
   * Navigate to workflows page
   */
  async goto() {
    await this.page.goto(ROUTES.workflows);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"], body', { timeout: 10000 });
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/workflow/i);
  }

  /**
   * Click create workflow button
   */
  async clickCreateWorkflow() {
    await this.createWorkflowButton.click();
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
   * Fill create workflow form
   */
  async fillWorkflowForm(name: string = TEST_WORKFLOW.name, description: string = TEST_WORKFLOW.description) {
    await this.nameInput.fill(name);
    if (description) {
      await this.descriptionInput.fill(description);
    }
  }

  /**
   * Save workflow form
   */
  async saveWorkflow() {
    await this.saveButton.click();
  }

  /**
   * Create a new workflow
   */
  async createWorkflow(name: string = TEST_WORKFLOW.name, description: string = TEST_WORKFLOW.description) {
    await this.clickCreateWorkflow();
    await this.verifyCreateModalOpen();
    await this.fillWorkflowForm(name, description);
    await this.saveWorkflow();
  }

  /**
   * Get workflow row by name
   */
  getWorkflowRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="workflow"]:has-text("${name}")`);
  }

  /**
   * Open workflow detail/builder
   */
  async openWorkflow(name: string) {
    const row = this.getWorkflowRow(name);
    await row.click();
  }

  /**
   * Click view details on a workflow
   */
  async clickViewDetails(name: string) {
    const row = this.getWorkflowRow(name);
    const viewButton = row.locator('button[title*="View"], [class*="eye"]');
    await viewButton.click();
  }

  /**
   * Click execute on a workflow
   */
  async clickExecute(name: string) {
    const row = this.getWorkflowRow(name);
    const executeButton = row.locator('button[title*="Execute"], [class*="play"]');
    await executeButton.click();
  }

  /**
   * Enter workflow execution input
   */
  async enterExecutionInput(input: string) {
    const inputField = this.page.locator('textarea, input[type="text"]').first();
    await inputField.fill(input);
  }

  /**
   * Submit workflow execution
   */
  async submitExecution() {
    const executeButton = this.page.getByRole('button', { name: /execute|run|start/i });
    await executeButton.click();
  }

  /**
   * Wait for workflow execution to complete
   */
  async waitForExecutionComplete() {
    // Wait for completion indicator
    await this.page.waitForSelector(':text("Completed"), :text("Success"), [class*="complete"]', {
      timeout: 120000,
    });
  }

  /**
   * Verify execution results
   */
  async verifyExecutionResults() {
    await expect(
      this.page.locator('[class*="result"], [class*="output"], :text("Output")')
    ).toBeVisible();
  }

  /**
   * Click duplicate on a workflow
   */
  async clickDuplicate(name: string) {
    const row = this.getWorkflowRow(name);
    const duplicateButton = row.locator('button[title*="Duplicate"], button[title*="Copy"]');
    await duplicateButton.click();
  }

  /**
   * Click delete on a workflow
   */
  async clickDelete(name: string) {
    const row = this.getWorkflowRow(name);
    const deleteButton = row.locator('button[title*="Delete"], [class*="trash"]');
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
  async filterByStatus(status: 'Draft' | 'Active' | 'Inactive' | 'Paused' | 'Archived') {
    await this.statusFilter.click();
    await this.page.locator(`:text("${status}")`).click();
  }

  /**
   * Filter by type (All, Workflows, Templates)
   */
  async filterByType(type: 'All' | 'Workflows' | 'Templates') {
    const button = this.page.locator(`button:has-text("${type}")`).first();
    await button.click();
  }

  /**
   * Search workflows
   */
  async search(query: string) {
    await this.searchInput.fill(query);
  }

  /**
   * Clear search
   */
  async clearSearch() {
    await this.searchInput.clear();
  }

  /**
   * Verify empty state is shown
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No workflows"), :text("Get started"), :text("Create Workflow")')
    ).toBeVisible();
  }

  /**
   * Navigate to monitoring
   */
  async goToMonitoring() {
    await this.monitoringButton.click();
  }

  /**
   * Navigate to import
   */
  async goToImport() {
    await this.importButton.click();
  }

  /**
   * Refresh workflow list
   */
  async refresh() {
    await this.refreshButton.click();
  }

  /**
   * Get count of workflows in list
   */
  async getWorkflowCount(): Promise<number> {
    return await this.workflowList.count();
  }

  // === Workflow Builder Methods ===

  /**
   * Verify workflow builder is open
   */
  async verifyBuilderOpen() {
    await expect(
      this.page.locator('[class*="canvas"], [class*="react-flow"], [class*="workflow-builder"]')
    ).toBeVisible();
  }

  /**
   * Add a node to the canvas
   */
  async addNode(nodeType: 'start' | 'ai_agent' | 'end' | 'condition' | 'transform') {
    // Open node palette or use drag-drop
    const addButton = this.page.getByRole('button', { name: /add node|add/i });
    await addButton.click();

    // Select node type
    const nodeOption = this.page.locator(`:text("${nodeType}"), [data-node-type="${nodeType}"]`);
    await nodeOption.click();
  }

  /**
   * Connect two nodes
   */
  async connectNodes(fromNode: string, toNode: string) {
    // This would require interaction with the React Flow canvas
    // Implementation depends on the specific UI structure
  }

  /**
   * View workflow validation
   */
  async openValidation() {
    const validationTab = this.page.locator('[role="tab"]:has-text("Validation"), button:has-text("Validation")');
    await validationTab.click();
  }

  /**
   * Verify health score is displayed
   */
  async verifyHealthScore() {
    await expect(
      this.page.locator('[class*="health"], :text("Health Score"), :text("%")')
    ).toBeVisible();
  }
}
