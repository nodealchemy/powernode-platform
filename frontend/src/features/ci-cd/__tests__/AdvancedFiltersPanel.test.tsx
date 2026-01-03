import { render, screen, fireEvent } from '@testing-library/react';
import { AdvancedFiltersPanel, PipelineFilters } from '../components/AdvancedFiltersPanel';

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  Filter: () => <span data-testid="icon-filter" />,
  ChevronDown: () => <span data-testid="icon-chevron-down" />,
  ChevronUp: () => <span data-testid="icon-chevron-up" />,
  Calendar: () => <span data-testid="icon-calendar" />,
  User: () => <span data-testid="icon-user" />,
  Zap: () => <span data-testid="icon-zap" />,
  Clock: () => <span data-testid="icon-clock" />,
  RotateCcw: () => <span data-testid="icon-rotate" />,
  Check: () => <span data-testid="icon-check" />,
  Search: () => <span data-testid="icon-search" />,
}));

describe('AdvancedFiltersPanel', () => {
  const defaultFilters: PipelineFilters = {};
  const mockOnChange = jest.fn();
  const mockOnClear = jest.fn();
  const mockOnToggle = jest.fn();

  const defaultProps = {
    filters: defaultFilters,
    onChange: mockOnChange,
    onClear: mockOnClear,
    isOpen: true,
    onToggle: mockOnToggle,
    repositories: [
      { id: 'repo-1', name: 'repo-1', full_name: 'owner/repo-1' },
    ],
    branches: ['main', 'develop'],
    actors: ['user1', 'user2'],
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders the filter panel when open', () => {
    render(<AdvancedFiltersPanel {...defaultProps} />);

    expect(screen.getByText('Advanced Filters')).toBeInTheDocument();
  });

  it('shows collapsed state when isOpen is false', () => {
    render(<AdvancedFiltersPanel {...defaultProps} isOpen={false} />);

    expect(screen.getByTestId('icon-filter')).toBeInTheDocument();
  });

  it('calls onToggle when header is clicked', () => {
    render(<AdvancedFiltersPanel {...defaultProps} />);

    const header = screen.getByText('Advanced Filters');
    fireEvent.click(header);

    expect(mockOnToggle).toHaveBeenCalled();
  });

  it('renders status filter options', () => {
    render(<AdvancedFiltersPanel {...defaultProps} />);

    expect(screen.getByText('Pending')).toBeInTheDocument();
    expect(screen.getByText('Running')).toBeInTheDocument();
    expect(screen.getByText('Success')).toBeInTheDocument();
    expect(screen.getByText('Failure')).toBeInTheDocument();
  });

  it('calls onChange when status filter is toggled', () => {
    render(<AdvancedFiltersPanel {...defaultProps} />);

    const successButton = screen.getByText('Success');
    fireEvent.click(successButton);

    expect(mockOnChange).toHaveBeenCalled();
  });

  it('calls onClear when clear button is clicked', () => {
    render(<AdvancedFiltersPanel {...defaultProps} filters={{ status: ['success'] }} />);

    const clearButton = screen.getByText('Clear All');
    fireEvent.click(clearButton);

    expect(mockOnClear).toHaveBeenCalled();
  });

  it('shows active filter count badge when filters are active', () => {
    render(
      <AdvancedFiltersPanel
        {...defaultProps}
        filters={{ status: ['success', 'failure'] }}
      />
    );

    // Should show badge with active filter count (1 filter category)
    expect(screen.getByText('1')).toBeInTheDocument();
  });
});
