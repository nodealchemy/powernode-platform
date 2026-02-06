import { Page, Locator, expect } from '@playwright/test';

/**
 * Knowledge Base Page Object Model
 *
 * Matches actual DOM structure:
 * - KnowledgeBasePage: /app/content/kb
 * - KnowledgeBaseAdminPage: /app/content/kb/admin
 * - KnowledgeBaseArticleEditor: /app/content/kb/articles/new
 * - KnowledgeBaseArticlePage: /app/content/kb/articles/:id
 */
export class KnowledgeBasePage {
  readonly page: Page;

  // Main KB page locators
  readonly createArticleButton: Locator;
  readonly articlesList: Locator;
  readonly searchInput: Locator;
  readonly filtersButton: Locator;
  readonly categoryFilterSelect: Locator;
  readonly pageTitle: Locator;
  readonly emptyState: Locator;

  // Article Editor locators (on /app/content/kb/articles/new)
  readonly articleTitleInput: Locator;
  readonly articleContentEditor: Locator;
  readonly categorySelect: Locator;
  readonly tagsInput: Locator;
  readonly publishButton: Locator;
  readonly saveDraftButton: Locator;
  readonly cancelButton: Locator;
  readonly editorTabs: Locator;

  // Admin page locators
  readonly adminSearchInput: Locator;
  readonly adminFiltersButton: Locator;
  readonly adminArticleRows: Locator;

  constructor(page: Page) {
    this.page = page;

    // Main KB page - PageContainer renders "Create Article" action with data-testid
    this.createArticleButton = page.locator(
      '[data-testid="action-create-article"], button[aria-label="Create Article"]'
    );

    // KbArticleList renders Link elements pointing to /app/content/kb/articles/
    this.articlesList = page.locator('a[href*="/app/content/kb/articles/"]');

    // KbSearchBar search input
    this.searchInput = page.locator(
      'input[placeholder*="Search articles"], input[placeholder*="search" i]'
    );

    // "Filters" button in KbSearchBar
    this.filtersButton = page.getByRole('button', { name: /filters/i });

    // Category select inside KbSearchBar filter panel
    this.categoryFilterSelect = page.locator(
      'select:has(option:text("All Categories"))'
    );

    // Page title rendered by PageContainer
    this.pageTitle = page.locator('h1');

    // Empty state text from KbArticleList
    this.emptyState = page.getByText(/no articles found|check back later/i);

    // --- Article Editor (full page at /app/content/kb/articles/new) ---
    this.articleTitleInput = page.locator('input[placeholder="Enter article title"]');
    this.articleContentEditor = page.locator(
      '.w-md-editor, [class*="w-md-editor"], [data-color-mode]'
    );
    this.categorySelect = page.locator('select.select-theme');
    this.tagsInput = page.locator('input[placeholder*="tag" i]');
    this.publishButton = page.getByRole('button', { name: /publish/i });
    this.saveDraftButton = page.getByRole('button', { name: /save draft/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });
    this.editorTabs = page.locator('button.capitalize, button:has-text("editor"), button:has-text("settings")');

    // --- Admin page locators ---
    this.adminSearchInput = page.locator('input[placeholder*="Search articles"]');
    this.adminFiltersButton = page.getByRole('button', { name: /filters/i });
    this.adminArticleRows = page.locator('input[type="checkbox"]').locator('..');
  }

  async goto() {
    await this.page.goto('/app/content/kb');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoAdmin() {
    await this.page.goto('/app/content/kb/admin');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoNewArticle() {
    await this.page.goto('/app/content/kb/articles/new');
    await this.page.waitForLoadState('networkidle');
  }

  async waitForReady() {
    // Wait for loading spinner to disappear
    await this.page.waitForLoadState('networkidle');
    await this.page.locator('.animate-spin').waitFor({ state: 'hidden', timeout: 10000 }).catch(() => {});
  }

  async verifyPageLoaded() {
    await expect(this.pageTitle.first()).toBeVisible();
  }

  async searchArticles(query: string) {
    const input = this.searchInput.first();
    await input.fill(query);
    // KbSearchBar auto-debounces at 300ms
    await this.page.waitForTimeout(500);
  }

  async openFilters() {
    const filtersBtn = this.filtersButton.first();
    if (await filtersBtn.isVisible()) {
      await filtersBtn.click();
      await this.page.waitForTimeout(300);
    }
  }

  async filterByCategory(categoryName: string) {
    await this.openFilters();
    const select = this.categoryFilterSelect.first();
    if (await select.isVisible()) {
      await select.selectOption({ label: new RegExp(categoryName) });
      await this.page.waitForTimeout(500);
    }
  }

  async getArticleCount(): Promise<number> {
    return await this.articlesList.count();
  }

  async clickEditorTab(tabName: string) {
    const tab = this.page.locator(`button.capitalize:has-text("${tabName}"), button:text-is("${tabName}")`);
    if (await tab.count() > 0) {
      await tab.first().click();
      await this.page.waitForTimeout(300);
    }
  }
}
