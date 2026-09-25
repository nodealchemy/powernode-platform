import { readFileSync } from 'fs';
import { join } from 'path';
import { matchRoutes } from 'react-router-dom';

/**
 * DashboardPage route-table regression test (fc-46 review, item 1).
 *
 * `/ai/agents/community` was registered as an EXACT route, so any sub-path
 * under it (`/ai/agents/community/federation`) never matched that route at
 * all — React Router fell through to `/ai/agents/:agentId/*` instead, with
 * `agentId="community"`, opening AgentDetailPage rather than the Community
 * tab. `DashboardPage.route-guards.test.ts` covers a DIFFERENT property
 * (a route staying permission-wrapped) with a source regex; this test goes
 * through React Router's own `matchRoutes` against the routes as they
 * actually appear in DashboardPage.tsx, so a route that regains an exact
 * path (or a competing route that outranks it) fails here even though no
 * source regex would notice.
 *
 * Routes are EXTRACTED from the real file, not hand-copied, so this can't
 * drift from what DashboardPage.tsx actually declares. Excludes the
 * featureRegistry-driven block (`path={route.path}`, a runtime expression,
 * not a literal `path="..."`) — those are extension-owned routes, verified
 * by each extension's own tests, not this file's static route table.
 */

const DASHBOARD_SRC = readFileSync(join(__dirname, 'DashboardPage.tsx'), 'utf8');

interface ExtractedRoute {
  path: string;
  component: string;
}

function extractStaticRoutes(src: string): ExtractedRoute[] {
  const routeRe = /<Route\s+path="([^"]+)"\s+element=\{([\s\S]*?)\}\s*\/>/g;
  const routes: ExtractedRoute[] = [];
  let m: RegExpExecArray | null;
  while ((m = routeRe.exec(src))) {
    const [, path, elementBody] = m;
    // The component that actually renders is the INNERMOST JSX tag in the
    // element body — a plain `<Foo />`, or the `<Foo />` inside a
    // `<ProtectedRoute ...><Foo /></ProtectedRoute>` wrapper. Component tags
    // are capitalized by convention; the last one opened is the innermost.
    const tagNames = [...elementBody.matchAll(/<([A-Z]\w*)/g)].map((t) => t[1]);
    routes.push({ path, component: tagNames[tagNames.length - 1] ?? '' });
  }
  return routes;
}

const routes = extractStaticRoutes(DASHBOARD_SRC);

// matchRoutes needs RouteObject[]; the component name rides along as `id`
// so a match can be traced back to what actually renders.
function resolvedComponent(pathname: string): string | undefined {
  const routeObjects = routes.map((r) => ({ path: r.path, id: r.component }));
  const matches = matchRoutes(routeObjects, pathname);
  if (!matches || matches.length === 0) return undefined;
  // The LAST entry in the match chain is the deepest/most specific match —
  // the one React Router actually renders for this pathname.
  return matches[matches.length - 1].route.id;
}

describe('DashboardPage route table (fc-46 review): a deep link resolves to the intended page', () => {
  it('extracted a realistic number of static routes (sanity — the extraction actually ran)', () => {
    expect(routes.length).toBeGreaterThan(50);
  });

  it('/ai/agents/community/federation resolves to AIAgentsPage, not AgentDetailPage', () => {
    expect(resolvedComponent('/ai/agents/community/federation')).toBe('AIAgentsPage');
  });

  it('/ai/agents/community (bare) resolves to AIAgentsPage', () => {
    expect(resolvedComponent('/ai/agents/community')).toBe('AIAgentsPage');
  });

  it('a real agent id still resolves to AgentDetailPage, unaffected by the community fix', () => {
    expect(resolvedComponent('/ai/agents/some-real-agent-id')).toBe('AgentDetailPage');
  });

  // The other fc-46 conversions all live under an ALREADY-wildcarded parent
  // route at this level (/ai/execution/*, /ai/knowledge/*,
  // /ai/infrastructure/*, /ai/observability/*) — checked here so a future
  // narrowing of one of those wildcards is caught the same way.
  it.each([
    ['/ai/infrastructure/model-router/decisions', 'InfrastructurePage'],
    ['/ai/infrastructure/mcp-apps/configure', 'InfrastructurePage'],
    ['/ai/knowledge/rag/query', 'KnowledgePage'],
    ['/ai/knowledge/graph/hybrid-search', 'KnowledgePage'],
    ['/ai/observability/evaluation/benchmarks', 'ObservabilityPage'],
    ['/ai/execution/loop/abc-123/iterations', 'ExecutionPage'],
  ])('%s resolves to %s', (pathname, expected) => {
    expect(resolvedComponent(pathname)).toBe(expected);
  });
});
