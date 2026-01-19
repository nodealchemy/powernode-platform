import { render, screen } from '@testing-library/react';
import { McpOperationNode } from '../McpOperationNode';

// Mock React Flow
jest.mock('@xyflow/react', () => ({
  useEdges: () => [],
  Handle: ({ type, position, id }: { type: string; position: string; id: string }) => (
    <div data-testid={`handle-${type}-${id}`} data-position={position} />
  ),
  Position: {
    Top: 'top',
    Bottom: 'bottom',
    Left: 'left',
    Right: 'right',
  },
}));

// Mock workflow context
jest.mock('../../WorkflowContext', () => ({
  useWorkflowContext: () => ({
    onOpenChat: jest.fn(),
  }),
}));

// Mock NodeActionsMenu
jest.mock('../../NodeActionsMenu', () => ({
  NodeActionsMenu: () => <div data-testid="node-actions-menu" />,
}));

// Mock DynamicNodeHandles
jest.mock('../DynamicNodeHandles', () => ({
  DynamicNodeHandles: () => <div data-testid="dynamic-node-handles" />,
}));

// Mock ExecutionOverlay
jest.mock('../../ExecutionOverlay', () => ({
  NodeStatusBadge: ({ status }: { status: string }) => (
    <div data-testid="node-status-badge">{status}</div>
  ),
}));

const baseNodeProps = {
  id: 'test-mcp-node-1',
  type: 'mcp_operation' as const,
  dragging: false,
  draggable: true,
  zIndex: 1,
  isConnectable: true,
  positionAbsoluteX: 100,
  positionAbsoluteY: 100,
  deletable: true,
  selectable: true,
  parentId: undefined,
  sourcePosition: undefined,
  targetPosition: undefined,
  dragHandle: undefined,
  selected: false,
  width: 192,
  height: 192,
};

