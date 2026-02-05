import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_PROMPT_TEMPLATE } from '../../fixtures/test-data';

/**
 * AI Prompts Page Object Model
 *
 * Encapsulates prompt template management interactions for Playwright tests.
 * Supports template listing, creation, editing, preview, and category filtering.
 */
export class PromptsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly templateList: Locator;
  readonly createTemplateButton: Locator;
  readonly refreshButton: Locator;
  readonly searchInput: Locator;

  // Category Filter Tabs
  readonly allCategoryTab: Locator;
  readonly generalCategoryTab: Locator;
  readonly agentCategoryTab: Locator;
  readonly workflowCategoryTab: Locator;

  // Create/Edit Form
  readonly nameInput: Locator;
  readonly descriptionInput: Locator;
  readonly contentInput: Locator;
  readonly categorySelect: Locator;
  readonly saveButton: Locator;
  readonly cancelButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.templateList = page.locator('[class*="card"], [class*="Card"], [class*="template"]');
    this.createTemplateButton = page.getByRole('button', { name: /create template|create|new/i });
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');

    // Category tabs
    this.allCategoryTab = page.getByRole('button', { name: /^all$/i });
    this.generalCategoryTab = page.getByRole('button', { name: /general/i });
    this.agentCategoryTab = page.getByRole('button', { name: /agent/i });
    this.workflowCategoryTab = page.getByRole('button', { name: /workflow/i });

    // Form inputs
    this.nameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.descriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.contentInput = page.locator('textarea[name="content"], textarea[name="template"], textarea[placeholder*="prompt" i]');
    this.categorySelect = page.locator('select[name="category"], [name="category"]');
    this.saveButton = page.getByRole('button', { name: /save|create|submit/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });
  }

  /**
   * Navigate to prompts page
   */
  async goto() {
    await this.page.goto(ROUTES.prompts);
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
    await expect(this.page.locator('body')).toContainText(/prompt/i);
  }

  /**
   * Click create template button
   */
  async clickCreateTemplate() {
    await this.createTemplateButton.click();
  }

  /**
   * Verify editor/form is open
   */
  async verifyEditorOpen() {
    await expect(
      this.page.locator('[role="dialog"], [class*="modal"], form, [class*="editor"]')
    ).toBeVisible();
  }

  /**
   * Fill template form
   */
  async fillTemplateForm(data: Partial<typeof TEST_PROMPT_TEMPLATE> = TEST_PROMPT_TEMPLATE) {
    if (data.name) {
      await this.nameInput.fill(data.name);
    }
    if (data.content) {
      await this.contentInput.fill(data.content);
    }
    if (data.description) {
      await this.descriptionInput.fill(data.description);
    }
  }

  /**
   * Save template form
   */
  async saveTemplate() {
    await this.saveButton.click();
  }

  /**
   * Cancel template form
   */
  async cancelForm() {
    await this.cancelButton.click();
  }

  /**
   * Create a new template
   */
  async createTemplate(data: Partial<typeof TEST_PROMPT_TEMPLATE> = TEST_PROMPT_TEMPLATE) {
    await this.clickCreateTemplate();
    await this.page.waitForTimeout(500);
    await this.fillTemplateForm(data);
    await this.saveTemplate();
  }

  /**
   * Filter by category
   */
  async filterByCategory(category: 'All' | 'General' | 'Agent' | 'Workflow') {
    switch (category) {
      case 'All':
        await this.allCategoryTab.click();
        break;
      case 'General':
        await this.generalCategoryTab.click();
        break;
      case 'Agent':
        await this.agentCategoryTab.click();
        break;
      case 'Workflow':
        await this.workflowCategoryTab.click();
        break;
    }
  }

  /**
   * Get template card by name
   */
  getTemplateCard(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), [class*="Card"]:has-text("${name}")`);
  }

  /**
   * Click on a template card to edit
   */
  async openTemplateEditor(name: string) {
    const card = this.getTemplateCard(name);
    await card.click();
  }

  /**
   * Click preview on a template
   */
  async clickPreview(name: string) {
    const card = this.getTemplateCard(name);
    const previewButton = card.getByRole('button', { name: /preview/i });
    await previewButton.click();
  }

  /**
   * Search templates
   */
  async search(query: string) {
    await this.searchInput.first().fill(query);
  }

  /**
   * Clear search
   */
  async clearSearch() {
    await this.searchInput.first().clear();
  }

  /**
   * Get count of visible template cards
   */
  async getTemplateCount(): Promise<number> {
    return await this.templateList.count();
  }

  /**
   * Verify empty state
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No prompt templates"), :text("Create your first"), :text("no templates")')
    ).toBeVisible();
  }

  /**
   * Refresh template list
   */
  async refresh() {
    if (await this.refreshButton.count() > 0) {
      await this.refreshButton.click();
    }
  }
}
