import { readFileSync, readdirSync } from 'fs';
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
  // route at this level (/ai/execution/*, /ai/knowledge/*, /ai/model-router/*,
  // /ai/mcp/*, /ai/observability/*) — checked here so a future narrowing of
  // one of those wildcards is caught the same way. (fc-43 split the former
  // /ai/infrastructure/* hub into Model Router and MCP.)
  it.each([
    ['/ai/model-router/decisions', 'ModelRouterPage'],
    ['/ai/mcp/apps/configure', 'McpPage'],
    ['/ai/knowledge/rag/query', 'KnowledgePage'],
    ['/ai/knowledge/graph/hybrid-search', 'KnowledgePage'],
    ['/ai/observability/evaluation/benchmarks', 'ObservabilityPage'],
    ['/ai/execution/loop/abc-123/iterations', 'ExecutionPage'],
  ])('%s resolves to %s', (pathname, expected) => {
    expect(resolvedComponent(pathname)).toBe(expected);
  });
});

describe('DashboardPage route table (fc-44): the regrouped DevOps URLs resolve to the intended page', () => {
  it.each([
    ['/devops/integrations', 'IntegrationsWebhooksPage'],
    ['/devops/integrations/webhook-endpoints', 'IntegrationsWebhooksPage'],
    ['/devops/integrations/new', 'NewIntegrationPage'],
    ['/devops/integrations/new/some-template', 'NewIntegrationPage'],
    ['/devops/integrations/some-integration-id', 'IntegrationDetailPage'],
    ['/devops/integrations/some-integration-id/executions', 'IntegrationDetailPage'],
    ['/devops/api-keys', 'ApiKeysPage'],
    ['/devops/containers', 'ContainersHubPage'],
    ['/devops/containers/docker/some-host/containers/some-container', 'ContainersHubPage'],
  ])('%s resolves to %s', (pathname, expected) => {
    expect(resolvedComponent(pathname)).toBe(expected);
  });

  // fc-44 review blocker: six links pointed at /app/devops/integrations/integrations,
  // which the :id detail route swallows (id="integrations"), opening a
  // "doesn't exist" detail page whose Back link looped to the same URL. Any
  // STATIC /app/devops/integrations/<word> link literal in the frontend must
  // resolve to something other than the detail page.
  it('no static /app/devops/integrations/<word> link resolves to IntegrationDetailPage', () => {
    const srcRoot = join(__dirname, '..', '..');
    const linkRe = /['"`](\/app\/devops\/integrations\/[a-z][a-z-]*)(?=['"`/?])/g;
    const found = new Set<string>();
    const walk = (dir: string): void => {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
          if (entry.name !== 'node_modules') walk(full);
        } else if (/\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name)) {
          for (const m of readFileSync(full, 'utf8').matchAll(linkRe)) found.add(m[1]);
        }
      }
    };
    walk(srcRoot);
    const words = [...found];
    expect(words.length).toBeGreaterThan(0);

    const swallowed = words.filter((p) => resolvedComponent(p.replace(/^\/app/, '')) === 'IntegrationDetailPage');
    expect(swallowed).toEqual([]);
  });
});

describe('DashboardPage route table (fc-43): the AI Agents / Work / Platform regroup', () => {
  it.each([
    // One agent detail page; its Memory tab is at the old memory URLs.
    ['/ai/agents/some-agent-id/memory', 'AgentDetailPage'],
    ['/ai/agents/some-agent-id/memory/pools', 'AgentDetailPage'],
    ['/ai/agents/some-agent-id/history', 'AgentDetailPage'],
    // Skills and Prompts left the Knowledge hub for their own AI Agents items.
    ['/ai/skills', 'SkillsPage'],
    ['/ai/skills/graph', 'SkillsPage'],
    ['/ai/prompts', 'PromptsPage'],
    // Learning Insights folded into Knowledge › Learning.
    ['/ai/knowledge/learning', 'KnowledgePage'],
    ['/ai/knowledge/learning/recommendations', 'KnowledgePage'],
    ['/ai/knowledge/learning/insights', 'KnowledgePage'],
    // AI Platform: the Infrastructure hub split into its own items, and its
    // MCP tabs became the MCP hub.
    ['/ai/providers', 'ProvidersPage'],
    ['/ai/data-sources', 'DataSourcesPage'],
    ['/ai/model-router', 'ModelRouterPage'],
    ['/ai/mcp', 'McpPage'],
    ['/ai/mcp/apps', 'McpPage'],
    ['/ai/mcp/studio', 'McpPage'],
    ['/ai/mcp/sessions', 'McpPage'],
  ])('%s resolves to %s', (pathname, expected) => {
    expect(resolvedComponent(pathname)).toBe(expected);
  });

  // Deleted, never redirected: nothing may still answer at the old paths.
  it.each([
    '/ai/learning',
    '/ai/learning/insights',
    '/ai/infrastructure',
    '/ai/infrastructure/data-sources',
    '/ai/infrastructure/mcp',
    '/ai/infrastructure/mcp-apps',
    '/ai/infrastructure/mcp-studio',
    '/ai/infrastructure/mcp-sessions',
    '/ai/infrastructure/model-router',
  ])('%s no longer resolves to any page', (pathname) => {
    expect(resolvedComponent(pathname)).toBeUndefined();
  });
});
