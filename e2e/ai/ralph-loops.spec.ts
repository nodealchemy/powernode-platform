import { test, expect, Page, Route } from '@playwright/test';
import { ROUTES, API_ENDPOINTS } from '../fixtures/test-data';

/**
 * Ralph Loops - Mocked E2E Tests
 *
 * Uses page.route() to intercept API calls and return mock data.
 * No backend required. Tests UI rendering, interactions, state transitions,
 * and agent-based execution flow.
 */

// Mock data factory
function createMockLoop(overrides: Record<string, unknown> = {}) {
  return {
    id: 'loop-001',
    account_id: 'acc-001',
    name: 'Test Ralph Loop',
    description: 'A test loop for E2E testing',
    status: 'pending',
    current_iteration: 0,
    max_iterations: 10,
    default_agent_id: 'agent-001',
    default_agent_name: 'Ollama Agent',
    mcp_server_ids: [],
    task_count: 5,
    completed_task_count: 0,
    progress_percentage: 0,
    learnings: [],
    scheduling_mode: 'manual',
    configuration: {},
    metrics: {
      total_iterations: 0,
      successful_iterations: 0,
      failed_iterations: 0,
      total_tasks: 5,
      completed_tasks: 0,
      total_tokens: 0,
      total_cost: 0,
    },
    created_at: '2026-02-01T00:00:00Z',
    updated_at: '2026-02-01T00:00:00Z',
    ...overrides,
  };
}

function createMockLoopSummary(overrides: Record<string, unknown> = {}) {
  return {
    id: 'loop-001',
    name: 'Test Ralph Loop',
    description: 'A test loop for E2E testing',
    status: 'pending',
    current_iteration: 0,
    max_iterations: 10,
    default_agent_id: 'agent-001',
    default_agent_name: 'Ollama Agent',
    mcp_server_ids: [],
    task_count: 5,
    completed_task_count: 0,
    progress_percentage: 0,
    scheduling_mode: 'manual',
    ...overrides,
  };
}

const mockAgents = [
  { id: 'agent-001', name: 'Ollama Agent', status: 'active', agent_type: 'assistant' },
  { id: 'agent-002', name: 'Claude Agent', status: 'active', agent_type: 'assistant' },
  { id: 'agent-003', name: 'GPT Agent', status: 'active', agent_type: 'assistant' },
];

// Shared mock state for route handlers
let currentLoopStatus = 'pending';
let currentIteration = 0;

