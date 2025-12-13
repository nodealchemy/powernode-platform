import { screen, fireEvent } from '@testing-library/react';
import { PageContainer, PageAction, BreadcrumbItem } from './PageContainer';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';

// Mock SharedBreadcrumbs only - let BreadcrumbContext work naturally
jest.mock('../ui/SharedBreadcrumbs', () => ({
  SharedBreadcrumbs: ({ items }: { items: Array<{ label: string; href?: string }> }) => (
    <nav data-testid="breadcrumbs">
      {items.map((item, idx) => (
        <span key={idx} data-testid={`breadcrumb-${idx}`}>
          {item.href ? <a href={item.href}>{item.label}</a> : item.label}
        </span>
      ))}
    </nav>
  ),
}));

describe('PageContainer', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders title', () => {
      renderWithProviders(
        <PageContainer title="Test Page">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByText('Test Page')).toBeInTheDocument();
      expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Test Page');
    });

    it('renders description when provided', () => {
      renderWithProviders(
        <PageContainer title="Test Page" description="This is a test description">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByText('This is a test description')).toBeInTheDocument();
    });

    it('does not render description when not provided', () => {
      renderWithProviders(
        <PageContainer title="Test Page">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      // Only the title and content should be present
      expect(screen.getByText('Test Page')).toBeInTheDocument();
      expect(screen.queryByText('This is a test description')).not.toBeInTheDocument();
    });

    it('renders children content', () => {
      renderWithProviders(
        <PageContainer title="Test Page">
          <div data-testid="child-content">Child Content Here</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByTestId('child-content')).toBeInTheDocument();
      expect(screen.getByText('Child Content Here')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = renderWithProviders(
        <PageContainer title="Test Page" className="custom-class">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      // The outer div should have the custom class
      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('breadcrumbs', () => {
    it('renders breadcrumbs when provided', () => {
      const breadcrumbs: BreadcrumbItem[] = [
        { label: 'Home', href: '/' },
        { label: 'Users', href: '/users' },
        { label: 'Edit' },
      ];

      renderWithProviders(
        <PageContainer title="Edit User" breadcrumbs={breadcrumbs}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByTestId('breadcrumbs')).toBeInTheDocument();
      expect(screen.getByText('Home')).toBeInTheDocument();
      expect(screen.getByText('Users')).toBeInTheDocument();
      expect(screen.getByText('Edit')).toBeInTheDocument();
    });

    it('does not render breadcrumbs when not provided', () => {
      renderWithProviders(
        <PageContainer title="Test Page">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.queryByTestId('breadcrumbs')).not.toBeInTheDocument();
    });

    it('does not render breadcrumbs when empty array provided', () => {
      renderWithProviders(
        <PageContainer title="Test Page" breadcrumbs={[]}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.queryByTestId('breadcrumbs')).not.toBeInTheDocument();
    });
  });

  describe('actions', () => {
    it('renders action buttons', () => {
      const actions: PageAction[] = [
        { label: 'Save', onClick: jest.fn() },
        { label: 'Cancel', onClick: jest.fn() },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByRole('button', { name: 'Save' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Cancel' })).toBeInTheDocument();
    });

    it('calls onClick when action button clicked', () => {
      const mockOnClick = jest.fn();
      const actions: PageAction[] = [
        { label: 'Save', onClick: mockOnClick },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      fireEvent.click(screen.getByRole('button', { name: 'Save' }));
      expect(mockOnClick).toHaveBeenCalledTimes(1);
    });

    it('renders disabled action button', () => {
      const actions: PageAction[] = [
        { label: 'Submit', onClick: jest.fn(), disabled: true },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      const button = screen.getByRole('button', { name: 'Submit' });
      expect(button).toBeDisabled();
    });

    it('does not render actions when not provided', () => {
      renderWithProviders(
        <PageContainer title="Test Page">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      // No buttons should be present in the action area
      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });

    it('renders action with primary variant', () => {
      const actions: PageAction[] = [
        { label: 'Create', onClick: jest.fn(), variant: 'primary' },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      const button = screen.getByRole('button', { name: 'Create' });
      expect(button).toHaveClass('btn-theme-primary');
    });

    it('renders action with danger variant', () => {
      const actions: PageAction[] = [
        { label: 'Delete', onClick: jest.fn(), variant: 'danger' },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      const button = screen.getByRole('button', { name: 'Delete' });
      expect(button).toHaveClass('btn-theme-danger');
    });

    it('renders action with outline variant', () => {
      const actions: PageAction[] = [
        { label: 'Edit', onClick: jest.fn(), variant: 'outline' },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      const button = screen.getByRole('button', { name: 'Edit' });
      expect(button).toHaveClass('btn-theme-outline');
    });

    it('renders action with custom size', () => {
      const actions: PageAction[] = [
        { label: 'Small', onClick: jest.fn(), size: 'sm' },
        { label: 'Large', onClick: jest.fn(), size: 'lg' },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByRole('button', { name: 'Small' })).toHaveClass('btn-theme-sm');
      expect(screen.getByRole('button', { name: 'Large' })).toHaveClass('btn-theme-lg');
    });

    it('renders multiple actions with different variants', () => {
      const actions: PageAction[] = [
        { id: 'save', label: 'Save', onClick: jest.fn(), variant: 'primary' },
        { id: 'cancel', label: 'Cancel', onClick: jest.fn(), variant: 'secondary' },
        { id: 'delete', label: 'Delete', onClick: jest.fn(), variant: 'danger' },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByRole('button', { name: 'Save' })).toHaveClass('btn-theme-primary');
      expect(screen.getByRole('button', { name: 'Cancel' })).toHaveClass('btn-theme-secondary');
      expect(screen.getByRole('button', { name: 'Delete' })).toHaveClass('btn-theme-danger');
    });
  });

  describe('action with icon', () => {
    it('renders action with string icon', () => {
      const actions: PageAction[] = [
        { label: 'Add', onClick: jest.fn(), icon: '+' },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      const button = screen.getByRole('button', { name: /Add/i });
      expect(button.textContent).toContain('+');
    });

    it('renders action with component icon', () => {
      const MockIcon = () => <svg data-testid="mock-icon" />;
      const actions: PageAction[] = [
        { label: 'Settings', onClick: jest.fn(), icon: MockIcon },
      ];

      renderWithProviders(
        <PageContainer title="Test Page" actions={actions}>
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      expect(screen.getByTestId('mock-icon')).toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('has proper heading styling', () => {
      renderWithProviders(
        <PageContainer title="Test Page">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      const heading = screen.getByRole('heading', { level: 1 });
      expect(heading).toHaveClass('text-2xl', 'font-bold', 'text-theme-primary');
    });

    it('has proper description styling', () => {
      renderWithProviders(
        <PageContainer title="Test Page" description="Test description">
          <div>Content</div>
        </PageContainer>,
        { preloadedState: mockAuthenticatedState }
      );

      const description = screen.getByText('Test description');
      expect(description).toHaveClass('text-theme-secondary');
    });
  });
});
