import { screen } from '@testing-library/react';
import { PublicPageContainer } from './PublicPageContainer';
import { renderWithProviders, mockUnauthenticatedState } from '@/shared/utils/test-utils';
import { featureRegistry } from '@/shared/services/featureRegistry';

jest.mock('@/shared/contexts/FooterContext', () => ({
  useFooter: () => ({ footerData: null }),
}));

// Core names no pricing route. The header's "Get Started" and the footer's
// Product links follow the public route an extension registers for the
// 'pricing' role, and are absent when none does.
describe('PublicPageContainer pricing links', () => {
  beforeEach(() => featureRegistry.clear());
  afterAll(() => featureRegistry.clear());

  it('renders no pricing links when no extension registers a pricing route', () => {
    renderWithProviders(<PublicPageContainer>content</PublicPageContainer>, {
      preloadedState: mockUnauthenticatedState,
    });

    expect(screen.queryByText('Get Started')).not.toBeInTheDocument();
    expect(screen.queryByText('Pricing')).not.toBeInTheDocument();
    expect(screen.queryByText('Product')).not.toBeInTheDocument();
    expect(screen.getByText('Sign in')).toBeInTheDocument();
  });

  it('links Get Started and the Product links to the registered pricing route', () => {
    featureRegistry.registerPublicRoutes('test-ext', [
      { path: '/ext-pricing', component: () => null, role: 'pricing' },
    ]);
    renderWithProviders(<PublicPageContainer>content</PublicPageContainer>, {
      preloadedState: mockUnauthenticatedState,
    });

    expect(screen.getByText('Get Started').closest('a')).toHaveAttribute('href', '/ext-pricing');
    expect(screen.getByText('Pricing').closest('a')).toHaveAttribute('href', '/ext-pricing');
    expect(screen.getByText('Features').closest('a')).toHaveAttribute('href', '/ext-pricing');
  });
});