async function setupApiMocks(page: Page, options: { loops?: Record<string, unknown>[], loopDetail?: Record<string, unknown> } = {}) {
  const defaultLoops = options.loops || [
    createMockLoopSummary(),
    createMockLoopSummary({ id: 'loop-002', name: 'Claude Code Loop', default_agent_id: 'agent-002', default_agent_name: 'Claude Agent', status: 'running', current_iteration: 3 }),
    createMockLoopSummary({ id: 'loop-003', name: 'GPT Loop', default_agent_id: 'agent-003', default_agent_name: 'GPT Agent', status: 'completed', progress_percentage: 100 }),
  ];

  // GET /api/v1/ai/agents - Agent list for selectors
  await page.route(`**${API_ENDPOINTS.agents}*`, async (route: Route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: mockAgents,
          pagination: { total_count: mockAgents.length, page: 1, per_page: 100 },
        }),
      });
    } else {
      await route.continue();
    }
  });

  // All ralph_loops API routes - single catch-all handler
  await page.route(`**${API_ENDPOINTS.ralphLoops}**`, async (route: Route) => {
    const url = route.request().url();
    const method = route.request().method();

    // Extract path after ralph_loops (strip query params for path matching)
    const pathPart = url.replace(/\?.*$/, '');
    const afterLoops = pathPart.replace(/^.*ralph_loops\/?/, '');

    // GET list: /ralph_loops or /ralph_loops?params (afterLoops is empty)
    if (method === 'GET' && !afterLoops) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: defaultLoops,
          pagination: { total_count: defaultLoops.length, page: 1, per_page: 50 },
        }),
      });
      return;
    }

    // GET detail: /ralph_loops/:id (afterLoops has no slash)
    if (method === 'GET' && afterLoops && !afterLoops.includes('/')) {
      const loopId = afterLoops;
      const detail = options.loopDetail || createMockLoop({
        id: loopId,
        status: currentLoopStatus,
        current_iteration: currentIteration,
      });
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: detail }),
      });
      return;
    }

    // POST start
    if (method === 'POST' && url.includes('/start')) {
      currentLoopStatus = 'running';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'running' }) }),
      });
      return;
    }

    // POST pause
    if (method === 'POST' && url.includes('/pause')) {
      currentLoopStatus = 'paused';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'paused' }) }),
      });
      return;
    }

    // POST resume
    if (method === 'POST' && url.includes('/resume')) {
      currentLoopStatus = 'running';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'running' }) }),
      });
      return;
    }

    // POST cancel
    if (method === 'POST' && url.includes('/cancel')) {
      currentLoopStatus = 'cancelled';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'cancelled' }) }),
      });
      return;
    }

    // POST reset
    if (method === 'POST' && url.includes('/reset')) {
      currentLoopStatus = 'pending';
      currentIteration = 0;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'pending', current_iteration: 0 }) }),
      });
      return;
    }

    // POST run_all
    if (method === 'POST' && url.includes('/run_all') && !url.includes('stop_run_all')) {
      currentLoopStatus = 'running';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'running', configuration: { run_all_active: true } }) }),
      });
      return;
    }

    // POST stop_run_all
    if (method === 'POST' && url.includes('/stop_run_all')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'running', configuration: { run_all_active: false } }) }),
      });
      return;
    }

    // POST run_iteration
    if (method === 'POST' && url.includes('/run_iteration')) {
      currentIteration += 1;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          ralph_iteration: {
            id: `iter-${currentIteration}`,
            ralph_loop_id: 'loop-001',
            iteration_number: currentIteration,
            status: 'completed',
            created_at: new Date().toISOString(),
          },
        }),
      });
      return;
    }

    // POST create
    if (method === 'POST' && !afterLoops) {
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ id: 'loop-new' }) }),
      });
      return;
    }

    // PATCH/PUT update
    if (method === 'PATCH' || method === 'PUT') {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ralph_loop: createMockLoop({ status: currentLoopStatus }) }),
      });
      return;
    }

    // GET tasks
    if (method === 'GET' && url.includes('/tasks')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: [
            { id: 'task-1', task_key: 'setup', description: 'Initial setup', status: 'pending', priority: 1, iteration_count: 0, execution_type: 'agent' },
            { id: 'task-2', task_key: 'implement', description: 'Core implementation', status: 'pending', priority: 2, iteration_count: 0, execution_type: 'agent' },
          ],
          pagination: { total_count: 2, page: 1, per_page: 50 },
        }),
      });
      return;
    }

    // GET iterations
    if (method === 'GET' && url.includes('/iterations')) {
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

    // GET progress
    if (method === 'GET' && url.includes('/progress')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          loop_status: { loop: {}, tasks: [], recent_iterations: [], next_task: null },
          progress_text: 'Waiting to start',
          progress_percentage: 0,
          learnings: [],
          recent_commits: [],
        }),
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

