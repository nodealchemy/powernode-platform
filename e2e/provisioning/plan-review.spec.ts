import { test, expect, type Page, type Route } from '@playwright/test';

/**
 * AI Provisioning Plan Review — E2E
 *
 * Drives the full operator-facing M1+M2 flow:
 *   /new → ProjectProvisioningChat → "Open Plan" → ProvisioningPlanReview
 *   → topology + cost + risk → Approve & Provision → execution view
 *   → Background it → ExecutionPill bottom-right.
 *
 * Backend dispatches (LLM extraction, plan composition, run kickoff) are
 * mocked at the network layer via page.route() — this spec only validates
 * the M1+M2 frontend wiring + render contracts, not the actual provisioning
 * loop (covered by extensions/system/server/spec/integration/provisioning_m0_smoke_spec.rb).
 *
 * The chat → plan_ready transition is driven by ConversationChannel
 * WebSocket events. We override the global `WebSocket` constructor with
 * `page.addInitScript()` so the test can deterministically dispatch
 * synthetic frames (`__mockWSDispatch`) instead of waiting on a live cable.
 */

const FAKE_CONVERSATION_ID = 'conv-fixture';
const FAKE_MISSION_ID = 'mission-fixture';

// ----- mocks --------------------------------------------------------------

const FAKE_BRIEF = {
  intent: 'Provision a 3-node Postgres cluster',
  use_case: 'Side-business OLTP',
  scale: { initial: 3, target: 5, growth_profile: 'linear' },
  regions: ['us-east-1'],
  compliance: [],
  budget_cap_usd_monthly: 200,
  data_residency: [],
  preferred_provider: 'aws',
};

const FAKE_PLAN = {
  plan_id: 'plan-uuid-fixture',
  dag: {
    plan_id: 'plan-uuid-fixture',
    step_count: 1,
    // ProvisioningPage reads `plan.dag.nodes`; ProvisioningPlanReview reads the same.
    nodes: [
      {
        id: 'step-1',
        name: 'Provision full stack',
        skill: 'provision_full_stack',
        description: 'End-to-end resource provisioning',
        dependencies: [],
        on_failure: 'rollback',
        status: 'pending',
      },
    ],
    steps: [{ step_number: 1, skill: 'provision_full_stack', dependencies: [], on_failure: 'rollback' }],
  },
  cost_estimate: {
    monthly_usd: 187.5,
    one_time_usd: 0.0,
    confidence: 'med',
    by_resource: [
      { resource_type: 'compute', name: 'us-east-1 c5.large', monthly_usd: 124.1, count: 3 },
      { resource_type: 'storage', name: '50GB volume × 3', monthly_usd: 15.0, count: 3 },
      { resource_type: 'network', name: 'egress (~100GB × 3)', monthly_usd: 27.0, count: 3 },
      { resource_type: 'sdwan', name: 'SDWAN (us-east-1)', monthly_usd: 0.0, count: 1 },
    ],
  },
  topology_preview: {
    nodes: [
      { id: 'n1', type: 'user_device', label: 'Operator' },
      { id: 'n2', type: 'gateway', label: 'SDWAN Gateway' },
      { id: 'n3', type: 'network', label: 'us-east-1', region_id: 'region-1' },
      { id: 'n4', type: 'external_provider', label: 'aws' },
      { id: 'n5', type: 'database', label: 'DB primary', region_id: 'region-1', parent_id: 'n3' },
      { id: 'n6', type: 'volume', label: 'Volume 1', region_id: 'region-1', parent_id: 'n3' },
    ],
    edges: [
      { from: 'n1', to: 'n2', label: 'ingress', kind: 'ingress' },
      { from: 'n2', to: 'n3', label: 'tunnel', kind: 'tunnel' },
      { from: 'n3', to: 'n5', label: 'lan', kind: 'tunnel' },
      { from: 'n5', to: 'n6', label: 'data', kind: 'data' },
    ],
    regions: [{ id: 'region-1', name: 'us-east-1' }],
    estimated_resources: [],
  },
  risk: {
    score: 15,
    severity: 'low',
    factors: [],
  },
};

