import { screen } from '@testing-library/react';
import { WelcomePage } from './WelcomePage';
import { renderWithProviders, mockUnauthenticatedState } from '@/shared/utils/test-utils';
import { featureRegistry } from '@/shared/services/featureRegistry';

jest.mock('@/shared/contexts/FooterContext', () => ({
  useFooter: () => ({ footerData: null }),
}));

const withRegistration = {
  ...mockUnauthenticatedState,
  config: { ...mockUnauthenticatedState.config, registrationEnabled: true },
};

// The sign-up CTAs lead to the public route an extension registers for the
// 'pricing' role. With registration on but no such route, they are absent
// rather than dead links.
describe('WelcomePage sign-up CTAs', () => {
  beforeEach(() => featureRegistry.clear());
  afterAll(() => featureRegistry.clear());

  it('shows no sign-up CTA when no extension registers a pricing route', () => {
    renderWithProviders(<WelcomePage />, { preloadedState: withRegistration });

    expect(screen.queryByText('Get Started Free')).not.toBeInTheDocument();
    expect(screen.queryByText('Start Building')).not.toBeInTheDocument();
  });

  it('links the sign-up CTAs to the registered pricing route', () => {
    featureRegistry.registerPublicRoutes('test-ext', [
      { path: '/ext-pricing', component: () => null, role: 'pricing' },
    ]);
    renderWithProviders(<WelcomePage />, { preloadedState: withRegistration });

    expect(screen.getByText('Get Started Free').closest('a')).toHaveAttribute('href', '/ext-pricing');
    expect(screen.getByText('Start Building').closest('a')).toHaveAttribute('href', '/ext-pricing');
  });
});
