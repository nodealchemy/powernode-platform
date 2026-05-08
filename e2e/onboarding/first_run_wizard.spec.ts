import { test, expect, type Page, type Route } from '@playwright/test';

/**
 * M2 BYOC First-Run Wizard — E2E
 *
 * Drives the full onboarding flow:
 *   /login (skipped via storageState) → OnboardingGate sees no creds →
 *   redirect to /onboarding → 4-step wizard:
 *     1. Welcome
 *     2. Provider select (Vultr)
 *     3. Credentials form: enter API key → Test (200) → Save (201)
 *     4. Seed templates: POST /onboarding/complete → 200 → redirect to /new
 *   → second visit: GET /onboarding/status returns completed=true → no redirect.
 *
 * Backend dispatches are mocked at the network layer via `page.route()` so
 * this spec only validates the M2 frontend wiring + redirect contracts. The
 * actual server-side onboarding flow is exercised by:
 *   - server/spec/controllers/api/v1/onboarding_controller_spec.rb
 *   - extensions/system/server/spec/controllers/api/v1/system/provider_credentials_controller_spec.rb
 *   - extensions/system/server/spec/services/system/credential_validation_service_spec.rb
 *
 * NOTE: this spec uses the existing playwright auth fixture (e2e/.auth/user.json
 * created by global-setup) — the user is already logged in. The "fresh login"
 * path the task brief mentions is short-circuited via mocked `/onboarding/status`
 * responses; we don't actually log a brand-new user in for each test (the
 * existing storageState gives us a valid JWT, and the onboarding redirect is
 * driven by the mocked status payload, not the auth state).
 */

const FAKE_CREDENTIAL_ID = 'cred-fixture-uuid';
const FAKE_API_KEY = 'VULTR-test-key-1234567890';

interface OnboardingStatus {
  completed: boolean;
  has_credentials: boolean;
  completed_at: string | null;
}

/**
 * Stub the four endpoints the wizard touches:
 *   - GET  /api/v1/onboarding/status              — drives OnboardingGate redirect
 *   - POST /api/v1/system/provider_credentials/test — green-checks the creds
 *   - POST /api/v1/system/provider_credentials       — persists the cred
 *   - POST /api/v1/onboarding/complete             — flips the flag, redirect to /new
 *
 * `statusFn` lets a test progressively flip `completed` from false → true so
 * we can assert the second visit no longer redirects.
 */
async function stubOnboardingApis(
  page: Page,
  statusFn: () => OnboardingStatus
): Promise<{ saveCalls: number; completeCalls: number; testCalls: number }> {
  const counters = { saveCalls: 0, completeCalls: 0, testCalls: 0 };

  await page.route(/\/api\/v1\/onboarding\/status$/, async (route: Route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ success: true, data: statusFn() }),
    });
  });

  await page.route(
    /\/api\/v1\/system\/provider_credentials\/test$/,
    async (route: Route) => {
      counters.testCalls += 1;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ success: true, data: { valid: true } }),
      });
    }
  );

  // The non-test POST has the same path prefix; route ordering matters in
  // Playwright (last-registered handler wins for an overlapping URL), so the
  // generic /provider_credentials handler is registered AFTER /test.
  await page.route(
    /\/api\/v1\/system\/provider_credentials(?:\?.*)?$/,
    async (route: Route) => {
      const method = route.request().method();
      if (method !== 'POST') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ success: true, data: [] }),
        });
        return;
      }
      counters.saveCalls += 1;
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: { id: FAKE_CREDENTIAL_ID, provider_type: 'vultr' },
        }),
      });
    }
  );

  await page.route(/\/api\/v1\/onboarding\/complete$/, async (route: Route) => {
    counters.completeCalls += 1;
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        success: true,
        data: {
          completed: true,
          has_credentials: true,
          completed_at: new Date().toISOString(),
        },
      }),
    });
  });

  return counters;
}