// Surface `__mockWSDispatch` and the WebSocket override types to the test.
declare global {
  interface Window {
    __mockWSDispatch?: (
      channel: string,
      params: Record<string, unknown> | undefined,
      message: unknown
    ) => void;
    __mockWSSubscribedKeys?: string[];
  }
}

/**
 * Install a mock global `WebSocket` before any frontend script runs.
 *
 * Behavior:
 *  - `new WebSocket(url)` queues an `open` event on next tick, then emits a
 *    `welcome` frame so the WebSocketManager flips to "connected".
 *  - On `send()` of a `subscribe` command, the mock immediately replies with
 *    `confirm_subscription` (matching the ActionCable protocol).
 *  - `send()` of `unsubscribe` / `message` is a no-op.
 *  - `window.__mockWSDispatch(channel, params, message)` synthesizes a
 *    server frame for the specified subscription and routes it to every
 *    open mock instance — drives `ConversationChannel`/`MissionChannel`
 *    events directly into the WebSocketManager.
 *  - `window.__mockWSSubscribedKeys` exposes the JSON identifiers the app
 *    has subscribed to so tests can wait for subscription confirmation
 *    before dispatching events.
 */
async function installWebSocketMock(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const subscribed: string[] = [];
    const instances: Array<{
      readyState: number;
      onmessage: ((ev: { data: string }) => void) | null;
    }> = [];

    class MockWebSocket {
      static CONNECTING = 0;
      static OPEN = 1;
      static CLOSING = 2;
      static CLOSED = 3;

      readyState: number = MockWebSocket.CONNECTING;
      onopen: ((ev: Event) => void) | null = null;
      onmessage: ((ev: { data: string }) => void) | null = null;
      onclose: ((ev: { code: number; reason: string }) => void) | null = null;
      onerror: ((ev: Event) => void) | null = null;
      url: string;

      constructor(url: string) {
        this.url = url;
        instances.push(this);
        // Open + welcome on next tick so `wsManager.executeConnect()` can
        // attach handlers before `onopen` fires.
        setTimeout(() => {
          this.readyState = MockWebSocket.OPEN;
          try {
            this.onopen?.(new Event('open'));
          } catch (_e) {
            // Ignore handler errors
          }
          this.deliver({ type: 'welcome' });
        }, 0);
      }

      private deliver(payload: unknown): void {
        if (!this.onmessage) return;
        try {
          this.onmessage({ data: JSON.stringify(payload) });
        } catch (_e) {
          // Ignore handler errors
        }
      }

      send(raw: string): void {
        try {
          const parsed = JSON.parse(raw) as { command?: string; identifier?: string };
          if (parsed.command === 'subscribe' && parsed.identifier) {
            subscribed.push(parsed.identifier);
            this.deliver({ type: 'confirm_subscription', identifier: parsed.identifier });
          }
        } catch (_e) {
          // Ignore non-JSON / malformed sends
        }
      }

      close(_code?: number, _reason?: string): void {
        this.readyState = MockWebSocket.CLOSED;
        try {
          this.onclose?.({ code: 1000, reason: 'mock close' });
        } catch (_e) {
          // Ignore
        }
      }

      addEventListener(): void {
        /* no-op — WebSocketManager only uses the property setters */
      }

      removeEventListener(): void {
        /* no-op */
      }
    }

    // Replace the global. The cast keeps TS happy; runtime shape matches what
    // the WebSocketManager exercises (CONNECTING/OPEN constants + handler
    // properties + send/close).
    (window as unknown as { WebSocket: typeof WebSocket }).WebSocket =
      MockWebSocket as unknown as typeof WebSocket;

    window.__mockWSSubscribedKeys = subscribed;
    window.__mockWSDispatch = (channel, params, message) => {
      const identifier = JSON.stringify({ channel, ...(params ?? {}) });
      const frame = JSON.stringify({ identifier, message });
      for (const ws of instances) {
        if (ws.readyState === MockWebSocket.OPEN && ws.onmessage) {
          try {
            ws.onmessage({ data: frame });
          } catch (_e) {
            // Ignore handler errors
          }
        }
      }
    };
  });
}

