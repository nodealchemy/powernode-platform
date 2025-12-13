import { render, screen } from '@testing-library/react';
import { KbArticleNode } from '../KbArticleNode';

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
  id: 'test-node-1',
  type: 'kb_article' as const,
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

describe('KbArticleNode', () => {
  describe('Action: Create', () => {
    it('renders create action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Create Article',
          description: 'Create a new KB article',
          configuration: {
            action: 'create' as const,
            title: 'Test Article',
            category_id: 'cat-123',
            status: 'draft' as const,
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('Create Article')).toBeInTheDocument();
      expect(screen.getByText('KB ARTICLE')).toBeInTheDocument();
      expect(screen.getByText('Title:')).toBeInTheDocument();
      expect(screen.getByText('Test Article')).toBeInTheDocument();
    });

    it('displays status badge for create action', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Create Article',
          configuration: {
            action: 'create' as const,
            title: 'Test Article',
            status: 'published' as const,
          },
        },
      };

      render(<KbArticleNode {...props} />);
      expect(screen.getByText('published')).toBeInTheDocument();
    });

    it('displays tags when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Create Article',
          configuration: {
            action: 'create' as const,
            title: 'Test Article',
            tags: ['documentation', 'help'],
          },
        },
      };

      render(<KbArticleNode {...props} />);
      expect(screen.getByText('documentation')).toBeInTheDocument();
      expect(screen.getByText('help')).toBeInTheDocument();
    });
  });

  describe('Action: Read', () => {
    it('renders read action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Article',
          configuration: {
            action: 'read' as const,
            article_id: 'article-123',
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('Read Article')).toBeInTheDocument();
      expect(screen.getByText('ID:')).toBeInTheDocument();
      expect(screen.getByText('article-123')).toBeInTheDocument();
    });

    it('displays slug when provided instead of ID', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Read Article',
          configuration: {
            action: 'read' as const,
            article_slug: 'test-article-slug',
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('slug:')).toBeInTheDocument();
      expect(screen.getByText('test-article-slug')).toBeInTheDocument();
    });
  });

  describe('Action: Update', () => {
    it('renders update action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Update Article',
          configuration: {
            action: 'update' as const,
            article_id: 'article-456',
            title: 'Updated Title',
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('Update Article')).toBeInTheDocument();
      expect(screen.getByText('article-456')).toBeInTheDocument();
    });
  });

  describe('Action: Search', () => {
    it('renders search action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Search Articles',
          configuration: {
            action: 'search' as const,
            query: 'how to configure',
            limit: 10,
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('Search Articles')).toBeInTheDocument();
      expect(screen.getByText('Query:')).toBeInTheDocument();
      expect(screen.getByText('"how to configure"')).toBeInTheDocument();
    });

    it('displays filters when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Search Articles',
          configuration: {
            action: 'search' as const,
            category_id: 'cat-123',
            status: 'published' as const,
            tags: ['help'],
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('Filters:')).toBeInTheDocument();
      expect(screen.getByText('Category')).toBeInTheDocument();
      expect(screen.getByText('Status')).toBeInTheDocument();
      expect(screen.getByText('Tags')).toBeInTheDocument();
    });

    it('displays sort order when configured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Search Articles',
          configuration: {
            action: 'search' as const,
            sort_by: 'popular' as const,
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('Sort:')).toBeInTheDocument();
      expect(screen.getByText('Popular')).toBeInTheDocument();
    });
  });

  describe('Action: Publish', () => {
    it('renders publish action correctly', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'Publish Article',
          configuration: {
            action: 'publish' as const,
            article_id: 'article-789',
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('Publish Article')).toBeInTheDocument();
      expect(screen.getByText('Publish to KB')).toBeInTheDocument();
      expect(screen.getByText('article-789')).toBeInTheDocument();
    });
  });

  describe('Common Features', () => {
    it('shows "No configuration set" when unconfigured', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'KB Article',
          configuration: {
            action: 'create' as const,
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByText('No configuration set')).toBeInTheDocument();
    });

    it('applies selected styling when selected', () => {
      const props = {
        ...baseNodeProps,
        selected: true,
        data: {
          name: 'KB Article',
          configuration: {
            action: 'create' as const,
            title: 'Test',
          },
        },
      };

      const { container } = render(<KbArticleNode {...props} />);

      expect(container.querySelector('.border-theme-interactive-primary')).toBeInTheDocument();
    });

    it('renders execution status badge when present', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'KB Article',
          executionStatus: 'running' as const,
          configuration: {
            action: 'create' as const,
            title: 'Test',
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByTestId('node-status-badge')).toBeInTheDocument();
    });

    it('renders dynamic node handles', () => {
      const props = {
        ...baseNodeProps,
        data: {
          name: 'KB Article',
          configuration: {
            action: 'create' as const,
            title: 'Test',
          },
        },
      };

      render(<KbArticleNode {...props} />);

      expect(screen.getByTestId('dynamic-node-handles')).toBeInTheDocument();
    });

    it('uses correct action icon for each action type', () => {
      const actions = ['create', 'read', 'update', 'search', 'publish'] as const;

      actions.forEach((action) => {
        const props = {
          ...baseNodeProps,
          id: `test-node-${action}`,
          data: {
            name: `${action} Article`,
            configuration: {
              action,
              title: 'Test',
              article_id: 'art-123',
              query: 'test',
            },
          },
        };

        const { container, unmount } = render(<KbArticleNode {...props} />);

        // Each action should render with an icon in the header (h-4 w-4 classes)
        const iconContainer = container.querySelector('.h-4.w-4');
        expect(iconContainer).toBeInTheDocument();

        unmount();
      });
    });
  });
});