test.describe('M2 BYOC First-Run Wizard', () => {
  test('walks the operator through provider → credentials → seed → /new', async ({
    page,
  }) => {
    let status: OnboardingStatus = {
      completed: false,
      has_credentials: false,
      completed_at: null,
    };
    const counters = await stubOnboardingApis(page, () => status);

    // Quiet down React/devtools console errors that bubble up from extension
    // loads in test mode — they don't affect the gate logic.
    page.on('pageerror', () => {});

    // OnboardingGate is wired into /new (and the rest of /app) but the
    // /onboarding route itself doesn't gate. We hit /new so the gate fires
    // and observe the redirect.
    await page.goto('/new');
    await page.waitForURL(/\/onboarding/, { timeout: 15000 });

    // ---- Step 1 — welcome -------------------------------------------------
    await expect(page.getByTestId('first-run-step-welcome')).toBeVisible();
    await expect(page.getByTestId('first-run-welcome')).toBeVisible();
    await page.getByTestId('first-run-next-btn').click();

    // ---- Step 2 — provider select (Vultr) ---------------------------------
    await expect(page.getByTestId('first-run-step-provider')).toBeVisible();
    const nextBtn = page.getByTestId('first-run-next-btn');
    // Next is disabled until a provider is picked.
    await expect(nextBtn).toBeDisabled();
    await page.getByTestId('first-run-provider-vultr').click();
    await expect(nextBtn).toBeEnabled();
    await nextBtn.click();

    // ---- Step 3 — credentials form ---------------------------------------
    await expect(page.getByTestId('first-run-step-credentials')).toBeVisible();
    // Vultr's schema has a single `api_key` password field; the input id
    // matches the schema key by convention in ProviderCredentialForm.
    const apiKeyInput = page.locator(
      'input[name="api_key"], input[id*="api_key"], input[placeholder*="API"]'
    );
    await apiKeyInput.first().fill(FAKE_API_KEY);

    // Run the test endpoint — green check shows on success.
    const testBtn = page
      .getByRole('button', { name: /test connection|test credentials|^test$/i })
      .first();
    await testBtn.click();
    // Once the test resolves the wizard advances `testStatus` to "valid"
    // which is what enables the Save button.
    await expect.poll(() => counters.testCalls).toBeGreaterThanOrEqual(1);
    const saveBtn = page.getByTestId('first-run-save-btn');
    await expect(saveBtn).toBeEnabled({ timeout: 10000 });
    await saveBtn.click();

    // Save success surface + counter.
    await expect(page.getByTestId('first-run-save-success')).toBeVisible();
    expect(counters.saveCalls).toBe(1);

    await page.getByTestId('first-run-next-btn').click();

    // ---- Step 4 — seed templates -----------------------------------------
    await expect(page.getByTestId('first-run-step-complete')).toBeVisible();
    await page.getByTestId('first-run-seed-btn').click();
    await expect(page.getByTestId('first-run-seed-success')).toBeVisible();
    expect(counters.completeCalls).toBe(1);

    // After completion the wizard auto-navigates via useEffect; flip the
    // status mock so the OnboardingGate on /new doesn't bounce us back.
    status = {
      completed: true,
      has_credentials: true,
      completed_at: new Date().toISOString(),
    };

    await page.waitForURL(/\/new/, { timeout: 15000 });

    // ---- Second visit — should NOT redirect ------------------------------
    await page.goto('/new');
    // Give the gate a beat to run; if it were going to bounce, it would have
    // by now. We don't have a deterministic "gate done" event so we
    // explicitly assert we're still at /new and the wizard's testid is gone.
    await page.waitForLoadState('networkidle').catch(() => undefined);
    await expect(page).toHaveURL(/\/new/);
    await expect(page.getByTestId('first-run-wizard')).toHaveCount(0);
  });

  test('Vultr API key field is masked (password input)', async ({ page }) => {
    let status: OnboardingStatus = {
      completed: false,
      has_credentials: false,
      completed_at: null,
    };
    await stubOnboardingApis(page, () => status);
    page.on('pageerror', () => {});

    await page.goto('/onboarding');
    await page.getByTestId('first-run-next-btn').click();
    await page.getByTestId('first-run-provider-vultr').click();
    await page.getByTestId('first-run-next-btn').click();

    const apiKeyInput = page.locator(
      'input[name="api_key"], input[id*="api_key"]'
    );
    await expect(apiKeyInput.first()).toHaveAttribute('type', 'password');
    // Reference status to keep the lint flag happy across rebuilds.
    void status;
  });
});
