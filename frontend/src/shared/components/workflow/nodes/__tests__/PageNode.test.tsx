import { render, screen } from '@testing-library/react';
import { PageNode } from '../PageNode';

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
  id: 'test-page-node-1',
  type: 'page' as const,
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

describe('PageNode', () => {
  describe('Action: Create', () => {
    it('renders create action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Create Page',
          description: 'Create a new page',
          configuration: {
            action: 'create' as const,
            title: 'Test Page',
            slug: 'test-page',
            status: 'draft' as const,
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('Create Page')).toBeInTheDocument();
      expect(screen.getByText('PAGE')).toBeInTheDocument();
      expect(screen.getByText('Title:')).toBeInTheDocument();
      expect(screen.getByText('Test Page')).toBeInTheDocument();
    });

    it('displays slug when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Create Page',
          configuration: {
            action: 'create' as const,
            title: 'Test Page',
            slug: 'my-test-page',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('Slug:')).toBeInTheDocument();
      expect(screen.getByText('/my-test-page')).toBeInTheDocument();
    });

    it('displays status badge for create action', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Create Page',
          configuration: {
            action: 'create' as const,
            title: 'Test Page',
            status: 'published' as const,
          },
        },
      };

      render(<PageNode {...props} />);
      expect(screen.getByText('published')).toBeInTheDocument();
    });

    it('displays SEO indicator when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Create Page',
          configuration: {
            action: 'create' as const,
            title: 'Test Page',
            meta_description: 'SEO description for the page',
          },
        },
      };

      render(<PageNode {...props} />);
      expect(screen.getByText('SEO configured')).toBeInTheDocument();
    });
  });

  describe('Action: Read', () => {
    it('renders read action correctly with page_id', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Page',
          configuration: {
            action: 'read' as const,
            page_id: 'page-123',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('Read Page')).toBeInTheDocument();
      expect(screen.getByText('ID:')).toBeInTheDocument();
      expect(screen.getByText('page-123')).toBeInTheDocument();
    });

    it('renders read action correctly with slug', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Page',
          configuration: {
            action: 'read' as const,
            slug: 'about-us',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('Read Page')).toBeInTheDocument();
      expect(screen.getByText('slug:')).toBeInTheDocument();
      expect(screen.getByText('about-us')).toBeInTheDocument();
    });

    it('displays output variable when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Page',
          configuration: {
            action: 'read' as const,
            page_id: 'page-123',
            output_variable: 'page_content',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('Output Variable:')).toBeInTheDocument();
      expect(screen.getByText('page_content')).toBeInTheDocument();
    });
  });

  describe('Action: Update', () => {
    it('renders update action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Update Page',
          configuration: {
            action: 'update' as const,
            page_id: 'page-456',
            title: 'Updated Page Title',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('Update Page')).toBeInTheDocument();
      expect(screen.getByText('page-456')).toBeInTheDocument();
      expect(screen.getByText('New Title:')).toBeInTheDocument();
      expect(screen.getByText('Updated Page Title')).toBeInTheDocument();
    });

    it('displays status change when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Update Page',
          configuration: {
            action: 'update' as const,
            page_id: 'page-456',
            status: 'published' as const,
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('published')).toBeInTheDocument();
    });
  });

  describe('Action: Publish', () => {
    it('renders publish action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Publish Page',
          configuration: {
            action: 'publish' as const,
            page_id: 'page-789',
          },
        },
      };

      render(<PageNode {...props} />);

      // There will be two "Publish Page" texts - one in header, one in the action indicator
      const publishTexts = screen.getAllByText('Publish Page');
      expect(publishTexts.length).toBeGreaterThanOrEqual(1);
      expect(screen.getByText('page-789')).toBeInTheDocument();
    });
  });

  describe('Common Features', () => {
    it('shows "No configuration set" when unconfigured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Page',
          configuration: {
            action: 'create' as const,
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('No configuration set')).toBeInTheDocument();
    });

    it('applies selected styling when selected', () => {
      const props = {
        ...baseNodeProps,
        selected: true,
        data: {
          name: 'Page',
          configuration: {
            action: 'create' as const,
            title: 'Test',
          },
        },
      };

      const { container } = render(<PageNode {...props} />);

      expect(container.querySelector('.border-theme-interactive-primary')).toBeInTheDocument();
    });

    it('renders execution status badge when present', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Page',
          executionStatus: 'success' as const,
          configuration: {
            action: 'create' as const,
            title: 'Test',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByTestId('node-status-badge')).toBeInTheDocument();
    });

    it('renders dynamic node handles', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Page',
          configuration: {
            action: 'create' as const,
            title: 'Test',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByTestId('dynamic-node-handles')).toBeInTheDocument();
    });

    it('renders description when provided', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Page',
          description: 'This node creates a new page',
          configuration: {
            action: 'create' as const,
            title: 'Test',
          },
        },
      };

      render(<PageNode {...props} />);

      expect(screen.getByText('This node creates a new page')).toBeInTheDocument();
    });

    it('uses correct action icon for each action type', () => {
      const actions = ['create', 'read', 'update', 'publish'] as const;

      actions.forEach((action) => {
        const props = {
          ...baseNodeProps,
          id: `test-page-node-${action}`,
          data: {
            name: `${action} Page`,
            configuration: {
              action,
              title: 'Test',
              page_id: 'page-123',
            },
          },
        };

        const { container, unmount } = render(<PageNode {...props} />);

        // Each action should render with an icon in the header (h-4 w-4 classes)
        const iconContainer = container.querySelector('.h-4.w-4');
        expect(iconContainer).toBeInTheDocument();

        unmount();
      });
    });
  });
});
