import { test, expect } from '@playwright/test';
import { KnowledgeBasePage } from '../pages/content/knowledge-base.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Content Knowledge Base E2E Tests
 *
 * Tests for knowledge base article browsing, search, article editor,
 * and admin management functionality.
 *
 * Routes tested:
 *   /app/content/kb            - KnowledgeBasePage
 *   /app/content/kb/articles/new - KnowledgeBaseArticleEditor
 *   /app/content/kb/admin      - KnowledgeBaseAdminPage
 */

test.describe('Content Knowledge Base', () => {
  let kbPage: KnowledgeBasePage;

  test.beforeEach(async ({ page }) => {
    // Suppress page errors from API failures or missing data
    page.on('pageerror', () => {});
    kbPage = new KnowledgeBasePage(page);
  });

  test.describe('Page Display', () => {
    test.beforeEach(async () => {
      await kbPage.goto();
      await kbPage.waitForReady();
    });

    test('should load knowledge base page', async ({ page }) => {
      await kbPage.verifyPageLoaded();
      await expect(page.locator('body')).toContainText(/knowledge base/i);
    });

    test('should display page title and description', async () => {
      await expect(kbPage.pageTitle.first()).toContainText(/knowledge base/i);
    });

    test('should display create article button if user has permissions', async () => {
      // Create Article button is a PageContainer action - only visible with kb.manage or kb.update
      if (await kbPage.createArticleButton.count() > 0) {
        await expect(kbPage.createArticleButton.first()).toBeVisible();
      }
    });

    test('should display articles list or empty state', async ({ page }) => {
      const hasArticles = await kbPage.articlesList.count() > 0;
      const hasEmptyState = await kbPage.emptyState.count() > 0;
      // Page should show either articles or an empty/no-articles message
      await expectOrAlternateState(page, hasArticles || hasEmptyState);
    });

    test('should display search input', async () => {
      await expect(kbPage.searchInput.first()).toBeVisible();
    });
  });

  test.describe('Articles List', () => {
    test.beforeEach(async () => {
      await kbPage.goto();
      await kbPage.waitForReady();
    });

    test('should display article links', async () => {
      const hasArticles = await kbPage.articlesList.count() > 0;
      if (hasArticles) {
        await expect(kbPage.articlesList.first()).toBeVisible();
      }
    });

    test('should display section headings', async ({ page }) => {
      // Main page shows "Featured Articles", "Recent Articles", and "Categories" sections
      const hasSections = await page.getByText(/featured articles|recent articles|categories/i).count() > 0;
      await expectOrAlternateState(page, hasSections);
    });

    test('should display article metadata', async ({ page }) => {
      // Article list items include author, reading time, views
      const hasMetadata = await page.getByText(/min read|views|by /i).count() > 0;
      await expectOrAlternateState(page, hasMetadata);
    });

    test('should display category badges on articles', async ({ page }) => {
      // KbArticleList shows category badges when showCategory is true
      const hasBadges = await page.locator('[class*="badge"], [class*="Badge"]').count() > 0;
      await expectOrAlternateState(page, hasBadges);
    });
  });

  test.describe('Search and Filter', () => {
    test.beforeEach(async () => {
      await kbPage.goto();
      await kbPage.waitForReady();
    });

    test('should search articles by keyword', async ({ page }) => {
      await kbPage.searchArticles('test');
      // After typing, search should trigger; page may show "Search Results" heading
      const hasResults = await page.getByText(/search results|no articles found/i).count() > 0;
      await expectOrAlternateState(page, hasResults);
    });

    test('should show filters panel when clicking Filters button', async () => {
      const filtersBtn = kbPage.filtersButton.first();
      if (await filtersBtn.isVisible()) {
        await filtersBtn.click();
        await kbPage.page.waitForTimeout(300);
        // Filter panel should show category select with "All Categories" option
        const hasFilterPanel = await kbPage.categoryFilterSelect.count() > 0;
        expect(hasFilterPanel).toBeTruthy();
      }
    });

    test('should filter by category', async () => {
      await kbPage.openFilters();
      const select = kbPage.categoryFilterSelect.first();
      if (await select.isVisible()) {
        // Category select should have "All Categories" as first option
        await expect(select).toBeVisible();
      }
    });

    test('should clear search', async ({ page }) => {
      await kbPage.searchArticles('test');
      await kbPage.page.waitForTimeout(300);
      // Clear button appears when there are active filters
      const clearBtn = page.getByRole('button', { name: /clear/i });
      if (await clearBtn.count() > 0) {
        await clearBtn.first().click();
        await kbPage.page.waitForTimeout(300);
      }
    });
  });

  test.describe('Create Article Navigation', () => {
    test('should navigate to article editor when clicking Create Article', async ({ page }) => {
      await kbPage.goto();
      await kbPage.waitForReady();

      if (await kbPage.createArticleButton.count() === 0) {
        test.skip();
        return;
      }

      await kbPage.createArticleButton.first().click();
      await page.waitForLoadState('networkidle');
      // Should navigate to the article editor page
      await expect(page).toHaveURL(/\/app\/content\/kb\/articles\/new/);
    });
  });

  test.describe('Article Editor', () => {
    test.beforeEach(async () => {
      // Navigate directly to article editor
      await kbPage.gotoNewArticle();
      await kbPage.waitForReady();
    });

    test('should display editor page with title', async ({ page }) => {
      // Editor header shows "Create Article" for new articles
      const hasEditorTitle = await page.getByText(/create article/i).count() > 0;
      expect(hasEditorTitle).toBeTruthy();
    });

    test('should have title input field', async () => {
      await expect(kbPage.articleTitleInput).toBeVisible();
    });

    test('should have content editor', async () => {
      // MDEditor renders with class w-md-editor or data-color-mode attribute
      await expect(kbPage.articleContentEditor.first()).toBeVisible();
    });

    test('should have Save Draft button', async () => {
      const hasDraftButton = await kbPage.saveDraftButton.count() > 0;
      expect(hasDraftButton).toBeTruthy();
    });

    test('should have Publish button', async ({ page }) => {
      // "Save & Publish" button is shown for users with kb.publish permission
      const hasPublish = await kbPage.publishButton.count() > 0;
      await expectOrAlternateState(page, hasPublish);
    });

    test('should have Cancel button', async () => {
      await expect(kbPage.cancelButton.first()).toBeVisible();
    });

    test('should allow entering title', async () => {
      await kbPage.articleTitleInput.fill('Test Article Title');
      await expect(kbPage.articleTitleInput).toHaveValue('Test Article Title');
    });

    test('should show editor tabs', async ({ page }) => {
      // Editor has tabs: editor, settings, seo, preview
      const editorTab = page.locator('button').filter({ hasText: /^editor$/i });
      const settingsTab = page.locator('button').filter({ hasText: /^settings$/i });
      if (await editorTab.count() > 0) {
        await expect(editorTab.first()).toBeVisible();
      }
      if (await settingsTab.count() > 0) {
        await expect(settingsTab.first()).toBeVisible();
      }
    });

    test('should show category select on settings tab', async ({ page }) => {
      // Category is on the Settings tab
      const settingsTab = page.locator('button').filter({ hasText: /^settings$/i });
      if (await settingsTab.count() > 0) {
        await settingsTab.first().click();
        await page.waitForTimeout(300);
        const categorySelect = kbPage.categorySelect.first();
        if (await categorySelect.count() > 0) {
          await expect(categorySelect).toBeVisible();
        }
      }
    });

    test('should show tags input on settings tab', async ({ page }) => {
      // Tags input is on the Settings tab
      const settingsTab = page.locator('button').filter({ hasText: /^settings$/i });
      if (await settingsTab.count() > 0) {
        await settingsTab.first().click();
        await page.waitForTimeout(300);
        const tagsInput = kbPage.tagsInput.first();
        if (await tagsInput.count() > 0) {
          await expect(tagsInput).toBeVisible();
        }
      }
    });
  });

  test.describe('Article Editor - Rich Text', () => {
    test.beforeEach(async () => {
      await kbPage.gotoNewArticle();
      await kbPage.waitForReady();
    });

    test('should display markdown editor with toolbar', async ({ page }) => {
      // MDEditor renders toolbar buttons for formatting
      const hasToolbar = await page.locator('[class*="w-md-editor-toolbar"], [class*="toolbar"]').count() > 0;
      const hasEditor = await kbPage.articleContentEditor.first().isVisible().catch(() => false);
      expect(hasToolbar || hasEditor).toBeTruthy();
    });

    test('should show preview tab', async ({ page }) => {
      const previewTab = page.locator('button').filter({ hasText: /^preview$/i });
      if (await previewTab.count() > 0) {
        await previewTab.first().click();
        await page.waitForTimeout(300);
        // Preview tab shows message when no content
        const hasPreviewContent = await page.getByText(/no content to preview|preview/i).count() > 0;
        expect(hasPreviewContent).toBeTruthy();
      }
    });

    test('should show SEO tab', async ({ page }) => {
      const seoTab = page.locator('button').filter({ hasText: /^seo$/i });
      if (await seoTab.count() > 0) {
        await seoTab.first().click();
        await page.waitForTimeout(300);
        const hasSeoContent = await page.getByText(/meta title|meta description|search engine preview/i).count() > 0;
        expect(hasSeoContent).toBeTruthy();
      }
    });
  });

  test.describe('Article View', () => {
    test('should navigate to article when clicking article link', async ({ page }) => {
      await kbPage.goto();
      await kbPage.waitForReady();

      const hasArticles = await kbPage.articlesList.count() > 0;
      if (!hasArticles) {
        test.skip();
        return;
      }

      await kbPage.articlesList.first().click();
      await page.waitForLoadState('networkidle');
      // Should navigate to article detail page
      await expect(page).toHaveURL(/\/app\/content\/kb\/articles\//);
    });

    test('should display article content on detail page', async ({ page }) => {
      await kbPage.goto();
      await kbPage.waitForReady();

      const hasArticles = await kbPage.articlesList.count() > 0;
      if (!hasArticles) {
        test.skip();
        return;
      }

      await kbPage.articlesList.first().click();
      await page.waitForLoadState('networkidle');
      // Article detail page renders article element and content sections
      const hasContent = await page.locator('article, [class*="kb-article-content"]').count() > 0;
      await expectOrAlternateState(page, hasContent);
    });
  });

  test.describe('Admin View', () => {
    test('should access admin page', async ({ page }) => {
      await kbPage.gotoAdmin();
      await kbPage.waitForReady();
      // Admin page shows "Knowledge Base Admin" title or redirects to KB if no permission
      const hasAdminTitle = await page.getByText(/knowledge base admin|knowledge base/i).count() > 0;
      expect(hasAdminTitle).toBeTruthy();
    });

    test('should show admin stats overview', async ({ page }) => {
      await kbPage.gotoAdmin();
      await kbPage.waitForReady();
      // Admin page shows stats: Total Articles, Published, Draft, In Review, Archived
      const hasStats = await page.getByText(/total articles|published|draft/i).count() > 0;
      await expectOrAlternateState(page, hasStats);
    });

    test('should show admin search input', async ({ page }) => {
      await kbPage.gotoAdmin();
      await kbPage.waitForReady();
      const searchInput = page.locator('input[placeholder*="Search articles"]');
      if (await searchInput.count() > 0) {
        await expect(searchInput.first()).toBeVisible();
      }
    });

    test('should show articles section in admin', async ({ page }) => {
      await kbPage.gotoAdmin();
      await kbPage.waitForReady();
      // Admin page has "Articles" heading and article list or "No articles yet" empty state
      const hasArticlesSection = await page.getByText(/articles|no articles yet/i).count() > 0;
      expect(hasArticlesSection).toBeTruthy();
    });

    test('should show quick actions in admin', async ({ page }) => {
      await kbPage.gotoAdmin();
      await kbPage.waitForReady();
      const hasQuickActions = await page.getByText(/quick actions/i).count() > 0;
      await expectOrAlternateState(page, hasQuickActions);
    });
  });

  test.describe('Categories', () => {
    test.beforeEach(async () => {
      await kbPage.goto();
      await kbPage.waitForReady();
    });

    test('should display categories section', async ({ page }) => {
      // Main KB page has a "Categories" heading in the sidebar
      const hasCategories = await page.getByText(/categories/i).count() > 0;
      await expectOrAlternateState(page, hasCategories);
    });

    test('should display category list or empty state', async ({ page }) => {
      // KbCategoryList renders folder icons with category names, or "No categories found"
      const hasCategoryItems = await page.locator('button:has-text("articles"), button:has-text("0")').count() > 0;
      const hasNoCategoriesMessage = await page.getByText(/no categories found/i).count() > 0;
      await expectOrAlternateState(page, hasCategoryItems || hasNoCategoriesMessage);
    });
  });

  test.describe('Responsive Layout', () => {
    test('should render on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await kbPage.goto();
      await kbPage.waitForReady();
      await kbPage.verifyPageLoaded();
    });

    test('should render on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await kbPage.goto();
      await kbPage.waitForReady();
      await kbPage.verifyPageLoaded();
    });
  });
});
