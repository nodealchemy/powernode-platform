import { render, screen, fireEvent } from '@testing-library/react';
import { EmptyState } from './EmptyState';
import { Search, FileText } from 'lucide-react';

describe('EmptyState', () => {
  const defaultProps = {
    title: 'No results found',
    description: 'Try adjusting your search or filter criteria',
  };

  describe('rendering', () => {
    it('renders title', () => {
      render(<EmptyState {...defaultProps} />);

      expect(screen.getByText('No results found')).toBeInTheDocument();
    });

    it('renders description', () => {
      render(<EmptyState {...defaultProps} />);

      expect(screen.getByText('Try adjusting your search or filter criteria')).toBeInTheDocument();
    });

    it('renders title as heading', () => {
      render(<EmptyState {...defaultProps} />);

      expect(screen.getByRole('heading', { level: 3 })).toHaveTextContent('No results found');
    });

    it('applies custom className', () => {
      const { container } = render(
        <EmptyState {...defaultProps} className="custom-class" />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('icon rendering', () => {
    it('does not render icon wrapper when no icon provided', () => {
      const { container } = render(<EmptyState {...defaultProps} />);

      const iconWrapper = container.querySelector('.h-16.w-16');
      expect(iconWrapper).not.toBeInTheDocument();
    });

    it('renders icon when provided', () => {
      const { container } = render(
        <EmptyState {...defaultProps} icon={Search} />
      );

      const iconWrapper = container.querySelector('.h-16.w-16');
      expect(iconWrapper).toBeInTheDocument();
    });

    it('renders icon with correct size class', () => {
      const { container } = render(
        <EmptyState {...defaultProps} icon={FileText} />
      );

      const icon = container.querySelector('.h-8.w-8');
      expect(icon).toBeInTheDocument();
    });
  });

  describe('action rendering', () => {
    it('does not render action wrapper when no action provided', () => {
      render(<EmptyState {...defaultProps} />);

      // No button should be present
      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });

    it('renders action button when provided', () => {
      render(
        <EmptyState
          {...defaultProps}
          action={<button>Create New</button>}
        />
      );

      expect(screen.getByRole('button', { name: 'Create New' })).toBeInTheDocument();
    });

    it('renders custom action element', () => {
      render(
        <EmptyState
          {...defaultProps}
          action={<a href="/create">Add Item</a>}
        />
      );

      expect(screen.getByRole('link', { name: 'Add Item' })).toBeInTheDocument();
    });

    it('action is clickable', () => {
      const onClick = jest.fn();
      render(
        <EmptyState
          {...defaultProps}
          action={<button onClick={onClick}>Click me</button>}
        />
      );

      fireEvent.click(screen.getByRole('button'));
      expect(onClick).toHaveBeenCalledTimes(1);
    });
  });

  describe('styling', () => {
    it('centers content', () => {
      const { container } = render(<EmptyState {...defaultProps} />);

      expect(container.firstChild).toHaveClass(
        'flex',
        'flex-col',
        'items-center',
        'justify-center',
        'text-center'
      );
    });

    it('has proper padding', () => {
      const { container } = render(<EmptyState {...defaultProps} />);

      expect(container.firstChild).toHaveClass('py-12', 'px-4');
    });

    it('title has proper styling', () => {
      render(<EmptyState {...defaultProps} />);

      const title = screen.getByRole('heading');
      expect(title).toHaveClass('text-lg', 'font-semibold');
    });

    it('description has max-width', () => {
      render(<EmptyState {...defaultProps} />);

      const description = screen.getByText(defaultProps.description);
      expect(description).toHaveClass('max-w-md');
    });

    it('icon wrapper has proper styling', () => {
      const { container } = render(
        <EmptyState {...defaultProps} icon={Search} />
      );

      const iconWrapper = container.querySelector('.h-16.w-16');
      expect(iconWrapper).toHaveClass('rounded-full', 'mb-4');
    });
  });

  describe('different content combinations', () => {
    it('renders with only required props', () => {
      render(
        <EmptyState
          title="Empty"
          description="Nothing here yet"
        />
      );

      expect(screen.getByText('Empty')).toBeInTheDocument();
      expect(screen.getByText('Nothing here yet')).toBeInTheDocument();
    });

    it('renders with icon and no action', () => {
      render(
        <EmptyState
          title="No data"
          description="Start by creating something"
          icon={FileText}
        />
      );

      expect(screen.getByText('No data')).toBeInTheDocument();
      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });

    it('renders with action and no icon', () => {
      render(
        <EmptyState
          title="Empty list"
          description="Add your first item"
          action={<button>Add Item</button>}
        />
      );

      expect(screen.getByRole('button')).toBeInTheDocument();
    });

    it('renders with all props', () => {
      const { container } = render(
        <EmptyState
          title="No results"
          description="Try a different search"
          icon={Search}
          action={<button>Clear filters</button>}
          className="my-empty-state"
        />
      );

      expect(screen.getByText('No results')).toBeInTheDocument();
      expect(screen.getByText('Try a different search')).toBeInTheDocument();
      expect(container.querySelector('.h-16.w-16')).toBeInTheDocument();
      expect(screen.getByRole('button')).toBeInTheDocument();
      expect(container.firstChild).toHaveClass('my-empty-state');
    });
  });
});
