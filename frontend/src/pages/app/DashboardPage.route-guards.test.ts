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
