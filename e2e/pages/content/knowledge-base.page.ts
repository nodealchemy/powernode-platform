import { Page, Locator, expect } from '@playwright/test';

/**
 * Knowledge Base Page Object Model
 */
export class KnowledgeBasePage {
  readonly page: Page;
  readonly createArticleButton: Locator;
  readonly articlesList: Locator;
  readonly searchInput: Locator;
  readonly categoryFilter: Locator;
  readonly statusFilter: Locator;

  // Article Editor
  readonly articleTitleInput: Locator;
  readonly articleContentEditor: Locator;
  readonly categorySelect: Locator;
  readonly tagsInput: Locator;
  readonly publishButton: Locator;
  readonly saveDraftButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.createArticleButton = page.getByRole('button', { name: /create|new article/i });
    this.articlesList = page.locator('table tbody tr, [class*="article-card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.categoryFilter = page.locator('select[name*="category"], button:has-text("Category")');
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');

    this.articleTitleInput = page.locator('input[name="title"]');
    this.articleContentEditor = page.locator('[class*="editor"], [contenteditable="true"], textarea[name="content"]');
    this.categorySelect = page.locator('select[name="category"]');
    this.tagsInput = page.locator('input[name="tags"]');
    this.publishButton = page.getByRole('button', { name: /publish/i });
    this.saveDraftButton = page.getByRole('button', { name: /save draft/i });
  }

  async goto() {
    await this.page.goto('/app/content/knowledge-base');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoAdmin() {
    await this.page.goto('/app/content/kb-admin');
    await this.page.waitForLoadState('networkidle');
  }

  async createArticle(title: string, content: string, category?: string) {
    await this.createArticleButton.click();
    await this.articleTitleInput.fill(title);
    await this.articleContentEditor.fill(content);
    if (category) {
      await this.categorySelect.selectOption(category);
    }
    await this.publishButton.click();
  }

  async searchArticles(query: string) {
    await this.searchInput.fill(query);
    await this.searchInput.press('Enter');
  }

  async getArticleCount(): Promise<number> {
    return await this.articlesList.count();
  }

  getArticleRow(title: string): Locator {
    return this.page.locator(`tr:has-text("${title}"), [class*="article"]:has-text("${title}")`);
  }

  async viewArticle(title: string) {
    await this.getArticleRow(title).click();
  }

  async editArticle(title: string) {
    const row = this.getArticleRow(title);
    await row.getByRole('button', { name: /edit/i }).click();
  }

  async deleteArticle(title: string) {
    const row = this.getArticleRow(title);
    await row.getByRole('button', { name: /delete/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async filterByCategory(category: string) {
    await this.categoryFilter.click();
    await this.page.getByText(category).click();
  }
}
