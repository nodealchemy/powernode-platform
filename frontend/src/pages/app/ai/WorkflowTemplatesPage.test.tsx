import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { WorkflowTemplatesPage } from './WorkflowTemplatesPage';
import { workflowsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';

// Mock dependencies
jest.mock('@/shared/services/ai', () => ({
  workflowsApi: {
    getTemplates: jest.fn(),
    createWorkflow: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useAuth');
jest.mock('@/shared/hooks/useNotifications');

// Mock react-router-dom
const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

// Mock PageContainer
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children, title }: { children: React.ReactNode; title: string }) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      {children}
    </div>
  ),
}));

// Mock Card components
jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className }: { children: React.ReactNode; className?: string }) => (
    <div data-testid="card" className={className}>{children}</div>
  ),
  CardTitle: ({ children }: { children: React.ReactNode }) => (
    <h3 data-testid="card-title">{children}</h3>
  ),
  CardContent: ({ children, className }: { children: React.ReactNode; className?: string }) => (
    <div data-testid="card-content" className={className}>{children}</div>
  ),
}));

// Mock Button
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, size, disabled, className }: any) => (
    <button
      onClick={onClick}
      data-variant={variant}
      data-size={size}
      disabled={disabled}
      className={className}
      data-testid="button"
    >
      {children}
    </button>
  ),
}));

// Mock Badge
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, className }: any) => (
    <span data-testid="badge" data-variant={variant} className={className}>
      {children}
    </span>
  ),
}));

// Mock SearchInput
jest.mock('@/shared/components/ui/SearchInput', () => ({
  SearchInput: ({ value, onChange, placeholder }: any) => (
    <input
      data-testid="search-input"
      type="text"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
    />
  ),
}));

// Mock Select
jest.mock('@/shared/components/ui/Select', () => ({
  Select: ({ value, onChange, options, className }: any) => (
    <select
      data-testid="select"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className={className}
    >
      {options?.map((opt: any) => (
        <option key={opt.value} value={opt.value}>
          {opt.label}
        </option>
      ))}
    </select>
  ),
}));

// Test data
const mockTemplates = [
  {
    id: 'template-1',
    name: 'Content Generation',
    description: 'Generate content automatically using AI',
    category: 'content',
    execution_mode: 'sequential' as const,
    difficulty: 'beginner' as const,
    estimated_duration: '5-10 minutes',
    tags: ['ai', 'content', 'automation'],
  },
  {
    id: 'template-2',
    name: 'Data Analysis',
    description: 'Analyze data and generate insights',
    category: 'analytics',
    execution_mode: 'parallel' as const,
    difficulty: 'intermediate' as const,
    estimated_duration: '10-15 minutes',
    tags: ['data', 'analytics'],
  },
  {
    id: 'template-3',
    name: 'Complex Pipeline',
    description: 'Advanced multi-step workflow',
    category: 'automation',
    execution_mode: 'conditional' as const,
    difficulty: 'advanced' as const,
    estimated_duration: '30+ minutes',
    tags: ['advanced', 'pipeline', 'multi-step', 'complex'],
  },
];

const mockWorkflow = {
  id: 'workflow-123',
  name: 'Content Generation Workflow',
  description: 'Generate content automatically using AI',
};

