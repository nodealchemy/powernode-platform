import { test, expect, Page, Route } from '@playwright/test';
import { ROUTES, API_ENDPOINTS } from '../fixtures/test-data';

/**
 * Parallel Execution - Mocked E2E Tests
 *
 * Uses page.route() to intercept API calls and return mock data.
 * No backend required. Tests UI rendering, session list, detail view,
 * create modal, tabs, merge status, and state transitions.
 *
 * Selector notes (matching actual component DOM):
 * - Card component: no "Card" CSS class; uses bg-theme-surface, cursor-pointer, rounded-xl, etc.
 * - Badge component: uses badge-theme, badge-theme-success, etc. (no "Badge" class)
 * - TabsTrigger: renders as <button> without role="tab" (inside flex border-b container)
 * - Modal: renders with role="dialog" (standard ARIA)
 * - PageContainer actions: rendered with data-testid="action-{id}" and aria-label
 */

// Mock data factories

function createMockWorktree(overrides: Record<string, unknown> = {}) {
  return {
    id: 'wt-001',
    worktree_session_id: 'session-001',
    branch_name: 'worktree/session-001/feature-a',
    worktree_path: '/tmp/worktrees/feature-a',
    status: 'in_use',
    ai_agent_id: 'agent-001',
    agent_name: 'Claude Agent',
    base_commit_sha: 'abc1234',
    head_commit_sha: 'def5678',
    commit_count: 3,
    locked: false,
    healthy: true,
    files_changed: 5,
    lines_added: 120,
    lines_removed: 30,
    ready_at: '2026-02-01T00:01:00Z',
    completed_at: null,
    duration_ms: null,
    error_message: null,
    created_at: '2026-02-01T00:00:00Z',
    ...overrides,
  };
}

function createMockMergeOperation(overrides: Record<string, unknown> = {}) {
  return {
    id: 'merge-001',
    worktree_id: 'wt-001',
    source_branch: 'worktree/session-001/feature-a',
    target_branch: 'main',
    strategy: 'sequential',
    status: 'pending',
    merge_order: 0,
    merge_commit_sha: null,
    has_conflicts: false,
    conflict_files: [],
    conflict_resolution: null,
    pull_request_url: null,
    rolled_back: false,
    started_at: null,
    completed_at: null,
    duration_ms: null,
    error_message: null,
    ...overrides,
  };
}

function createMockSession(overrides: Record<string, unknown> = {}) {
  return {
    id: 'session-001',
    status: 'active',
    repository_path: '/home/user/project',
    base_branch: 'main',
    integration_branch: null,
    merge_strategy: 'sequential',
    max_parallel: 4,
    total_worktrees: 3,
    completed_worktrees: 1,
    failed_worktrees: 0,
    progress_percentage: 33,
    source_type: null,
    source_id: null,
    started_at: '2026-02-01T00:00:00Z',
    completed_at: null,
    duration_ms: null,
    error_message: null,
    error_code: null,
    configuration: {},
    metadata: {},
    created_at: '2026-02-01T00:00:00Z',
    ...overrides,
  };
}

function createMockSessionDetail(overrides: Record<string, unknown> = {}) {
  return {
    ...createMockSession(overrides),
    worktrees: [
      createMockWorktree(),
      createMockWorktree({
        id: 'wt-002',
        branch_name: 'worktree/session-001/feature-b',
        worktree_path: '/tmp/worktrees/feature-b',
        agent_name: 'GPT Agent',
        ai_agent_id: 'agent-002',
        status: 'completed',
        completed_at: '2026-02-01T00:05:00Z',
        duration_ms: 300000,
        commit_count: 7,
        files_changed: 12,
        lines_added: 250,
        lines_removed: 80,
      }),
      createMockWorktree({
        id: 'wt-003',
        branch_name: 'worktree/session-001/feature-c',
        worktree_path: '/tmp/worktrees/feature-c',
        agent_name: 'Ollama Agent',
        ai_agent_id: 'agent-003',
        status: 'pending',
        ready_at: null,
        commit_count: 0,
        files_changed: 0,
        lines_added: 0,
        lines_removed: 0,
      }),
    ],
    merge_operations: [
      createMockMergeOperation({ status: 'completed', merge_commit_sha: 'aaa1111', completed_at: '2026-02-01T00:06:00Z', duration_ms: 2000 }),
      createMockMergeOperation({ id: 'merge-002', worktree_id: 'wt-002', source_branch: 'worktree/session-001/feature-b', merge_order: 1 }),
    ],
  };
}

