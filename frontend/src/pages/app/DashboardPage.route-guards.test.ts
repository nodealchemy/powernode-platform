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

// fc-41: AI → Control replaces the Autonomy dashboard, the Governance page,
// the Approval Chains page and the standalone Budgets page. It is guarded on
// CONTROL_PERMISSIONS (every permission some leaf of it is gated on), and the
// routes it replaced are gone — no redirects.
describe('DashboardPage route guards — Control (fc-41)', () => {
  it('/ai/control/* renders ControlPage behind CONTROL_PERMISSIONS', () => {
    const element = protectedRouteElement('/ai/control/\\*');
    expect(element).toMatch(/^<ProtectedRoute\s+requiredPermissions=\{CONTROL_PERMISSIONS\}><ControlPage \/><\/ProtectedRoute>$/);
    expect(DASHBOARD_SRC).toMatch(/import \{ CONTROL_PERMISSIONS \} from '@\/features\/ai\/control\/controlPaths';/);
  });

  it.each(['/ai/governance', '/ai/approval-chains', '/ai/agents/autonomy', '/ai/control/budgets'])(
    'no longer routes %s',
    (path) => {
      expect(DASHBOARD_SRC).not.toContain(`path="${path}`);
    },
  );

  it('no longer mounts the pages Control replaced', () => {
    expect(DASHBOARD_SRC).not.toMatch(/GovernancePage|ApprovalChainsPage|BudgetsPage/);
  });
});
