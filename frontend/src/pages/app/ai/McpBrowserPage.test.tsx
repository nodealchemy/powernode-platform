import { screen } from '@testing-library/react';
import { render } from '@/test-utils';
import { McpBrowserContent } from './McpBrowserPage';

// loadData() calls mcpApi.getServers(); resolve it so the statistics grid renders.
jest.mock('@/shared/services/ai/McpApiService', () => ({
  mcpApi: {
    getServers: jest.fn().mockResolvedValue({ servers: [], tools: [] }),
    createServer: jest.fn(),
    updateServer: jest.fn(),
    deleteServer: jest.fn(),
    connectServer: jest.fn(),
    disconnectServer: jest.fn(),
    executeTool: jest.fn(),
    refreshCapabilities: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: { id: 'u1', permissions: ['mcp.servers.read'] },
  }),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({
  usePageWebSocket: jest.fn(),
}));

describe('McpBrowserPage statistics grid — semantic theme tokens (IMP-5a8f7c7ab930)', () => {
  it('renders the "Total Servers" stat icon chip with a semantic status token, not the interactive-primary affordance token', async () => {
    render(<McpBrowserContent />);

    // The four stat cards share one icon-chip role; siblings use success/info/warning.
    const label = await screen.findByText('Total Servers');
    const row = label.closest('div.flex');
    expect(row).toBeTruthy();

    const iconChip = row!.querySelector('div.rounded-lg');
    expect(iconChip).toBeTruthy();

    // Regression guard: this chip must NOT use the interactive-primary action/affordance
    // token (the "solid blue" odd-one-out among status-colored peers), and SHOULD use the
    // semantic informational token like its siblings.
    expect(iconChip!.className).not.toMatch(/theme-interactive-primary/);
    expect(iconChip!.className).toMatch(/bg-theme-info/);
  });
});