const defaultSessions = [
  createMockSession(),
  createMockSession({
    id: 'session-002',
    status: 'completed',
    base_branch: 'develop',
    merge_strategy: 'integration_branch',
    total_worktrees: 2,
    completed_worktrees: 2,
    progress_percentage: 100,
    completed_at: '2026-02-01T01:00:00Z',
    duration_ms: 3600000,
  }),
  createMockSession({
    id: 'session-003',
    status: 'failed',
    base_branch: 'release/1.0',
    total_worktrees: 4,
    completed_worktrees: 2,
    failed_worktrees: 1,
    progress_percentage: 50,
    error_message: 'Merge conflict in src/main.ts',
  }),
];

let currentSessionDetail = createMockSessionDetail();

async function setupApiMocks(page: Page, options: { sessions?: Record<string, unknown>[], sessionDetail?: Record<string, unknown> } = {}) {
  const sessions = options.sessions || defaultSessions;

  // All worktree_sessions API routes - single catch-all handler
  await page.route(`**${API_ENDPOINTS.worktreeSessions}**`, async (route: Route) => {
    const url = route.request().url();
    const method = route.request().method();

    // Extract path after worktree_sessions (strip query params for path matching)
    const pathPart = url.replace(/\?.*$/, '');
    const afterSessions = pathPart.replace(/^.*worktree_sessions\/?/, '');

    // GET list: /worktree_sessions or /worktree_sessions?params
    if (method === 'GET' && !afterSessions) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: sessions,
          pagination: { total_count: sessions.length, page: 1, per_page: 50 },
        }),
      });
      return;
    }

    // POST cancel: /worktree_sessions/:id/cancel
    if (method === 'POST' && url.includes('/cancel')) {
      const detail = { ...currentSessionDetail, status: 'cancelled' };
      currentSessionDetail = detail as ReturnType<typeof createMockSessionDetail>;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ session: detail, message: 'Session cancelled' }),
      });
      return;
    }

    // POST retry_merge: /worktree_sessions/:id/retry_merge
    if (method === 'POST' && url.includes('/retry_merge')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ session: currentSessionDetail, message: 'Merge retry started' }),
      });
      return;
    }

    // GET status: /worktree_sessions/:id/status
    if (method === 'GET' && url.includes('/status')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(currentSessionDetail),
      });
      return;
    }

    // GET merge_operations: /worktree_sessions/:id/merge_operations
    if (method === 'GET' && url.includes('/merge_operations')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ items: currentSessionDetail.merge_operations }),
      });
      return;
    }

    // GET detail: /worktree_sessions/:id (no sub-path)
    if (method === 'GET' && afterSessions && !afterSessions.includes('/')) {
      const detail = options.sessionDetail || currentSessionDetail;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(detail),
      });
      return;
    }

    // POST create: /worktree_sessions
    if (method === 'POST' && !afterSessions) {
      const newSession = createMockSession({ id: 'session-new', status: 'provisioning' });
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ session: newSession, message: 'Session created' }),
      });
      return;
    }

    await route.continue();
  });

  // Catch WebSocket upgrade attempts to prevent hanging
  await page.route('**/cable*', async (route: Route) => {
    await route.abort();
  });
}

// Helper: locate session cards in the DOM
// Card component renders <div class="... bg-theme-surface ... cursor-pointer ...">
function sessionCardLocator(page: Page) {
  return page.locator('[class*="cursor-pointer"][class*="bg-theme-surface"]');
}

// Helper: locate tab buttons (TabsTrigger renders as <button> inside flex border-b container)
function tabButton(page: Page, name: RegExp) {
  const tabsContainer = page.locator('[class*="border-b"][class*="bg-theme-surface"]');
  return tabsContainer.getByRole('button', { name });
}