describe('McpOperationNode', () => {
  describe('Operation Type: Tool', () => {
    it('renders tool operation correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Execute Tool',
          description: 'Execute an MCP tool',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'File System Server',
            mcp_tool_name: 'read_file',
            execution_mode: 'sync' as const,
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Execute Tool')).toBeInTheDocument();
      expect(screen.getByText('MCP')).toBeInTheDocument();
      expect(screen.getByText('File System Server')).toBeInTheDocument();
      expect(screen.getByText('read_file')).toBeInTheDocument();
    });

    it('displays synchronous execution mode', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Execute Tool',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
            execution_mode: 'sync' as const,
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Synchronous')).toBeInTheDocument();
    });

    it('displays asynchronous execution mode', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Execute Tool',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
            execution_mode: 'async' as const,
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Asynchronous')).toBeInTheDocument();
    });

    it('displays parameter count when parameters are configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Execute Tool',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
            parameters: {
              path: '/tmp/file.txt',
              encoding: 'utf-8',
            },
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('2 parameters')).toBeInTheDocument();
    });

    it('displays singular parameter text for single parameter', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Execute Tool',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
            parameters: {
              path: '/tmp/file.txt',
            },
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('1 parameter')).toBeInTheDocument();
    });
  });

  describe('Operation Type: Resource', () => {
    it('renders resource operation correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Resource',
          configuration: {
            operation_type: 'resource' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Data Server',
            resource_uri: 'file:///data/config.json',
            resource_name: 'Configuration File',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Read Resource')).toBeInTheDocument();
      expect(screen.getByText('MCP')).toBeInTheDocument();
      expect(screen.getByText('Configuration File')).toBeInTheDocument();
    });

    it('displays truncated URI for long resource URIs', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Resource',
          configuration: {
            operation_type: 'resource' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Data Server',
            resource_uri: 'file:///very/long/path/to/some/nested/directory/structure/file.json',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      // URI should be truncated to 30 chars + '...'
      expect(screen.getByText('file:///very/long/path/to/some...')).toBeInTheDocument();
    });

    it('displays MIME type when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Resource',
          configuration: {
            operation_type: 'resource' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Data Server',
            resource_uri: 'file:///data/config.json',
            mime_type: 'application/json',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('application/json')).toBeInTheDocument();
    });
  });

  describe('Operation Type: Prompt', () => {
    it('renders prompt operation correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Use Prompt',
          configuration: {
            operation_type: 'prompt' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'AI Prompts Server',
            prompt_name: 'summarize_text',
            prompt_description: 'Summarizes the provided text content',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Use Prompt')).toBeInTheDocument();
      expect(screen.getByText('MCP')).toBeInTheDocument();
      expect(screen.getByText('summarize_text')).toBeInTheDocument();
    });

    it('displays prompt description when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Use Prompt',
          configuration: {
            operation_type: 'prompt' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'AI Server',
            prompt_name: 'analyze_data',
            prompt_description: 'Analyzes the provided data set',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Analyzes the provided data set')).toBeInTheDocument();
    });

    it('displays argument count when arguments are configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Use Prompt',
          configuration: {
            operation_type: 'prompt' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'AI Server',
            prompt_name: 'analyze_data',
            arguments: {
              format: 'json',
              language: 'en',
              detail_level: 'high',
            },
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('3 arguments')).toBeInTheDocument();
    });

    it('displays singular argument text for single argument', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Use Prompt',
          configuration: {
            operation_type: 'prompt' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'AI Server',
            prompt_name: 'analyze_data',
            arguments: {
              format: 'json',
            },
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('1 argument')).toBeInTheDocument();
    });
  });

  describe('Common Features', () => {
    it('shows "Not configured" when unconfigured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'MCP Operation',
          configuration: {
            operation_type: 'tool' as const,
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Not configured')).toBeInTheDocument();
    });

    it('displays "No Server" when server name is not configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'MCP Operation',
          configuration: {
            operation_type: 'tool' as const,
            mcp_tool_name: 'test_tool',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('No Server')).toBeInTheDocument();
    });

    it('applies selected styling when selected', () => {
      const props = {
        ...baseNodeProps,
        selected: true,
        data: {
          name: 'MCP Operation',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
          },
        },
      };

      const { container } = render(<McpOperationNode {...props} />);

      expect(container.querySelector('.border-theme-interactive-primary')).toBeInTheDocument();
    });

    it('renders execution status badge when present', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'MCP Operation',
          executionStatus: 'error' as const,
          executionError: 'Connection timeout',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByTestId('node-status-badge')).toBeInTheDocument();
    });

    it('renders end node indicator when marked as end node', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'MCP Operation',
          isEndNode: true,
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
          },
        },
      };

      const { container } = render(<McpOperationNode {...props} />);

      expect(container.querySelector('.bg-theme-danger-solid')).toBeInTheDocument();
    });

    it('renders dynamic node handles', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'MCP Operation',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByTestId('dynamic-node-handles')).toBeInTheDocument();
    });

    it('renders description when provided', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'MCP Operation',
          description: 'Executes an MCP tool operation',
          configuration: {
            operation_type: 'tool' as const,
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('Executes an MCP tool operation')).toBeInTheDocument();
    });

    it('uses correct operation type icon for each type', () => {
      const operationTypes = ['tool', 'resource', 'prompt'] as const;

      operationTypes.forEach((opType) => {
        const props = {
          ...baseNodeProps,
          id: `test-mcp-node-${opType}`,
          data: {
            name: `MCP ${opType}`,
            configuration: {
              operation_type: opType,
              mcp_server_id: 'server-123',
              mcp_server_name: 'Test Server',
              mcp_tool_name: 'test_tool',
              resource_uri: 'file:///test.json',
              prompt_name: 'test_prompt',
            },
          },
        };

        const { container, unmount } = render(<McpOperationNode {...props} />);

        // Each operation type should render with an icon in the header (h-4 w-4 classes)
        const iconContainer = container.querySelector('.h-4.w-4');
        expect(iconContainer).toBeInTheDocument();

        unmount();
      });
    });

    it('defaults to tool operation type when not specified', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'MCP Operation',
          configuration: {
            mcp_server_id: 'server-123',
            mcp_server_name: 'Test Server',
            mcp_tool_name: 'test_tool',
          },
        },
      };

      render(<McpOperationNode {...props} />);

      expect(screen.getByText('MCP')).toBeInTheDocument();
    });
  });
});
