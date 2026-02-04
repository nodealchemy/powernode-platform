import { Page, Locator, expect } from '@playwright/test';

/**
 * Pipelines Page Object Model
 */
export class PipelinesPage {
  readonly page: Page;
  readonly createPipelineButton: Locator;
  readonly pipelinesList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly allTab: Locator;
  readonly activeTab: Locator;
  readonly inactiveTab: Locator;

  // Create Pipeline Form
  readonly pipelineNameInput: Locator;
  readonly pipelineDescriptionInput: Locator;
  readonly repositorySelect: Locator;
  readonly branchInput: Locator;
  readonly triggerSelect: Locator;
  readonly saveButton: Locator;

  // Pipeline Detail
  readonly runPipelineButton: Locator;
  readonly editPipelineButton: Locator;
  readonly deletePipelineButton: Locator;
  readonly exportYamlButton: Locator;
  readonly duplicateButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.createPipelineButton = page.getByRole('button', { name: /create.*pipeline|new.*pipeline|add/i });
    this.pipelinesList = page.locator('table tbody tr, [class*="pipeline-card"], [class*="card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"]');

    // Tabs
    this.allTab = page.getByRole('tab', { name: /all/i });
    this.activeTab = page.getByRole('tab', { name: /active/i });
    this.inactiveTab = page.getByRole('tab', { name: /inactive/i });

    // Form fields
    this.pipelineNameInput = page.locator('input[name="name"]');
    this.pipelineDescriptionInput = page.locator('textarea[name="description"]');
    this.repositorySelect = page.locator('select[name*="repository"], [class*="repository-select"]');
    this.branchInput = page.locator('input[name="branch"]');
    this.triggerSelect = page.locator('select[name*="trigger"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });

    // Actions
    this.runPipelineButton = page.getByRole('button', { name: /run|trigger|execute/i });
    this.editPipelineButton = page.getByRole('button', { name: /edit/i });
    this.deletePipelineButton = page.getByRole('button', { name: /delete/i });
    this.exportYamlButton = page.getByRole('button', { name: /export|yaml/i });
    this.duplicateButton = page.getByRole('button', { name: /duplicate|copy|clone/i });
  }

  async goto() {
    await this.page.goto('/app/devops/pipelines');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoCreate() {
    await this.page.goto('/app/devops/pipelines/new');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoPipeline(id: string) {
    await this.page.goto(`/app/devops/pipelines/${id}`);
    await this.page.waitForLoadState('networkidle');
  }

  async createPipeline(data: { name: string; description?: string }) {
    await this.createPipelineButton.first().click();
    await this.page.waitForTimeout(500);
    await this.pipelineNameInput.fill(data.name);
    if (data.description) {
      await this.pipelineDescriptionInput.fill(data.description);
    }
    await this.saveButton.first().click();
  }

  async getPipelineCount(): Promise<number> {
    return await this.pipelinesList.count();
  }

  getPipelineRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="card"]:has-text("${name}")`);
  }

  async runPipeline(name: string) {
    const row = this.getPipelineRow(name);
    await row.getByRole('button', { name: /run|trigger|execute/i }).click();
  }

  async viewPipeline(name: string) {
    await this.getPipelineRow(name).click();
    await this.page.waitForLoadState('networkidle');
  }

  async editPipeline(name: string) {
    const row = this.getPipelineRow(name);
    await row.getByRole('button', { name: /edit/i }).click();
  }

  async deletePipeline(name: string) {
    const row = this.getPipelineRow(name);
    await row.getByRole('button', { name: /delete/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async duplicatePipeline(name: string) {
    const row = this.getPipelineRow(name);
    await row.getByRole('button', { name: /duplicate|copy|clone/i }).click();
  }

  async exportYaml(name: string) {
    const row = this.getPipelineRow(name);
    await row.getByRole('button', { name: /export|yaml/i }).click();
  }

  async filterByStatus(status: 'all' | 'active' | 'inactive') {
    if (status === 'all') await this.allTab.click();
    else if (status === 'active') await this.activeTab.click();
    else await this.inactiveTab.click();
    await this.page.waitForTimeout(500);
  }

  async searchPipelines(query: string) {
    await this.searchInput.fill(query);
    await this.page.waitForTimeout(500);
  }
}
