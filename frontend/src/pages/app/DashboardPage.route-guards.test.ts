import { readFileSync } from 'fs';
import { join } from 'path';

/**
 * Route-guard regression test for C15 G5 (review-lane4-c15.md): `/ai/conversations`
 * and `/ai/chat-channels` were routed with no `ProtectedRoute` wrapper at all —
 * typing the URL without the permission got the page shell plus failing API
 * calls, unlike the other 21 permission-guarded routes in this file. Both were
 * fixed to wrap in `ProtectedRoute requiredPermissions={[...]}` matching what
 * the backend controller actually enforces (`ai.conversations.read` /
 * `chat.channels.read`), but nothing asserted it stays that way — the
 * review's own mutant (MG5: delete both wrappers) left the rest of the suite
 * green. This is a static source check, not a render test, because mounting
 * DashboardPage requires the full app provider tree; a regex on the route
 * declaration is enough to catch the wrapper (or the permission) disappearing.
 */

const DASHBOARD_SRC = readFileSync(join(__dirname, 'DashboardPage.tsx'), 'utf8');

function protectedRouteElement(path: string): string {
  const routeRe = new RegExp(`<Route\\s+path="${path.replace(/\//g, '\\/')}"\\s+element=\\{([\\s\\S]*?)\\}\\s*/>`);
  const match = DASHBOARD_SRC.match(routeRe);
  expect(match).not.toBeNull();
  return match![1];
}

describe('DashboardPage route guards (C15 G5)', () => {
  it('/ai/conversations requires ai.conversations.read', () => {
    const element = protectedRouteElement('/ai/conversations');
    expect(element).toMatch(/<ProtectedRoute\s+requiredPermissions=\{\['ai\.conversations\.read'\]\}>/);
  });

  it('/ai/chat-channels requires chat.channels.read', () => {
    const element = protectedRouteElement('/ai/chat-channels');
    expect(element).toMatch(/<ProtectedRoute\s+requiredPermissions=\{\['chat\.channels\.read'\]\}>/);
  });
});

// fc-31: the one Budgets page. Its route guard is the permission the list
// endpoint (GET /api/v1/ai/autonomy/budgets) checks, and it must be the same
// permission the sidebar item carries — a nav item the route then refuses, or
// a route the nav hides, is the mismatch this pins.
describe('DashboardPage route guards — Budgets (fc-31)', () => {
  it('/ai/control/budgets renders BudgetsPage behind ai.agents.read', () => {
    const element = protectedRouteElement('/ai/control/budgets');
    expect(element).toMatch(/^<ProtectedRoute\s+requiredPermissions=\{\['ai\.agents\.read'\]\}><BudgetsPage \/><\/ProtectedRoute>$/);
  });

  it('is the only route to the Budgets page', () => {
    expect(DASHBOARD_SRC.match(/<BudgetsPage \/>/g)).toHaveLength(1);
  });
});
