import { screen, fireEvent, waitFor } from '@testing-library/react';
import { Routes, Route } from 'react-router-dom';
import { render } from '@/test-utils';
import { McpPage } from '../McpPage';

// fc-43: AI → Platform → MCP. The former Infrastructure hub's four MCP tabs
// (servers, apps, studio, sessions) are one MCP page, each tab at its own
// path and gated like its endpoints.

jest.mock('@/pages/app/ai/McpBrowserPage', () => ({ McpBrowserContent: () => <div data-testid="servers-panel" /> }));
jest.mock('@/features/ai/mcp-apps', () => ({ McpAppsContent: () => <div data-testid="apps-panel" /> }));
jest.mock('@/features/ai/mcp/components/McpStudioTab', () => ({ McpStudioTab: () => <div data-testid="studio-panel" /> }));
jest.mock('@/features/ai/mcp-server/components/McpSessionsTab', () => ({
  McpSessionsTab: () => <div data-testid="sessions-panel" />,
}));

const ALL = ['mcp.servers.read', 'ai.agents.read'];

const renderAt = (path: string, permissions: string[] = ALL) => {
  window.history.pushState({}, '', path);
  return render(
    <Routes>
      <Route path="/app/ai/mcp/*" element={<McpPage />} />
    </Routes>,
    { preloadedState: { auth: { user: { id: 'u1', permissions }, isAuthenticated: true, isLoading: false } } },
  );
};

describe('McpPage (fc-43)', () => {
  it('is titled MCP and has Servers, Apps, Studio and Sessions', () => {
    renderAt('/app/ai/mcp');

    expect(screen.getByRole('heading', { name: 'MCP' })).toBeInTheDocument();
    expect(screen.getAllByRole('tab').map((t) => t.textContent?.trim())).toEqual(['Servers', 'Apps', 'Studio', 'Sessions']);
  });

  it.each([
    ['/app/ai/mcp', 'servers-panel'],
    ['/app/ai/mcp/apps', 'apps-panel'],
    ['/app/ai/mcp/apps/configure', 'apps-panel'],
    ['/app/ai/mcp/studio', 'studio-panel'],
    ['/app/ai/mcp/sessions', 'sessions-panel'],
  ])('%s renders its tab', (path, testId) => {
    renderAt(path);

    expect(screen.getByTestId(testId)).toBeInTheDocument();
  });

  it('navigates between tabs by path', async () => {
    renderAt('/app/ai/mcp');

    fireEvent.click(screen.getByRole('tab', { name: 'Sessions' }));

    await waitFor(() => expect(window.location.pathname).toBe('/app/ai/mcp/sessions'));
  });

  it('shows only the tabs the viewer may read', () => {
    renderAt('/app/ai/mcp/studio', ['ai.agents.read']);

    expect(screen.getAllByRole('tab').map((t) => t.textContent?.trim())).toEqual(['Apps', 'Sessions']);
    expect(screen.queryByTestId('studio-panel')).not.toBeInTheDocument();
    expect(screen.getByTestId('apps-panel')).toBeInTheDocument();
  });
});
