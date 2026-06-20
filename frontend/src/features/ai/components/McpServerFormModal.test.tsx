import { render, screen } from '@testing-library/react';
import { McpServerFormModal } from './McpServerFormModal';
import type { McpServer } from '@/pages/app/ai/McpBrowserPage';

// Regression for the edit-mode data-loss bug: opening the edit modal used to
// hard-reset command/args to empty, so saving wiped an external server's
// command/URL/args. The modal must now pre-fill the connection config it was
// given so a round-trip edit preserves it.

const baseServer: McpServer = {
  id: 'srv-1',
  name: 'My Server',
  description: 'A test server',
  version: '1.0.0',
  protocol_version: '2025-06-18',
  status: 'connected',
  connection_type: 'stdio',
  capabilities: {},
  tools_count: 0,
  resources_count: 0,
  prompts_count: 0,
  command: 'node',
  args: ['server.js', '--port', '3000'],
};

const COMMAND_PLACEHOLDER = 'e.g., node, python, /usr/local/bin/mcp-server';

describe('McpServerFormModal edit-mode pre-fill (data-loss regression)', () => {
  it('pre-fills the stdio command from the server being edited', () => {
    render(
      <McpServerFormModal isOpen onClose={jest.fn()} onSubmit={jest.fn()} server={baseServer} />
    );

    const commandInput = screen.getByPlaceholderText(COMMAND_PLACEHOLDER) as HTMLInputElement;
    expect(commandInput.value).toBe('node');
  });

  it('pre-fills the stdio args from the server being edited', () => {
    render(
      <McpServerFormModal isOpen onClose={jest.fn()} onSubmit={jest.fn()} server={baseServer} />
    );

    // StdioConfigFields renders one input per argument, bound to its value.
    expect(screen.getByDisplayValue('server.js')).toBeInTheDocument();
    expect(screen.getByDisplayValue('--port')).toBeInTheDocument();
    expect(screen.getByDisplayValue('3000')).toBeInTheDocument();
  });

  it('pre-fills the http/websocket URL (stored in command) when editing', () => {
    const httpServer: McpServer = {
      ...baseServer,
      connection_type: 'http',
      command: 'https://example.com/mcp',
      url: 'https://example.com/mcp',
    };

    render(
      <McpServerFormModal isOpen onClose={jest.fn()} onSubmit={jest.fn()} server={httpServer} />
    );

    // WebSocketConfigFields renders the URL input bound to `command`.
    expect(screen.getByDisplayValue('https://example.com/mcp')).toBeInTheDocument();
  });

  it('leaves the form blank when creating (no server)', () => {
    render(
      <McpServerFormModal isOpen onClose={jest.fn()} onSubmit={jest.fn()} server={null} />
    );

    const commandInput = screen.getByPlaceholderText(COMMAND_PLACEHOLDER) as HTMLInputElement;
    expect(commandInput.value).toBe('');
  });
});
