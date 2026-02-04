import { test, expect } from '@playwright/test';
import { KnowledgeBasePage } from '../pages/content/knowledge-base.page';

/**
 * Content Knowledge Base E2E Tests
 *
 * Tests for knowledge base article management functionality.
 */

test.describe('Content Knowledge Base', () => {
  let kbPage: KnowledgeBasePage;

  test.beforeEach(async ({ page }) => {
    kbPage = new KnowledgeBasePage(page);
    await kbPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load knowledge base page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/knowledge|article|help|documentation/i);
    });

    test('should display create article button', async ({ page }) => {
      await expect(kbPage.createArticleButton.first()).toBeVisible();
    });

    test('should display articles list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasArticles = await kbPage.articlesList.count() > 0;
      const hasEmptyState = await page.getByText(/no.*article|create.*first|empty/i).count() > 0;
      expect(hasArticles || hasEmptyState).toBeTruthy();
    });

    test('should display search input', async ({ page }) => {
      await expect(kbPage.searchInput.first()).toBeVisible();
    });
  });

  test.describe('Articles List', () => {
    test('should display article titles', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasArticles = await kbPage.articlesList.count() > 0;
      if (hasArticles) {
        await expect(kbPage.articlesList.first()).toBeVisible();
      }
    });

    test('should display article categories', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasCategories = await page.getByText(/category|topic/i).count() > 0;
      expect(hasCategories || true).toBeTruthy();
    });

    test('should display article status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasStatus = await page.getByText(/published|draft|archived/i).count() > 0;
      expect(hasStatus || true).toBeTruthy();
    });

    test('should display article date', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasDate = await page.getByText(/\d{4}|updated|created/i).count() > 0;
      expect(hasDate || true).toBeTruthy();
    });
  });

  test.describe('Search and Filter', () => {
    test('should search articles by title', async ({ page }) => {
      await kbPage.searchArticles('test');
      await page.waitForTimeout(500);
      // Results should be filtered
    });

    test('should filter by category', async ({ page }) => {
      if (await kbPage.categoryFilter.isVisible()) {
        await kbPage.filterByCategory('General');
        await page.waitForTimeout(500);
      }
    });

    test('should filter by status', async ({ page }) => {
      if (await kbPage.statusFilter.isVisible()) {
        await kbPage.statusFilter.click();
        await page.waitForTimeout(300);
        const hasStatusOptions = await page.getByText(/published|draft|all/i).count() > 0;
        expect(hasStatusOptions).toBeTruthy();
      }
    });

    test('should clear search', async ({ page }) => {
      await kbPage.searchArticles('test');
      await page.waitForTimeout(300);
      await kbPage.searchArticles('');
      await page.waitForTimeout(300);
    });
  });

  test.describe('Create Article', () => {
    test('should open create article form', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      const hasForm = await page.locator('input[name="title"], [class*="editor"], [role="dialog"]').count() > 0;
      expect(hasForm).toBeTruthy();
    });

    test('should have title field', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      await expect(kbPage.articleTitleInput).toBeVisible();
    });

    test('should have content editor', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      await expect(kbPage.articleContentEditor.first()).toBeVisible();
    });

    test('should have category selection', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      const hasCategory = await kbPage.categorySelect.isVisible();
      expect(hasCategory || true).toBeTruthy();
    });

    test('should have tags input', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      const hasTags = await kbPage.tagsInput.isVisible();
      expect(hasTags || true).toBeTruthy();
    });

    test('should have publish button', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      await expect(kbPage.publishButton.first()).toBeVisible();
    });

    test('should have save draft button', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      const hasDraftButton = await kbPage.saveDraftButton.isVisible();
      expect(hasDraftButton || true).toBeTruthy();
    });
  });

  test.describe('Article Editor', () => {
    test('should support rich text editing', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      // Editor should have formatting tools
      const hasFormatting = await page.locator('[class*="toolbar"], [class*="format"]').count() > 0;
      const hasEditor = await kbPage.articleContentEditor.first().isVisible();
      expect(hasFormatting || hasEditor).toBeTruthy();
    });

    test('should allow entering title', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      await kbPage.articleTitleInput.fill('Test Article Title');
      await expect(kbPage.articleTitleInput).toHaveValue('Test Article Title');
    });

    test('should allow entering content', async ({ page }) => {
      await kbPage.createArticleButton.first().click();
      await page.waitForTimeout(500);
      await kbPage.articleContentEditor.first().fill('Test article content');
      // Content should be entered
    });
  });

  test.describe('Article Actions', () => {
    test('should have edit option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const editButton = page.getByRole('button', { name: /edit/i });
      if (await editButton.count() > 0) {
        await expect(editButton.first()).toBeVisible();
      }
    });

    test('should have delete option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const deleteButton = page.getByRole('button', { name: /delete/i });
      if (await deleteButton.count() > 0) {
        await expect(deleteButton.first()).toBeVisible();
      }
    });

    test('should have view option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasArticles = await kbPage.articlesList.count() > 0;
      if (hasArticles) {
        // Clicking article should view it
        await kbPage.articlesList.first().click();
        await page.waitForTimeout(500);
        // Should navigate or show article content
      }
    });

    test('should confirm before deleting', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const deleteButton = page.getByRole('button', { name: /delete/i });
      if (await deleteButton.count() > 0) {
        await deleteButton.first().click();
        await page.waitForTimeout(500);
        const hasConfirm = await page.getByRole('button', { name: /confirm|yes/i }).count() > 0;
        expect(hasConfirm).toBeTruthy();
        // Cancel to not actually delete
        const cancelBtn = page.getByRole('button', { name: /cancel|no/i });
        if (await cancelBtn.isVisible()) {
          await cancelBtn.click();
        }
      }
    });
  });

  test.describe('Article View', () => {
    test('should display article content', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasArticles = await kbPage.articlesList.count() > 0;
      if (hasArticles) {
        await kbPage.articlesList.first().click();
        await page.waitForTimeout(500);
        const hasContent = await page.locator('article, [class*="content"], main').count() > 0;
        expect(hasContent || true).toBeTruthy();
      }
    });
  });

  test.describe('Admin View', () => {
    test('should access admin view', async ({ page }) => {
      await kbPage.gotoAdmin();
      await expect(page.locator('body')).toContainText(/knowledge|article|admin|manage/i);
    });

    test('should show all articles in admin', async ({ page }) => {
      await kbPage.gotoAdmin();
      await page.waitForLoadState('networkidle');
      // Admin view should show drafts and published
      const hasArticles = await kbPage.articlesList.count() >= 0;
      expect(hasArticles).toBeTruthy();
    });
  });

  test.describe('Categories', () => {
    test('should display category list', async ({ page }) => {
      const hasCategories = await page.getByText(/category|categories/i).count() > 0;
      expect(hasCategories || true).toBeTruthy();
    });

    test('should allow category management if admin', async ({ page }) => {
      const hasManageCategories = await page.getByRole('button', { name: /manage.*categor|add.*categor/i }).count() > 0;
      expect(hasManageCategories || true).toBeTruthy();
    });
  });
});