test.describe('Ralph Loops Page', () => {
  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    currentLoopStatus = 'pending';
    currentIteration = 0;
    await setupApiMocks(page);
    await page.goto(ROUTES.ralphLoops);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  });

  test.describe('Page Navigation', () => {
    test('should navigate to ralph loops page', async ({ page }) => {
      expect(page.url()).toContain('/ralph-loops');
    });

    test('should display page title', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Ralph Loops');
    });

    test('should display breadcrumbs', async ({ page }) => {
      await expect(page.locator('body')).toContainText('AI');
    });
  });

  test.describe('List View', () => {
    test('should display loop cards', async ({ page }) => {
      const headings = page.getByRole('heading', { level: 3 }).filter({ hasText: /loop/i });
      await expect(headings.first()).toBeVisible({ timeout: 5000 });
      expect(await headings.count()).toBeGreaterThan(0);
    });

    test('should display New Loop button', async ({ page }) => {
      const newButton = page.getByRole('button', { name: /new loop/i });
      await expect(newButton).toBeVisible();
    });

    test('should show status filter', async ({ page }) => {
      const select = page.locator('select').first();
      await expect(select).toBeVisible();
    });

    test('should show agent filter dropdown', async ({ page }) => {
      const agentSelect = page.locator('select').nth(1);
      await expect(agentSelect).toBeVisible();
      const options = await agentSelect.locator('option').allTextContents();
      expect(options).toContain('All Agents');
    });

    test('should show agent name on loop cards', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Ollama Agent');
    });

    test('should display empty state when filtered with no results', async ({ page }) => {
      await page.route(`**${API_ENDPOINTS.ralphLoops}**`, async (route: Route) => {
        const url = route.request().url();
        const pathPart = url.replace(/\?.*$/, '');
        const afterLoops = pathPart.replace(/^.*ralph_loops\/?/, '');
        if (route.request().method() === 'GET' && !afterLoops) {
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
      await expect(page.locator('body')).toContainText(/no loops|adjust/i);
    });

    test('should show refresh button', async ({ page }) => {
      const refreshBtn = page.locator('button').filter({ has: page.locator('svg') }).filter({ hasNotText: /./  });
      expect(await refreshBtn.count()).toBeGreaterThan(0);
    });
  });

  test.describe('Create Dialog', () => {
    test('should open create dialog when clicking New Loop', async ({ page }) => {
      await page.getByRole('button', { name: /new loop/i }).click();
      await expect(page.locator('[role="dialog"]')).toBeVisible();
      await expect(page.locator('[role="dialog"]')).toContainText('Create Ralph Loop');
    });

    test('should close dialog on Cancel', async ({ page }) => {
      await page.getByRole('button', { name: /new loop/i }).click();
      await expect(page.locator('[role="dialog"]')).toBeVisible();
      await page.locator('[role="dialog"]').getByRole('button', { name: /cancel/i }).click();
      await expect(page.locator('[role="dialog"]')).not.toBeVisible();
    });

    test('should show agent selector in create dialog', async ({ page }) => {
      await page.getByRole('button', { name: /new loop/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toBeVisible();
      await expect(dialog).toContainText('Default Agent');
      const select = dialog.locator('select');
      await expect(select).toBeVisible();
    });

    test('should have name input field', async ({ page }) => {
      await page.getByRole('button', { name: /new loop/i }).click();
      const dialog = page.locator('[role="dialog"]');
      const nameInput = dialog.locator('input').first();
      await expect(nameInput).toBeVisible();
    });

    test('should have max iterations input', async ({ page }) => {
      await page.getByRole('button', { name: /new loop/i }).click();
      const dialog = page.locator('[role="dialog"]');
      const iterInput = dialog.locator('input[type="number"]');
      await expect(iterInput).toBeVisible();
    });

    test('should disable create button when no agent selected', async ({ page }) => {
      await page.getByRole('button', { name: /new loop/i }).click();
      const dialog = page.locator('[role="dialog"]');
      // Fill name but leave agent empty
      await dialog.locator('input').first().fill('Test Loop');
      const createBtn = dialog.getByRole('button', { name: /create loop/i });
      await expect(createBtn).toBeDisabled();
    });

    test('should submit form when name and agent are provided', async ({ page }) => {
      let createCalled = false;
      await page.route(`**${API_ENDPOINTS.ralphLoops}`, async (route: Route) => {
        if (route.request().method() === 'POST') {
          createCalled = true;
          const body = JSON.parse(route.request().postData() || '{}');
          expect(body.ralph_loop?.default_agent_id).toBeTruthy();
          await route.fulfill({
            status: 201,
            contentType: 'application/json',
            body: JSON.stringify({ ralph_loop: createMockLoop({ id: 'loop-new' }) }),
          });
        } else {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({ items: [], pagination: { total_count: 0, page: 1, per_page: 50 } }),
          });
        }
      });

      await page.getByRole('button', { name: /new loop/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await dialog.locator('input').first().fill('My New Loop');
      // Select an agent
      const select = dialog.locator('select');
      await select.selectOption('agent-001');
      const createBtn = dialog.getByRole('button', { name: /create loop/i });
      await expect(createBtn).toBeEnabled();
      await createBtn.click();
      await expect(dialog).not.toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Detail View - Pending State', () => {
    test('should navigate to detail view on card click', async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText('Test Ralph Loop');
      await expect(page.getByRole('button', { name: /back to list/i })).toBeVisible();
    });

    test('should show Pending status badge', async ({ page }) => {
      currentLoopStatus = 'pending';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText('Pending');
    });

    test('should show Start Loop button when pending', async ({ page }) => {
      currentLoopStatus = 'pending';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('button', { name: /start loop/i })).toBeVisible();
    });

    test('should NOT show Run One button when pending', async ({ page }) => {
      currentLoopStatus = 'pending';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('button', { name: /run one/i })).not.toBeVisible();
    });

    test('should show stats cards with Default Agent', async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toContainText('Iterations');
      await expect(page.locator('body')).toContainText('Tasks Completed');
      await expect(page.locator('body')).toContainText('Progress');
      await expect(page.locator('body')).toContainText('Default Agent');
    });

    test('should show agent name in Default Agent stats card', async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      const agentSection = page.locator('text=Default Agent').locator('..');
      await expect(agentSection).toContainText('Ollama Agent');
    });

    test('should show Settings button', async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('button', { name: /settings/i })).toBeVisible();
    });
  });

  test.describe('Detail View - Running State (Bug Fix Verification)', () => {
    test.beforeEach(async ({ page }) => {
      currentLoopStatus = 'running';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
    });

    test('should show Running status badge', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Running');
    });

    test('CRITICAL: should show Run One button when running', async ({ page }) => {
      await expect(page.getByRole('button', { name: /run one/i })).toBeVisible();
    });

    test('should show Pause button when running', async ({ page }) => {
      await expect(page.getByRole('button', { name: /^pause$/i })).toBeVisible();
    });

    test('should NOT show Start Loop button when running', async ({ page }) => {
      await expect(page.getByRole('button', { name: /start loop/i })).not.toBeVisible();
    });

    test('should NOT show Resume button when running', async ({ page }) => {
      await expect(page.getByRole('button', { name: /^resume$/i })).not.toBeVisible();
    });
  });

  test.describe('Detail View - Paused State', () => {
    test.beforeEach(async ({ page }) => {
      currentLoopStatus = 'paused';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
    });

    test('should show Paused status badge', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Paused');
    });

    test('should show Resume button when paused', async ({ page }) => {
      await expect(page.getByRole('button', { name: /^resume$/i })).toBeVisible();
    });

    test('should show Cancel button when paused', async ({ page }) => {
      await expect(page.getByRole('button', { name: /^cancel$/i })).toBeVisible();
    });

    test('should NOT show Run One button when paused', async ({ page }) => {
      await expect(page.getByRole('button', { name: /run one/i })).not.toBeVisible();
    });

    test('should NOT show Start Loop button when paused', async ({ page }) => {
      await expect(page.getByRole('button', { name: /start loop/i })).not.toBeVisible();
    });
  });

  test.describe('Detail View - Terminal States', () => {
    for (const terminalStatus of ['completed', 'failed', 'cancelled']) {
      test(`should show Reset button when ${terminalStatus}`, async ({ page }) => {
        currentLoopStatus = terminalStatus;
        const card = page.locator('div').filter({ has: page.getByRole('heading', { name: 'Test Ralph Loop' }) }).first();
        await card.click();
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('button', { name: /^reset$/i })).toBeVisible();
      });

      test(`should NOT show Start/Pause/Resume/RunOne when ${terminalStatus}`, async ({ page }) => {
        currentLoopStatus = terminalStatus;
        const card = page.locator('div').filter({ has: page.getByRole('heading', { name: 'Test Ralph Loop' }) }).first();
        await card.click();
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('button', { name: /start loop/i })).not.toBeVisible();
        await expect(page.getByRole('button', { name: /^pause$/i })).not.toBeVisible();
        await expect(page.getByRole('button', { name: /^resume$/i })).not.toBeVisible();
        await expect(page.getByRole('button', { name: /run one/i })).not.toBeVisible();
      });
    }
  });

  test.describe('Run Iteration Flow', () => {
    test('should call run_iteration API when clicking Run One', async ({ page }) => {
      currentLoopStatus = 'running';
      let runIterationCalled = false;

      await page.route(`**${API_ENDPOINTS.ralphLoops}/*/run_iteration`, async (route: Route) => {
        runIterationCalled = true;
        currentIteration += 1;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            ralph_iteration: {
              id: `iter-${currentIteration}`,
              ralph_loop_id: 'loop-001',
              iteration_number: currentIteration,
              status: 'completed',
              created_at: new Date().toISOString(),
            },
          }),
        });
      });

      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');

      const runOneBtn = page.getByRole('button', { name: /run one/i });
      await expect(runOneBtn).toBeVisible();
      await runOneBtn.click();
      await page.waitForLoadState('networkidle');

      expect(runIterationCalled).toBe(true);
    });
  });

  test.describe('Tab Navigation', () => {
    test.beforeEach(async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
    });

    test('should show Tasks tab by default', async ({ page }) => {
      // Tabs render as buttons, not role="tab"
      await expect(page.getByRole('button', { name: 'Tasks', exact: true })).toBeVisible();
    });

    test('should switch to Iterations tab', async ({ page }) => {
      await page.getByRole('button', { name: 'Iterations', exact: true }).click();
      // Verify tab content changed by checking for iterations-related content
      await expect(page.locator('body')).toContainText('Iterations');
    });

    test('should switch to Progress tab', async ({ page }) => {
      await page.getByRole('button', { name: 'Progress', exact: true }).click();
      await expect(page.locator('body')).toContainText('Progress');
    });

    test('should switch to Schedule tab', async ({ page }) => {
      await page.getByRole('button', { name: 'Schedule', exact: true }).click();
      await expect(page.locator('body')).toContainText('Schedule');
    });
  });

  test.describe('Settings Modal', () => {
    test.beforeEach(async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
    });

    test('should open settings modal', async ({ page }) => {
      await page.getByRole('button', { name: /settings/i }).click();
      await expect(page.locator('[role="dialog"]')).toBeVisible();
      await expect(page.locator('[role="dialog"]')).toContainText('Loop Settings');
    });

    test('should display current loop values', async ({ page }) => {
      await page.getByRole('button', { name: /settings/i }).click();
      const dialog = page.locator('[role="dialog"]');
      const nameInput = dialog.locator('input').first();
      await expect(nameInput).toHaveValue('Test Ralph Loop');
    });

    test('should display default agent name in settings', async ({ page }) => {
      await page.getByRole('button', { name: /settings/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toContainText('Ollama Agent');
    });

    test('should close settings on Cancel', async ({ page }) => {
      await page.getByRole('button', { name: /settings/i }).click();
      const dialog = page.locator('[role="dialog"]');
      await expect(dialog).toBeVisible();
      await dialog.getByRole('button', { name: /cancel/i }).click();
      await expect(dialog).not.toBeVisible();
    });

    test('should save settings', async ({ page }) => {
      let updateCalled = false;
      await page.route(`**${API_ENDPOINTS.ralphLoops}/*`, async (route: Route) => {
        if (route.request().method() === 'PATCH' || route.request().method() === 'PUT') {
          updateCalled = true;
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({ ralph_loop: createMockLoop({ name: 'Updated Name' }) }),
          });
          return;
        }
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ ralph_loop: createMockLoop() }),
        });
      });

      await page.getByRole('button', { name: /settings/i }).click();
      const dialog = page.locator('[role="dialog"]');
      const saveBtn = dialog.getByRole('button', { name: /save settings/i });
      await saveBtn.click();
      await page.waitForLoadState('networkidle');
      expect(updateCalled).toBe(true);
    });
  });

  test.describe('Agent Display', () => {
    test('should show agent name in loop card', async ({ page }) => {
      await expect(page.locator('body')).toContainText('Ollama Agent');
    });

    test('should show agent name in detail view stats card', async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      const agentSection = page.locator('text=Default Agent').locator('..');
      await expect(agentSection).toContainText('Ollama Agent');
    });
  });

  test.describe('Back Navigation', () => {
    test('should return to list view when clicking Back', async ({ page }) => {
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('button', { name: /back to list/i })).toBeVisible();

      await page.getByRole('button', { name: /back to list/i }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('button', { name: /new loop/i })).toBeVisible();
    });
  });

  test.describe('Run All / Stop Run All', () => {
    test('should show Run All button when running and runAllActive is false', async ({ page }) => {
      currentLoopStatus = 'running';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('[data-testid="action-run-all"]')).toBeVisible();
    });

    test('should show Run One and Run All together when running', async ({ page }) => {
      currentLoopStatus = 'running';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.getByRole('button', { name: /run one/i })).toBeVisible();
      await expect(page.locator('[data-testid="action-run-all"]')).toBeVisible();
    });

    test('should NOT show Run All when pending', async ({ page }) => {
      currentLoopStatus = 'pending';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('[data-testid="action-run-all"]')).not.toBeVisible();
    });

    test('should NOT show Run All when paused', async ({ page }) => {
      currentLoopStatus = 'paused';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('[data-testid="action-run-all"]')).not.toBeVisible();
    });

    test('should NOT show Run All in terminal states', async ({ page }) => {
      for (const status of ['completed', 'failed', 'cancelled']) {
        currentLoopStatus = status;
        const card = page.locator('div').filter({ has: page.getByRole('heading', { name: 'Test Ralph Loop' }) }).first();
        await card.click();
        await page.waitForLoadState('networkidle');
        await expect(page.locator('[data-testid="action-run-all"]')).not.toBeVisible();
        // Go back for next iteration
        await page.getByRole('button', { name: /back to list/i }).click();
        await page.waitForLoadState('networkidle');
      }
    });

    test('should call run_all API when clicking Run All', async ({ page }) => {
      currentLoopStatus = 'running';
      let runAllCalled = false;

      await page.route(`**${API_ENDPOINTS.ralphLoops}/*/run_all`, async (route: Route) => {
        runAllCalled = true;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'running', configuration: { run_all_active: true } }) }),
        });
      });

      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');

      await page.locator('[data-testid="action-run-all"]').click();
      await page.waitForLoadState('networkidle');

      expect(runAllCalled).toBe(true);
    });

    test('should show Stop Run All when run_all_active is true', async ({ page }) => {
      currentLoopStatus = 'running';
      // Override detail route to return run_all_active: true
      await page.route(`**${API_ENDPOINTS.ralphLoops}**`, async (route: Route) => {
        const url = route.request().url();
        const method = route.request().method();
        const pathPart = url.replace(/\?.*$/, '');
        const afterLoops = pathPart.replace(/^.*ralph_loops\/?/, '');
        if (method === 'GET' && afterLoops && !afterLoops.includes('/')) {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
              ralph_loop: createMockLoop({ status: 'running', configuration: { run_all_active: true } }),
            }),
          });
          return;
        }
        await route.fallback();
      });

      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');

      await expect(page.locator('[data-testid="action-stop-run-all"]')).toBeVisible();
    });

    test('should NOT show Run One when runAllActive is true', async ({ page }) => {
      currentLoopStatus = 'running';
      await page.route(`**${API_ENDPOINTS.ralphLoops}**`, async (route: Route) => {
        const url = route.request().url();
        const method = route.request().method();
        const pathPart = url.replace(/\?.*$/, '');
        const afterLoops = pathPart.replace(/^.*ralph_loops\/?/, '');
        if (method === 'GET' && afterLoops && !afterLoops.includes('/')) {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
              ralph_loop: createMockLoop({ status: 'running', configuration: { run_all_active: true } }),
            }),
          });
          return;
        }
        await route.fallback();
      });

      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');

      await expect(page.getByRole('button', { name: /run one/i })).not.toBeVisible();
    });

    test('should call stop_run_all API when clicking Stop Run All', async ({ page }) => {
      currentLoopStatus = 'running';
      let stopCalled = false;

      await page.route(`**${API_ENDPOINTS.ralphLoops}/*/stop_run_all`, async (route: Route) => {
        stopCalled = true;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ ralph_loop: createMockLoop({ status: 'running', configuration: { run_all_active: false } }) }),
        });
      });

      await page.route(`**${API_ENDPOINTS.ralphLoops}**`, async (route: Route) => {
        const url = route.request().url();
        const method = route.request().method();
        if (url.includes('stop_run_all')) {
          await route.fallback();
          return;
        }
        const pathPart = url.replace(/\?.*$/, '');
        const afterLoops = pathPart.replace(/^.*ralph_loops\/?/, '');
        if (method === 'GET' && afterLoops && !afterLoops.includes('/')) {
          await route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
              ralph_loop: createMockLoop({ status: 'running', configuration: { run_all_active: true } }),
            }),
          });
          return;
        }
        await route.fallback();
      });

      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');

      await page.locator('[data-testid="action-stop-run-all"]').click();
      await page.waitForLoadState('networkidle');

      expect(stopCalled).toBe(true);
    });
  });

  test.describe('Live Execution Panel', () => {
    test('should NOT show panel when pending', async ({ page }) => {
      currentLoopStatus = 'pending';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('text=Live Execution')).not.toBeVisible();
    });

    test('should show panel when running', async ({ page }) => {
      currentLoopStatus = 'running';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('text=Live Execution')).toBeVisible();
    });

    test('should show Running badge in panel header', async ({ page }) => {
      currentLoopStatus = 'running';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      // The RalphLiveExecutionPanel shows a "Running" badge next to "Live Execution" in the same panel section
      const panelSection = page.locator('text=Live Execution').locator('../..');
      await expect(panelSection).toContainText('Running');
    });

    test('should show "Waiting for iteration results..." when no iterations', async ({ page }) => {
      currentLoopStatus = 'running';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');
      await expect(page.locator('text=Waiting for iteration results...')).toBeVisible();
    });

    test('should NOT show panel in terminal states with no iterations', async ({ page }) => {
      for (const status of ['completed', 'failed', 'cancelled']) {
        currentLoopStatus = status;
        const card = page.locator('div').filter({ has: page.getByRole('heading', { name: 'Test Ralph Loop' }) }).first();
        await card.click();
        await page.waitForLoadState('networkidle');
        await expect(page.locator('text=Live Execution')).not.toBeVisible();
        await page.getByRole('button', { name: /back to list/i }).click();
        await page.waitForLoadState('networkidle');
      }
    });
  });

  test.describe('State Transitions', () => {
    test('should transition from pending to running on Start', async ({ page }) => {
      currentLoopStatus = 'pending';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');

      await page.getByRole('button', { name: /start loop/i }).click();
      await page.waitForLoadState('networkidle');

      await expect(page.locator('body')).toContainText('Running');
      await expect(page.getByRole('button', { name: /run one/i })).toBeVisible();
    });

    test('should transition from running to paused on Pause', async ({ page }) => {
      currentLoopStatus = 'running';
      await page.getByRole('heading', { name: 'Test Ralph Loop' }).click();
      await page.waitForLoadState('networkidle');

      await page.getByRole('button', { name: /^pause$/i }).click();
      await page.waitForLoadState('networkidle');

      await expect(page.locator('body')).toContainText('Paused');
      await expect(page.getByRole('button', { name: /^resume$/i })).toBeVisible();
    });
  });
});