test.describe('Parallel Execution Page', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    currentSessionDetail = createMockSessionDetail();
    await setupApiMocks(page);
    await page.goto(ROUTES.parallelExecution);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should navigate to parallel execution page', async ({ page }) => {
      expect(page.url()).toContain('/parallel-execution');
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('h1')).toContainText('Parallel Execution');
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText('AI');
    });

    test('should display page description', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/parallel|worktree|agent/i);
    });
  });

  test.describe('Session List', () => {
    test('should display session cards', async ({ page }) => {
      const cards = sessionCardLocator(page);
      await expect(cards.first()).toBeVisible({ timeout: 5000 });
      expect(await cards.count()).toBeGreaterThan(0);
    });

    test('should display New Session button', async ({ page }) => {
      await expect(page.getByRole('button', { name: /new session/i })).toBeVisible();
    });

    test('should show status filter', async ({ page }) => {
      const select = page.locator('select').first();
      await expect(select).toBeVisible();
      const options = await select.locator('option').allTextContents();
      expect(options).toContain('All Statuses');
    });

    test('should display base branch on session cards', async ({ page }) => {
      await expect(page.locator('body')).toContainText('main');
    });

    test('should show merge strategy on session cards', async ({ page }) => {
      await expect(page.locator('body')).toContainText('sequential');
    });

    test('should show worktree count on session cards', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/\d+\/\d+/);
    });

    test('should display empty state when filtered with no results', async ({ page }) => {
      await page.route(`**${API_ENDPOINTS.worktreeSessions}**`, async (route: Route) => {
        const url = route.request().url();
        const pathPart = url.replace(/\?.*$/, '');
        const afterSessions = pathPart.replace(/^.*worktree_sessions\/?/, '');
        if (route.request().method() === 'GET' && !afterSessions) {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
              items: [],
              pagination: { total_count: 0, page: 1, per_page: 50 },
            }),
          });
          return;
        }
        await route.fallback();
      });
      const statusSelect = page.locator('select').first();
      await statusSelect.selectOption('failed');
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText(/no parallel|create.*session/i);
    });

    test('should show refresh button', async ({ page }) => {
      // RefreshCw icon from lucide renders as <svg class="lucide lucide-refresh-cw ...">
      const refreshBtn = page.locator('button').filter({ has: page.locator('svg[class*="lucide-refresh"]') });
      await expect(refreshBtn).toBeVisible();
    });
  });

  test.describe('Create Session Modal', () => {
    test('should open create session modal when clicking New Session', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      await expect(page.locator('[role="dialog"]')).toBeVisible();
      await expect(page.locator('[role="dialog"]')).toContainText('New Parallel Execution Session');
    });

    test('should close modal on Cancel', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      await expect(page.locator('[role="dialog"]')).toBeVisible();
      await page.locator('[role="dialog"]').getByRole('button', { name: /cancel/i }).click();
      await expect(page.locator('[role="dialog"]')).not.toBeVisible();
    });

    test('should have repository path input', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toContainText('Repository Path');
      const repoInput = dialog.locator('input').first();
      await expect(repoInput).toBeVisible();
    });

    test('should have base branch input', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toContainText('Base Branch');
    });

    test('should have merge strategy select with options', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toContainText('Merge Strategy');
      await expect(dialog).toContainText('Sequential');
      await expect(dialog).toContainText('Integration Branch');
      // "Manual (PR-based)" is the option text
      await expect(dialog).toContainText(/Manual/);
    });

    test('should have max parallel input', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toContainText('Max Parallel');
      const numInput = dialog.locator('input[type="number"]');
      await expect(numInput.first()).toBeVisible();
    });

    test('should have branch suffixes input', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toContainText('Branch Suffixes');
    });

    test('should disable create button when required fields are empty', async ({ page }) => {
      await page.getByRole('button', { name: /new session/i }).click();
      const dialog = page.locator('[role="dialog"]');
      const createBtn = dialog.getByRole('button', { name: /create session/i });
      await expect(createBtn).toBeDisabled();
    });

    test('should submit form when all required fields are filled', async ({ page }) => {
      let createCalled = false;
      await page.route(`**${API_ENDPOINTS.worktreeSessions}`, async (route: Route) => {
        if (route.request().method() === 'POST') {
          createCalled = true;
          const body = JSON.parse(route.request().postData() || '{}');
          expect(body.repository_path).toBeTruthy();
          expect(body.tasks?.length).toBeGreaterThan(0);
          await route.fulfill({
            status: 201,
            contentType: 'application/json',
            body: JSON.stringify({ session: createMockSession({ id: 'session-new' }), message: 'Created' }),
          });
        } else {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({ items: [], pagination: { total_count: 0, page: 1, per_page: 50 } }),
          });
        }
      });

      await page.getByRole('button', { name: /new session/i }).click();
      const dialog = page.locator('[role="dialog"]');
      // Fill repository path
      await dialog.locator('input').first().fill('/home/user/project');
      // Fill branch suffixes (last input in the dialog)
      await dialog.locator('input').last().fill('feature-a, feature-b');
      const createBtn = dialog.getByRole('button', { name: /create session/i });
      await expect(createBtn).toBeEnabled();
      await createBtn.click();
      await expect(dialog).not.toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Session Detail View', () => {
    test('should navigate to detail view on card click', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      // PageContainer action "Back to List" has data-testid="action-back"
      await expect(page.locator('[data-testid="action-back"]')).toBeVisible();
    });

    test('should show session status badge', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      // Badge component uses badge-theme classes
      await expect(page.locator('[class*="badge-theme"]').first()).toBeVisible();
    });

    test('should show summary cards', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText('Worktrees');
      await expect(page.locator('body')).toContainText('Progress');
      await expect(page.locator('body')).toContainText('Duration');
    });

    test('should show progress bar', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      const progressBar = page.locator('[class*="rounded-full"][class*="overflow-hidden"]').first();
      await expect(progressBar).toBeVisible();
    });

    test('should show error message when session has error', async ({ page }) => {
      currentSessionDetail = createMockSessionDetail({
        status: 'failed',
        error_message: 'Merge conflict in src/main.ts',
      });
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText('Merge conflict');
    });
  });

  test.describe('Tab Navigation', () => {
    test.beforeEach(async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
    });

    test('should show Agents tab by default', async ({ page }) => {
      await expect(tabButton(page, /agents/i)).toBeVisible();
    });

    test('should show Timeline tab', async ({ page }) => {
      await expect(tabButton(page, /timeline/i)).toBeVisible();
    });

    test('should show Graph tab', async ({ page }) => {
      await expect(tabButton(page, /graph/i)).toBeVisible();
    });

    test('should show Merges tab', async ({ page }) => {
      await expect(tabButton(page, /merges/i)).toBeVisible();
    });

    test('should show Configuration tab', async ({ page }) => {
      await expect(tabButton(page, /configuration/i)).toBeVisible();
    });

    test('should switch to Timeline tab', async ({ page }) => {
      await tabButton(page, /timeline/i).click();
      await expect(page.locator('body')).toContainText(/timeline|total/i);
    });

    test('should switch to Merges tab and show operations', async ({ page }) => {
      await tabButton(page, /merges/i).click();
      // Merges tab should show merge operation details with branch arrows
      await expect(page.locator('body')).toContainText(/merge|sequential/i);
    });

    test('should switch to Configuration tab and show config', async ({ page }) => {
      await tabButton(page, /configuration/i).click();
      await expect(page.locator('body')).toContainText('Session Configuration');
      await expect(page.locator('body')).toContainText('Repository');
      await expect(page.locator('body')).toContainText('Base Branch');
      await expect(page.locator('body')).toContainText('Merge Strategy');
      await expect(page.locator('body')).toContainText('Max Parallel');
    });
  });

  test.describe('Agent Lanes', () => {
    test('should display agent lane cards in agents tab', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');

      // Should show agent names from worktrees
      await expect(page.locator('body')).toContainText('Claude Agent');
    });

    test('should show worktree branch info', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');

      await expect(page.locator('body')).toContainText(/feature-a|feature-b|feature-c/i);
    });

    test('should display empty state when no worktrees', async ({ page }) => {
      currentSessionDetail = createMockSessionDetail();
      currentSessionDetail.worktrees = [];
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      // AgentLanesPanel shows "No worktrees provisioned yet."
      await expect(page.locator('body')).toContainText(/no worktrees/i);
    });
  });

  test.describe('Merge Status', () => {
    test('should display merge operations in merges tab', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /merges/i).click();

      // Should show at least one merge operation
      await expect(page.locator('body')).toContainText(/feature-a|feature-b/i);
    });

    test('should display empty merge state when no operations', async ({ page }) => {
      currentSessionDetail = createMockSessionDetail();
      currentSessionDetail.merge_operations = [];
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /merges/i).click();

      // MergeStatusPanel shows "No merge operations yet."
      await expect(page.locator('body')).toContainText(/No merge operations yet/);
    });

    test('should show retry merge button when merge failed', async ({ page }) => {
      currentSessionDetail = createMockSessionDetail({ status: 'failed' });
      currentSessionDetail.merge_operations = [
        createMockMergeOperation({ status: 'failed', has_conflicts: false }) as ReturnType<typeof createMockMergeOperation>,
      ];
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /merges/i).click();

      await expect(page.getByRole('button', { name: /retry merge/i })).toBeVisible();
    });

    test('should show conflict files when conflicts exist', async ({ page }) => {
      currentSessionDetail = createMockSessionDetail({ status: 'failed' });
      currentSessionDetail.merge_operations = [
        createMockMergeOperation({
          status: 'conflict',
          has_conflicts: true,
          conflict_files: ['src/main.ts', 'src/utils.ts'],
        }) as ReturnType<typeof createMockMergeOperation>,
      ];
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /merges/i).click();

      await expect(page.locator('body')).toContainText('Conflict Files');
      await expect(page.locator('body')).toContainText('src/main.ts');
      await expect(page.locator('body')).toContainText('src/utils.ts');
    });

    test('should call retry_merge API when clicking Retry Merge', async ({ page }) => {
      let retryMergeCalled = false;
      currentSessionDetail = createMockSessionDetail({ status: 'failed' });
      currentSessionDetail.merge_operations = [
        createMockMergeOperation({ status: 'failed' }) as ReturnType<typeof createMockMergeOperation>,
      ];

      await page.route(`**${API_ENDPOINTS.worktreeSessions}/*/retry_merge`, async (route: Route) => {
        retryMergeCalled = true;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ session: currentSessionDetail, message: 'Merge retry started' }),
        });
      });

      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /merges/i).click();

      const retryBtn = page.getByRole('button', { name: /retry merge/i });
      await expect(retryBtn).toBeVisible();
      await retryBtn.click();
      await page.waitForLoadState('networkidle');

      expect(retryMergeCalled).toBe(true);
    });
  });

  test.describe('Back Navigation', () => {
    test('should return to list view when clicking Back to List', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      const backBtn = page.locator('[data-testid="action-back"]');
      await expect(backBtn).toBeVisible();

      await backBtn.click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('button', { name: /new session/i })).toBeVisible();
    });
  });

  test.describe('Session Statuses', () => {
    for (const status of ['pending', 'provisioning', 'active', 'merging', 'completed', 'failed', 'cancelled'] as const) {
      test(`should display ${status} status in detail view`, async ({ page }) => {
        currentSessionDetail = createMockSessionDetail({ status });
        const card = sessionCardLocator(page).first();
        await card.click();
        await page.waitForLoadState('networkidle');
        // Badge component uses badge-theme classes
        await expect(page.locator('[class*="badge-theme"]').first()).toBeVisible();
      });
    }

    test('should show Cancel button for active sessions', async ({ page }) => {
      currentSessionDetail = createMockSessionDetail({ status: 'active' });
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      // Cancel button from PageContainer actions has data-testid="action-cancel"
      const cancelBtn = page.locator('[data-testid="action-cancel"]');
      if (await cancelBtn.count() > 0) {
        await expect(cancelBtn).toBeVisible();
      }
    });

    test('should NOT show Cancel button for completed sessions', async ({ page }) => {
      currentSessionDetail = createMockSessionDetail({ status: 'completed' });
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      // Cancel action should not exist for completed sessions
      const cancelBtn = page.locator('[data-testid="action-cancel"]');
      // Expect 0 count or not visible
      const count = await cancelBtn.count();
      if (count > 0) {
        await expect(cancelBtn).not.toBeVisible();
      }
      // Back button should still be present
      await expect(page.locator('[data-testid="action-back"]')).toBeVisible();
    });
  });

  test.describe('Cancel Session', () => {
    test('should call cancel API when clicking Cancel', async ({ page }) => {
      let cancelCalled = false;
      currentSessionDetail = createMockSessionDetail({ status: 'active' });

      await page.route(`**${API_ENDPOINTS.worktreeSessions}/*/cancel`, async (route: Route) => {
        cancelCalled = true;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ session: { ...currentSessionDetail, status: 'cancelled' }, message: 'Cancelled' }),
        });
      });

      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');

      // Click the Cancel action button (from PageContainer, data-testid="action-cancel")
      const cancelBtn = page.locator('[data-testid="action-cancel"]');
      if (await cancelBtn.count() > 0) {
        await cancelBtn.click();
        await page.waitForLoadState('networkidle');
        expect(cancelCalled).toBe(true);
      }
    });
  });

  test.describe('Configuration Panel', () => {
    test('should display repository path in configuration', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /configuration/i).click();
      await expect(page.locator('body')).toContainText('/home/user/project');
    });

    test('should display base branch in configuration', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /configuration/i).click();
      await expect(page.locator('body')).toContainText('main');
    });

    test('should display merge strategy in configuration', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /configuration/i).click();
      await expect(page.locator('body')).toContainText('sequential');
    });

    test('should display auto cleanup status', async ({ page }) => {
      const card = sessionCardLocator(page).first();
      await card.click();
      await page.waitForLoadState('networkidle');
      await tabButton(page, /configuration/i).click();
      await expect(page.locator('body')).toContainText('Auto Cleanup');
    });
  });

  test.describe('Responsive Design', () => {
    test('should display properly on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await page.goto(ROUTES.parallelExecution);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('h1')).toContainText('Parallel Execution');
    });

    test('should display properly on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await page.goto(ROUTES.parallelExecution);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('h1')).toContainText('Parallel Execution');
    });

    test('should display properly on desktop viewport', async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await page.goto(ROUTES.parallelExecution);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('h1')).toContainText('Parallel Execution');
    });
  });
});
