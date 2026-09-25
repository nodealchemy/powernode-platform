import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { DeveloperPortal } from './DeveloperPortal';

// =============================================================================
// Mocks
//
// DeveloperPortal composes ApiDocs and CodeSamples for its other tabs; both
// are unrelated to the docs-only Keys tab this test covers, so they're
// stubbed to keep the test focused and avoid pulling in their own fetches.
// =============================================================================

jest.mock('./ApiDocs', () => ({
  ApiDocs: () => <div data-testid="api-docs">API Docs</div>,
}));

jest.mock('../components/CodeSamples', () => ({
  CodeSamples: () => <div data-testid="code-samples">Code Samples</div>,
}));

// =============================================================================
// Helper
// =============================================================================

function renderPortal() {
  return render(
    <MemoryRouter>
      <BreadcrumbProvider>
        <DeveloperPortal />
      </BreadcrumbProvider>
    </MemoryRouter>,
  );
}

// =============================================================================
// Tests
// =============================================================================

describe('DeveloperPortal', () => {
  // fc-35 review fix (Must fix #1): the Keys tab was made docs-only
  // (ApiKeyManager deleted; pages/app/devops/ApiKeysPage.tsx is the one
  // canonical surface for creating/regenerating/revoking keys) but had no
  // test. This covers both that the tab renders docs content instead of a
  // key-management UI, and that it points at the right canonical surface.
  describe('API Keys tab', () => {
    function openKeysTab() {
      fireEvent.click(screen.getByRole('tab', { name: 'API Keys' }));
    }

    it('renders docs-only content, not a key-management UI', () => {
      renderPortal();

      openKeysTab();

      expect(
        screen.getByText(/Authenticating with an API Key/i),
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Create, regenerate and revoke API keys from DevOps → API Keys/i),
      ).toBeInTheDocument();
      // No key-management affordances (create/regenerate/revoke buttons,
      // a key list) — ApiKeyManager was deleted precisely so this tab
      // couldn't duplicate that surface.
      expect(screen.queryByRole('button', { name: /create.*key/i })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /revoke/i })).not.toBeInTheDocument();
    });

    it('links to the canonical API Keys surface at /app/devops/api-keys', () => {
      renderPortal();

      openKeysTab();

      const link = screen.getByRole('link', { name: /manage api keys/i });
      expect(link).toHaveAttribute('href', '/app/devops/api-keys');
    });

    it('does not render the other tabs’ content while Keys is active', () => {
      renderPortal();

      openKeysTab();

      expect(screen.queryByTestId('api-docs')).not.toBeInTheDocument();
      expect(screen.queryByTestId('code-samples')).not.toBeInTheDocument();
    });
  });
});