async function stubProvisioningApis(page: Page): Promise<void> {
  // Bootstrap the concierge conversation (ProvisioningPage useEffect).
  await page.route(/\/api\/v1\/ai\/conversations\/concierge$/, async (route: Route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        success: true,
        data: {
          conversation: {
            id: FAKE_CONVERSATION_ID,
            conversation_id: FAKE_CONVERSATION_ID,
          },
        },
      }),
    });
  });

  // Initial messages fetch — empty conversation.
  await page.route(
    new RegExp(`/api/v1/ai/conversations/${FAKE_CONVERSATION_ID}/messages$`),
    async (route: Route) => {
      const method = route.request().method();
      if (method === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true, data: { messages: [] } }),
        });
      } else {
        // Send-message POST — the ConversationChannel WS event is what
        // actually drives the next UI step (the test dispatches it).
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            data: { id: `msg-${Date.now()}`, accepted: true },
          }),
        });
      }
    }
  );

  // Plan compose — invoked from ProvisioningPage.handleOpenPlan.
  await page.route(
    new RegExp(`/api/v1/ai/missions/${FAKE_MISSION_ID}/compose_plan$`),
    async (route: Route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: { plan: FAKE_PLAN, brief: FAKE_BRIEF },
        }),
      });
    }
  );

  // Mission approve / reject.
  await page.route(
    new RegExp(`/api/v1/ai/missions/${FAKE_MISSION_ID}/(approve|reject)$`),
    async (route: Route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: { mission_id: FAKE_MISSION_ID, status: 'approved' },
        }),
      });
    }
  );

  // Belt-and-suspenders: keep the legacy MCP-bridge mocks in case any
  // ancillary code path still exercises them.
  await page.route(/\/api\/v1\/.*platform_provisioning_capture_brief/, async (route: Route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        success: true,
        data: { mission_id: FAKE_MISSION_ID, brief: FAKE_BRIEF, missing_fields: [] },
      }),
    });
  });

  await page.route(/\/api\/v1\/.*platform_provisioning_compose_plan/, async (route: Route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ success: true, data: FAKE_PLAN }),
    });
  });

  await page.route(/\/api\/v1\/.*platform_provisioning_approve_plan/, async (route: Route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        success: true,
        data: {
          plan_id: FAKE_PLAN.plan_id,
          plan: { id: FAKE_PLAN.plan_id, status: 'approved', step_count: 1 },
          approval_request_id: null,
          mission_status: 'active',
        },
      }),
    });
  });

  await page.route(/\/api\/v1\/.*platform_provisioning_execute/, async (route: Route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        success: true,
        data: {
          runner_id: 'run-fixture',
          started_at: '2026-05-07T18:00:00Z',
          step_count: 1,
        },
      }),
    });
  });

  await page.route(/\/api\/v1\/.*platform_provisioning_status/, async (route: Route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        success: true,
        data: { phase: 'execute', current_step: 1, completed: [], pending: [], failed: [] },
      }),
    });
  });
}

async function waitForChannelSubscription(
  page: Page,
  channel: string,
  params: Record<string, unknown>
): Promise<void> {
  const expectedIdentifier = JSON.stringify({ channel, ...params });
  await page.waitForFunction(
    (id: string) => Array.isArray(window.__mockWSSubscribedKeys) && window.__mockWSSubscribedKeys.includes(id),
    expectedIdentifier,
    { timeout: 10000 }
  );
}

async function dispatchChannelMessage(
  page: Page,
  channel: string,
  params: Record<string, unknown>,
  message: unknown
): Promise<void> {
  await page.evaluate(
    ({ channel: c, params: p, message: m }) => {
      window.__mockWSDispatch?.(c, p, m);
    },
    { channel, params, message }
  );
}

