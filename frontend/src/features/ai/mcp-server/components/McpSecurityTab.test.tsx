import { screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@/test-utils';
import { McpSecurityTab } from './McpSecurityTab';

// IMP-cdda895b07a8 — the stdio sandbox capabilities. Visible to mcp.servers.read,
// editable only with mcp.servers.security_manage (a permission, never a role),
// and the form shows the server's own validation message instead of re-checking.

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), patch: jest.fn() },
}));
import { apiClient } from '@/shared/services/apiClient';

const servers = [
  {
    id: 's1', name: 'Filesystem', status: 'connected', connection_type: 'stdio', command: 'npx',
    security: { allow_network: false, allow_extended_commands: false, egress_allowlist: ['api.example.test'] },
  },
  {
    id: 's2', name: 'Fetcher', status: 'disconnected', connection_type: 'stdio', command: 'uvx',
    security: { allow_network: true, allow_extended_commands: true, egress_allowlist: [] },
  },
];

const renderTab = (permissions: string[]) =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <McpSecurityTab />
    </QueryClientProvider>,
    {
      preloadedState: { auth: { user: { id: 'u1', permissions }, isAuthenticated: true, isLoading: false } },
    },
  );

describe('McpSecurityTab', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (apiClient.get as jest.Mock).mockResolvedValue({ data: { data: { mcp_servers: servers } } });
    (apiClient.patch as jest.Mock).mockResolvedValue({ data: { data: {} } });
  });

  it('asks only for stdio servers and summarizes each one\'s settings', async () => {
    renderTab(['mcp.servers.read']);

    expect(await screen.findByText('Filesystem')).toBeInTheDocument();
    expect(apiClient.get).toHaveBeenCalledWith('/mcp_servers', { params: { connection_type: 'stdio' } });
    expect(screen.getByText(/Network: allowlist \(1\)/)).toBeInTheDocument();
    expect(screen.getByText(/Network: unrestricted/)).toBeInTheDocument();
    expect(screen.getByText(/Extended commands: allowed/)).toBeInTheDocument();
  });

  it('is read-only without mcp.servers.security_manage: no Edit control, and it says why', async () => {
    renderTab(['mcp.servers.read', 'mcp.servers.write']);

    await screen.findByText('Filesystem');
    expect(screen.queryByRole('button', { name: 'Edit' })).not.toBeInTheDocument();
    expect(screen.getByText(/changing them needs the/i)).toBeInTheDocument();
  });

  it('does not treat a role-like permission as the gate: mcp.servers.write alone cannot edit', async () => {
    renderTab(['mcp.servers.write']);

    await screen.findByText('Filesystem');
    expect(screen.queryByRole('button', { name: 'Edit' })).not.toBeInTheDocument();
  });

  it('with the permission, edits one server and sends exactly the three settings', async () => {
    renderTab(['mcp.servers.read', 'mcp.servers.security_manage']);

    await screen.findByText('Filesystem');
    fireEvent.click(screen.getAllByRole('button', { name: 'Edit' })[0]);
    const editor = screen.getByTestId('security-editor-s1');
    expect(editor).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('Egress allowlist'), { target: { value: 'api.example.test\n203.0.113.7, 198.51.100.0/24\n' } });
    fireEvent.click(screen.getByLabelText('Allow extended commands'));
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(apiClient.patch).toHaveBeenCalledWith('/mcp_servers/s1/security', {
        security: {
          allow_network: false,
          allow_extended_commands: true,
          egress_allowlist: ['api.example.test', '203.0.113.7', '198.51.100.0/24'],
        },
      }),
    );
  });

  it('blocks Save while allow network and an allowlist are both set', async () => {
    renderTab(['mcp.servers.read', 'mcp.servers.security_manage']);

    await screen.findByText('Filesystem');
    fireEvent.click(screen.getAllByRole('button', { name: 'Edit' })[0]);
    fireEvent.click(screen.getByLabelText('Allow network access'));

    expect(screen.getByRole('alert')).toHaveTextContent(/cannot both be set/i);
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
  });

  it("shows the server's own validation message and keeps the editor open when the save is refused", async () => {
    (apiClient.patch as jest.Mock).mockRejectedValue({
      response: { data: { error: 'egress_allowlist entry "127.0.0.1" falls within a forbidden range' } },
    });
    renderTab(['mcp.servers.read', 'mcp.servers.security_manage']);

    await screen.findByText('Filesystem');
    fireEvent.click(screen.getAllByRole('button', { name: 'Edit' })[0]);
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(await screen.findByText(/falls within a forbidden range/)).toBeInTheDocument();
    expect(screen.getByTestId('security-editor-s1')).toBeInTheDocument();
  });

  it('closes the editor on Cancel without calling the API', async () => {
    renderTab(['mcp.servers.read', 'mcp.servers.security_manage']);

    await screen.findByText('Filesystem');
    fireEvent.click(screen.getAllByRole('button', { name: 'Edit' })[0]);
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(screen.queryByTestId('security-editor-s1')).not.toBeInTheDocument();
    expect(apiClient.patch).not.toHaveBeenCalled();
  });

  it('says so when there are no stdio servers', async () => {
    (apiClient.get as jest.Mock).mockResolvedValue({ data: { data: { mcp_servers: [] } } });
    renderTab(['mcp.servers.read']);

    expect(await screen.findByText('No stdio MCP servers.')).toBeInTheDocument();
  });
});