describe('WorkflowTemplatesPage', () => {
  const mockAddNotification = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();

    (useAuth as jest.Mock).mockReturnValue({
      currentUser: {
        id: 'user-1',
        permissions: ['ai.workflows.create', 'ai.workflows.read'],
      },
    });

    (useNotifications as jest.Mock).mockReturnValue({
      addNotification: mockAddNotification,
    });

    (workflowsApi.getTemplates as jest.Mock).mockResolvedValue(mockTemplates);
    (workflowsApi.createWorkflow as jest.Mock).mockResolvedValue(mockWorkflow);
  });

  const renderPage = () => {
    return render(
      <BrowserRouter>
        <WorkflowTemplatesPage />
      </BrowserRouter>
    );
  };

  describe('Rendering', () => {
    it('renders the page container with title', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Workflow Templates')).toBeInTheDocument();
      });
    });

    it('renders search input', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByTestId('search-input')).toBeInTheDocument();
      });
    });

    it('renders filter dropdowns', async () => {
      renderPage();

      await waitFor(() => {
        const selects = screen.getAllByTestId('select');
        expect(selects.length).toBeGreaterThanOrEqual(2);
      });
    });
  });

  describe('Data Loading', () => {
    it('calls getTemplates on mount', async () => {
      renderPage();

      await waitFor(() => {
        expect(workflowsApi.getTemplates).toHaveBeenCalled();
      });
    });

    it('displays templates after loading', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
        expect(screen.getByText('Data Analysis')).toBeInTheDocument();
        expect(screen.getByText('Complex Pipeline')).toBeInTheDocument();
      });
    });

    it('displays loading skeleton while fetching', () => {
      (workflowsApi.getTemplates as jest.Mock).mockImplementation(
        () => new Promise(() => {}) // Never resolves - stays loading
      );

      renderPage();

      // Check for loading state (cards with animate-pulse class)
      const cards = screen.getAllByTestId('card');
      expect(cards.some(card => card.className.includes('animate-pulse'))).toBe(true);
    });

    it('shows error notification on load failure', async () => {
      (workflowsApi.getTemplates as jest.Mock).mockRejectedValue(new Error('API Error'));

      renderPage();

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith({
          type: 'error',
          title: 'Error',
          message: 'Failed to load workflow templates. Please try again.',
        });
      });
    });
  });

  describe('Template Display', () => {
    it('displays template names', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });
    });

    it('displays template descriptions', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Generate content automatically using AI')).toBeInTheDocument();
      });
    });

    it('displays difficulty badges', async () => {
      renderPage();

      await waitFor(() => {
        const badges = screen.getAllByTestId('badge');
        const difficultyBadges = badges.filter(
          b => b.textContent === 'beginner' ||
               b.textContent === 'intermediate' ||
               b.textContent === 'advanced'
        );
        expect(difficultyBadges.length).toBeGreaterThan(0);
      });
    });

    it('displays category badges', async () => {
      renderPage();

      await waitFor(() => {
        const badges = screen.getAllByTestId('badge');
        const categoryBadges = badges.filter(
          b => b.textContent === 'content' ||
               b.textContent === 'analytics' ||
               b.textContent === 'automation'
        );
        expect(categoryBadges.length).toBeGreaterThan(0);
      });
    });

    it('displays estimated duration', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('5-10 minutes')).toBeInTheDocument();
      });
    });

    it('displays tags', async () => {
      renderPage();

      await waitFor(() => {
        const badges = screen.getAllByTestId('badge');
        // Check that some tags are visible
        expect(badges.some(b => b.textContent === 'ai')).toBe(true);
      });
    });

    it('shows +N more when more than 3 tags', async () => {
      renderPage();

      await waitFor(() => {
        // Complex Pipeline has 4 tags, so should show "+1 more"
        expect(screen.getByText('+1 more')).toBeInTheDocument();
      });
    });
  });

  describe('Search and Filtering', () => {
    it('filters templates by search query', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const searchInput = screen.getByTestId('search-input');
      fireEvent.change(searchInput, { target: { value: 'Data Analysis' } });

      await waitFor(() => {
        expect(screen.getByText('Data Analysis')).toBeInTheDocument();
        expect(screen.queryByText('Content Generation')).not.toBeInTheDocument();
      });
    });

    it('filters by search query in description', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const searchInput = screen.getByTestId('search-input');
      fireEvent.change(searchInput, { target: { value: 'insights' } });

      await waitFor(() => {
        expect(screen.getByText('Data Analysis')).toBeInTheDocument();
        expect(screen.queryByText('Content Generation')).not.toBeInTheDocument();
      });
    });

    it('filters by category', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const selects = screen.getAllByTestId('select');
      const categorySelect = selects[0]; // First select is category

      fireEvent.change(categorySelect, { target: { value: 'analytics' } });

      await waitFor(() => {
        expect(screen.getByText('Data Analysis')).toBeInTheDocument();
        expect(screen.queryByText('Content Generation')).not.toBeInTheDocument();
      });
    });

    it('filters by difficulty', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const selects = screen.getAllByTestId('select');
      const difficultySelect = selects[1]; // Second select is difficulty

      fireEvent.change(difficultySelect, { target: { value: 'advanced' } });

      await waitFor(() => {
        expect(screen.getByText('Complex Pipeline')).toBeInTheDocument();
        expect(screen.queryByText('Content Generation')).not.toBeInTheDocument();
      });
    });
  });

  describe('Empty States', () => {
    it('shows empty state when no templates', async () => {
      (workflowsApi.getTemplates as jest.Mock).mockResolvedValue([]);

      renderPage();

      await waitFor(() => {
        expect(screen.getByText('No templates found')).toBeInTheDocument();
      });
    });

    it('shows filtered empty state message', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const searchInput = screen.getByTestId('search-input');
      fireEvent.change(searchInput, { target: { value: 'nonexistent template xyz' } });

      await waitFor(() => {
        expect(screen.getByText('No templates found')).toBeInTheDocument();
        expect(screen.getByText('Try adjusting your filters to see more templates.')).toBeInTheDocument();
      });
    });

    it('shows Clear Filters button when filters are active', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const searchInput = screen.getByTestId('search-input');
      fireEvent.change(searchInput, { target: { value: 'nonexistent' } });

      await waitFor(() => {
        expect(screen.getByText('Clear Filters')).toBeInTheDocument();
      });
    });

    it('clears filters when Clear Filters button clicked', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const searchInput = screen.getByTestId('search-input');
      fireEvent.change(searchInput, { target: { value: 'nonexistent' } });

      await waitFor(() => {
        expect(screen.getByText('Clear Filters')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Clear Filters'));

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });
    });
  });

  describe('Template Actions', () => {
    it('renders View and Use buttons for each template', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const viewButtons = screen.getAllByText('View');
      const useButtons = screen.getAllByText('Use');

      expect(viewButtons.length).toBe(3);
      expect(useButtons.length).toBe(3);
    });

    it('shows notification when View clicked', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const viewButtons = screen.getAllByText('View');
      fireEvent.click(viewButtons[0]);

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'info',
            title: 'Template Details',
          })
        );
      });
    });

    it('creates workflow and navigates when Use clicked', async () => {
      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const useButtons = screen.getAllByText('Use');
      fireEvent.click(useButtons[0]);

      await waitFor(() => {
        expect(workflowsApi.createWorkflow).toHaveBeenCalledWith({
          name: 'Content Generation Workflow',
          description: 'Generate content automatically using AI',
          status: 'draft',
          execution_mode: 'sequential',
          tags: ['ai', 'content', 'automation'],
        });
      });

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith({
          type: 'success',
          title: 'Workflow Created',
          message: 'Created new workflow from "Content Generation" template.',
        });
      });

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/app/ai/workflows/workflow-123/edit');
      });
    });

    it('shows error notification on workflow creation failure', async () => {
      (workflowsApi.createWorkflow as jest.Mock).mockRejectedValue(new Error('Creation failed'));

      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const useButtons = screen.getAllByText('Use');
      fireEvent.click(useButtons[0]);

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith({
          type: 'error',
          title: 'Creation Failed',
          message: 'Failed to create workflow from template. Please try again.',
        });
      });
    });
  });

  describe('Permissions', () => {
    it('hides Use button when user lacks create permission', async () => {
      (useAuth as jest.Mock).mockReturnValue({
        currentUser: {
          id: 'user-1',
          permissions: ['ai.workflows.read'], // No create permission
        },
      });

      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      const viewButtons = screen.getAllByText('View');
      expect(viewButtons.length).toBe(3);

      // Use buttons should not be present
      expect(screen.queryAllByText('Use').length).toBe(0);
    });

    it('shows permission denied notification when creating without permission', async () => {
      (useAuth as jest.Mock).mockReturnValue({
        currentUser: {
          id: 'user-1',
          permissions: [], // No permissions
        },
      });

      renderPage();

      await waitFor(() => {
        expect(screen.getByText('Content Generation')).toBeInTheDocument();
      });

      // Use buttons should not be rendered due to permission check
      expect(screen.queryAllByText('Use').length).toBe(0);
    });
  });
});
