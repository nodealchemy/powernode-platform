import { Page, Locator } from '@playwright/test';

/**
 * System Modules Page Object Model
 *
 * Routes the operator UI for /app/system/modules where module list +
 * detail modals + autonomy controls (consent budget + canary marker)
 * are exercised.
 *
 * Tolerant of empty data — uses `data-testid` first, then falls back to
 * role-based + class-pattern selectors per the project's e2e selector
 * priority memo.
 */
export class ModulesPage {
  readonly page: Page;
  readonly pageHeading: Locator;
  readonly createButton: Locator;
  readonly moduleRows: Locator;
  readonly detailModal: Locator;
  readonly modalHeading: Locator;
  readonly autonomyTab: Locator;
  readonly canaryMarker: Locator;
  readonly consentBudgetEditor: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageHeading = page.getByRole('heading', { name: /modules/i }).first();
    this.createButton = page.getByRole('button', { name: /create module|new module/i });
    this.moduleRows = page.locator('tr[data-testid^="module-row"], [data-testid^="module-card"]');
    this.detailModal = page.locator('[role="dialog"], [class*="modal"]').filter({ hasText: /module/i }).first();
    this.modalHeading = this.detailModal.getByRole('heading').first();
    this.autonomyTab = this.detailModal.getByRole('tab', { name: /autonomy|canary|consent/i });
    this.canaryMarker = this.detailModal.locator('[data-testid="canary-marker"], [class*="canary"]').first();
    this.consentBudgetEditor = this.detailModal.locator('[data-testid="consent-budget-editor"], [class*="consent"]').first();
  }

  async goto() {
    await this.page.goto('/app/system/modules');
    await this.waitForPageReady();
  }

  async waitForPageReady() {
    // Heading + either the empty state or at least one module item
    await this.pageHeading.waitFor({ state: 'visible', timeout: 10_000 }).catch(() => {});
  }

  /** Returns the count of visible module rows; 0 when the list is empty. */
  async moduleCount(): Promise<number> {
    return this.moduleRows.count();
  }

  /** Click the first module's name/view action to open the detail modal. */
  async openFirstModuleDetail(): Promise<boolean> {
    const count = await this.moduleCount();
    if (count === 0) return false;
    // Module names are clickable links/buttons inside the row
    const firstNameLink = this.moduleRows.first().getByRole('link').or(
      this.moduleRows.first().getByRole('button')
    ).first();
    await firstNameLink.click();
    await this.detailModal.waitFor({ state: 'visible', timeout: 5_000 }).catch(() => {});
    return this.detailModal.isVisible();
  }
}
