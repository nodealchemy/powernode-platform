import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { AppCard, AppFeature, AppReview, AppStats } from './AppCard';
import { App, AppStatus } from '../../types';

// Mock useNavigate
const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate
}));

// Mock UI components
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, size, className, disabled }: any) => (
    <button
      onClick={onClick}
      data-variant={variant}
      data-size={size}
      className={className}
      disabled={disabled}
    >
      {children}
    </button>
  )
}));

jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, className }: any) => (
    <span data-testid="badge" data-variant={variant} className={className}>
      {children}
    </span>
  )
}));

jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className, onClick }: any) => (
    <div data-testid="card" className={className} onClick={onClick}>
      {children}
    </div>
  )
}));

describe('AppCard', () => {
  const mockApp: App = {
    id: 'app-1',
    name: 'Test App',
    slug: 'test-app',
    description: 'A test application for testing purposes. This is a longer description.',
    short_description: 'A test app',
    category: 'Productivity',
    icon: '📱',
    status: 'published' as AppStatus,
    version: '1.0.0',
    tags: ['api', 'automation', 'integration', 'analytics'],
    created_at: '2025-01-01T00:00:00Z',
    updated_at: '2025-01-15T10:00:00Z',
    published_at: '2025-01-05T00:00:00Z',
    configuration: {},
    metadata: {}
  };

  const mockFeatures: AppFeature[] = [
    { name: 'API Integration', description: 'Connect with external services', icon: '🔌' },
    { name: 'Real-time Updates', description: 'Live data synchronization', icon: '⚡' },
    { name: 'Custom Webhooks', description: 'Event-driven notifications', icon: '🔔' },
    { name: 'Analytics Dashboard', description: 'Comprehensive reporting', icon: '📊' }
  ];

  const mockReviews: AppReview[] = [
    { id: '1', user: 'John Smith', rating: 5, comment: 'Excellent app! Easy to integrate and very reliable.', date: '2024-01-15' },
    { id: '2', user: 'Sarah Johnson', rating: 4, comment: 'Great functionality, could use better documentation.', date: '2024-01-10' }
  ];

  const mockStats: AppStats = {
    apiEndpointCount: 12,
    webhookCount: 5,
    userCount: '1.2k'
  };

  const defaultProps = {
    app: mockApp,
    features: mockFeatures,
    reviews: mockReviews,
    stats: mockStats
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  const renderWithRouter = (ui: React.ReactElement) => {
    return render(<BrowserRouter>{ui}</BrowserRouter>);
  };

  describe('basic display', () => {
    it('shows app name', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('Test App')).toBeInTheDocument();
    });

    it('shows app icon', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('📱')).toBeInTheDocument();
    });

    it('shows short description', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('A test app')).toBeInTheDocument();
    });

    it('shows version', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('v1.0.0')).toBeInTheDocument();
    });

    it('shows category', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      // Category appears twice - in header and in details
      const categoryElements = screen.getAllByText('Productivity');
      expect(categoryElements.length).toBeGreaterThan(0);
    });

    it('shows updated date', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText(/Updated/)).toBeInTheDocument();
    });
  });

  describe('status badge', () => {
    it('shows published status badge', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('Published')).toBeInTheDocument();
    });

    it('shows draft status badge', () => {
      const draftApp = { ...mockApp, status: 'draft' as AppStatus };
      renderWithRouter(<AppCard app={draftApp} />);

      expect(screen.getByText('Draft')).toBeInTheDocument();
    });

    it('shows under review status badge', () => {
      const reviewApp = { ...mockApp, status: 'under_review' as AppStatus };
      renderWithRouter(<AppCard app={reviewApp} />);

      expect(screen.getByText('Under Review')).toBeInTheDocument();
    });

    it('shows inactive status badge', () => {
      const inactiveApp = { ...mockApp, status: 'inactive' as AppStatus };
      renderWithRouter(<AppCard app={inactiveApp} />);

      expect(screen.getByText('Inactive')).toBeInTheDocument();
    });
  });

  describe('tags', () => {
    it('shows first 3 tags', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('api')).toBeInTheDocument();
      expect(screen.getByText('automation')).toBeInTheDocument();
      expect(screen.getByText('integration')).toBeInTheDocument();
    });

    it('shows +N more when more than 3 tags', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('+1 more')).toBeInTheDocument();
    });

    it('hides +N more when 3 or fewer tags', () => {
      const fewTagsApp = { ...mockApp, tags: ['api', 'test'] };
      renderWithRouter(<AppCard app={fewTagsApp} />);

      expect(screen.queryByText(/\+\d+ more/)).not.toBeInTheDocument();
    });
  });

  describe('owner mode', () => {
    it('shows Manage button when isOwner is true', () => {
      renderWithRouter(<AppCard {...defaultProps} isOwner={true} />);

      expect(screen.getByText('Manage')).toBeInTheDocument();
    });

    it('hides Manage button when isOwner is false', () => {
      renderWithRouter(<AppCard {...defaultProps} isOwner={false} />);

      expect(screen.queryByText('Manage')).not.toBeInTheDocument();
    });

    it('calls onManage when Manage clicked', () => {
      const onManage = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} isOwner={true} onManage={onManage} />);

      fireEvent.click(screen.getByText('Manage'));

      expect(onManage).toHaveBeenCalledWith(mockApp);
    });

    it('shows app name as link when isOwner', () => {
      renderWithRouter(<AppCard {...defaultProps} isOwner={true} />);

      const link = screen.getByRole('link', { name: 'Test App' });
      expect(link).toHaveAttribute('href', '/app/marketplace/apps/app-1');
    });
  });

  describe('subscription mode', () => {
    it('shows Subscribe button when showSubscription is true', () => {
      renderWithRouter(<AppCard {...defaultProps} showSubscription={true} />);

      expect(screen.getByText('Subscribe')).toBeInTheDocument();
    });

    it('hides Subscribe button when showSubscription is false', () => {
      renderWithRouter(<AppCard {...defaultProps} showSubscription={false} />);

      expect(screen.queryByText('Subscribe')).not.toBeInTheDocument();
    });

    it('hides Subscribe button when isOwner is true', () => {
      renderWithRouter(<AppCard {...defaultProps} showSubscription={true} isOwner={true} />);

      expect(screen.queryByText('Subscribe')).not.toBeInTheDocument();
    });

    it('calls onSubscribe when Subscribe clicked', () => {
      const onSubscribe = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} showSubscription={true} onSubscribe={onSubscribe} />);

      fireEvent.click(screen.getByText('Subscribe'));

      expect(onSubscribe).toHaveBeenCalledWith(mockApp);
    });
  });

  describe('card click behavior', () => {
    it('calls onCardClick when card is clicked', () => {
      const onCardClick = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} onCardClick={onCardClick} />);

      const card = screen.getByTestId('card');
      fireEvent.click(card);

      expect(onCardClick).toHaveBeenCalledWith(mockApp);
    });

    it('navigates to app detail page by default', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      const card = screen.getByTestId('card');
      fireEvent.click(card);

      expect(mockNavigate).toHaveBeenCalledWith('/app/marketplace/apps/app-1');
    });

    it('does not navigate when onCardClick is provided', () => {
      const onCardClick = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} onCardClick={onCardClick} />);

      const card = screen.getByTestId('card');
      fireEvent.click(card);

      expect(mockNavigate).not.toHaveBeenCalled();
    });
  });

  describe('expansion mode', () => {
    it('shows expand button when onToggleExpansion is provided', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} onToggleExpansion={onToggleExpansion} />);

      // Should find ChevronDown icon button
      const buttons = screen.getAllByRole('button');
      const expandButton = buttons.find(btn => btn.querySelector('.lucide-chevron-down'));
      expect(expandButton).toBeInTheDocument();
    });

    it('calls onToggleExpansion when expand button clicked', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} onToggleExpansion={onToggleExpansion} />);

      const buttons = screen.getAllByRole('button');
      const expandButton = buttons.find(btn => btn.querySelector('.lucide-chevron-down'));

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(onToggleExpansion).toHaveBeenCalledWith(mockApp);
    });

    it('shows expanded content when expanded is true', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={true} onToggleExpansion={onToggleExpansion} />);

      expect(screen.getByText('Overview')).toBeInTheDocument();
      expect(screen.getByText('Features')).toBeInTheDocument();
      expect(screen.getByText('Reviews')).toBeInTheDocument();
    });

    it('hides expanded content when expanded is false', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={false} onToggleExpansion={onToggleExpansion} />);

      expect(screen.queryByText('Overview')).not.toBeInTheDocument();
      expect(screen.queryByText('Features')).not.toBeInTheDocument();
      expect(screen.queryByText('Reviews')).not.toBeInTheDocument();
    });

    it('shows ChevronUp when expanded', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={true} onToggleExpansion={onToggleExpansion} />);

      const buttons = screen.getAllByRole('button');
      const collapseButton = buttons.find(btn => btn.querySelector('.lucide-chevron-up'));
      expect(collapseButton).toBeInTheDocument();
    });
  });

  describe('expanded tabs', () => {
    it('shows App Information in overview tab', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={true} onToggleExpansion={onToggleExpansion} />);

      expect(screen.getByText('App Information')).toBeInTheDocument();
    });

    it('shows Technical Details in overview tab', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={true} onToggleExpansion={onToggleExpansion} />);

      expect(screen.getByText('Technical Details')).toBeInTheDocument();
    });

    it('switches to features tab when clicked', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={true} onToggleExpansion={onToggleExpansion} />);

      const featuresTab = screen.getByText('Features');
      fireEvent.click(featuresTab);

      // Features content should appear
      expect(screen.getByText('API Integration')).toBeInTheDocument();
      expect(screen.getByText('Real-time Updates')).toBeInTheDocument();
    });

    it('switches to reviews tab when clicked', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={true} onToggleExpansion={onToggleExpansion} />);

      const reviewsTab = screen.getByText('Reviews');
      fireEvent.click(reviewsTab);

      // Reviews content should appear
      expect(screen.getByText('John Smith')).toBeInTheDocument();
      expect(screen.getByText('Sarah Johnson')).toBeInTheDocument();
    });

    it('shows review comments', () => {
      const onToggleExpansion = jest.fn();
      renderWithRouter(<AppCard {...defaultProps} expanded={true} onToggleExpansion={onToggleExpansion} />);

      const reviewsTab = screen.getByText('Reviews');
      fireEvent.click(reviewsTab);

      expect(screen.getByText('Excellent app! Easy to integrate and very reliable.')).toBeInTheDocument();
    });
  });

  describe('API and webhook info', () => {
    it('shows API endpoints count', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('📡 12 API endpoints')).toBeInTheDocument();
    });

    it('shows webhooks count', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('🔗 5 webhooks')).toBeInTheDocument();
    });
  });

  describe('rating display', () => {
    it('shows average rating', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      // Average rating of mock reviews (5 + 4) / 2 = 4.5
      expect(screen.getByText('4.5')).toBeInTheDocument();
    });
  });

  describe('user count display', () => {
    it('shows user count', () => {
      renderWithRouter(<AppCard {...defaultProps} />);

      expect(screen.getByText('1.2k')).toBeInTheDocument();
    });
  });

  describe('app without optional fields', () => {
    it('handles missing icon', () => {
      const appWithoutIcon = { ...mockApp, icon: undefined };
      renderWithRouter(<AppCard app={appWithoutIcon} />);

      // Should show default icon
      expect(screen.getByText('📱')).toBeInTheDocument();
    });

    it('handles empty tags', () => {
      const appWithoutTags = { ...mockApp, tags: [] };
      renderWithRouter(<AppCard app={appWithoutTags} />);

      // Should not crash, tags section should be hidden
      expect(screen.queryByText('+0 more')).not.toBeInTheDocument();
    });

    it('handles missing short_description by using description', () => {
      const appWithoutShortDesc = { ...mockApp, short_description: '' };
      renderWithRouter(<AppCard app={appWithoutShortDesc} />);

      expect(screen.getByText(/A test application for testing purposes/)).toBeInTheDocument();
    });
  });

  describe('click event propagation', () => {
    it('does not call onCardClick when Subscribe button clicked', () => {
      const onCardClick = jest.fn();
      const onSubscribe = jest.fn();
      renderWithRouter(
        <AppCard
          {...defaultProps}
          showSubscription={true}
          onCardClick={onCardClick}
          onSubscribe={onSubscribe}
        />
      );

      fireEvent.click(screen.getByText('Subscribe'));

      expect(onSubscribe).toHaveBeenCalled();
      expect(onCardClick).not.toHaveBeenCalled();
    });

    it('does not call onCardClick when Manage button clicked', () => {
      const onCardClick = jest.fn();
      const onManage = jest.fn();
      renderWithRouter(
        <AppCard
          {...defaultProps}
          isOwner={true}
          onCardClick={onCardClick}
          onManage={onManage}
        />
      );

      fireEvent.click(screen.getByText('Manage'));

      expect(onManage).toHaveBeenCalled();
      expect(onCardClick).not.toHaveBeenCalled();
    });
  });
});