test.describe('AI Provisioning Plan Review (M1+M2)', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await installWebSocketMock(page);
    await stubProvisioningApis(page);
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test('side-business persona prompt → plan review modal renders all three previews', async ({ page }) => {
    await page.goto('/new', { waitUntil: 'load' });

    // Chat surface ready (ProvisioningPage bootstrap completed via mock).
    const input = page.getByTestId('chat-input');
    await expect(input).toBeVisible({ timeout: 15000 });

    // Wait for ConversationChannel subscription before dispatching a frame —
    // otherwise the WebSocketManager has nothing to route the message to.
    await waitForChannelSubscription(page, 'ConversationChannel', {
      conversation_id: FAKE_CONVERSATION_ID,
    });

    await input.fill(
      'I run a small Etsy-style side business. I need a 3-node Postgres cluster in us-east-1 ' +
        'with $200/mo budget for OLTP traffic.'
    );
    await page.keyboard.press('Enter');

    // Optimistic user bubble should be rendered immediately.
    await expect(page.getByTestId('msg-user').last()).toBeVisible();

    // Push the AI response carrying `plan_ready` — this is the trigger that
    // unhides the "Open Plan" button.
    await dispatchChannelMessage(
      page,
      'ConversationChannel',
      { conversation_id: FAKE_CONVERSATION_ID },
      {
        event: 'message_created',
        message: {
          id: 'msg-ai-1',
          sender_type: 'ai',
          content:
            'Got it — a 3-node Postgres cluster in us-east-1 within a $200/mo budget. Plan is ready for review.',
          created_at: new Date().toISOString(),
          metadata: {
            mission_id: FAKE_MISSION_ID,
            mission_phase: 'plan_ready',
            plan_ready: { mission_id: FAKE_MISSION_ID },
          },
        },
      }
    );

    // Open Plan button surfaces once the AI message renders.
    const openPlanButton = page.getByTestId('open-plan-button');
    await expect(openPlanButton).toBeVisible({ timeout: 15000 });
    await openPlanButton.click();

    // Modal mounted with all three previews.
    const modal = page.getByTestId('provisioning-plan-review');
    await expect(modal).toBeVisible({ timeout: 15000 });

    // Topology — ReactFlow surface always renders a `.react-flow__viewport`.
    await expect(page.getByTestId('provisioning-topology')).toBeVisible();

    // Cost block (CostBreakdown contains the monthly total label).
    await expect(modal.getByText(/\/mo|monthly/i).first()).toBeVisible();

    // Risk badge — section is keyed off severity/score.
    await expect(page.getByTestId('provisioning-risk')).toBeVisible();
    await expect(page.getByTestId('provisioning-risk').getByText(/low risk|medium risk|high risk/i)).toBeVisible();

    // Approve & Provision — uses the structured testid; the `getByRole` regex
    // still works but the testid is more precise.
    const approveButton = page.getByTestId('provisioning-approve-btn');
    await approveButton.click();

    // Wait for MissionChannel subscription so step events route correctly,
    // then drive the step to completion via synthetic WS frame.
    await waitForChannelSubscription(page, 'MissionChannel', { mission_id: FAKE_MISSION_ID });

    await dispatchChannelMessage(
      page,
      'MissionChannel',
      { mission_id: FAKE_MISSION_ID },
      {
        event: 'provisioning_step_changed',
        payload: {
          mission_id: FAKE_MISSION_ID,
          step_id: 'step-1',
          status: 'running',
        },
      }
    );

    // Execution view + step stream.
    await expect(page.getByTestId('step-progress-stream')).toBeVisible({ timeout: 15000 });

    // Background it (modal close button — labelled "Close modal" by Modal.tsx).
    const closeButton = page.getByRole('button', { name: /close modal/i });
    await closeButton.click();

    // ExecutionPill — bottom-right floating element.
    await expect(page.getByTestId('execution-pill')).toBeVisible({ timeout: 5000 });
  });
});
