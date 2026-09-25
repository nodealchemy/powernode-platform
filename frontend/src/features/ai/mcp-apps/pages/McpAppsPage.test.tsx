import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { McpAppsPage } from './McpAppsPage';

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: () => true }),
}));

jest.mock('../components/McpAppGallery', () => ({
  McpAppGallery: ({ onSelectApp }: { onSelectApp?: (app: { id: string; name: string }) => void }) => (
    <div data-testid="mcp-app-gallery">
      MCP App Gallery
      <button data-testid="select-app-btn" onClick={() => onSelectApp?.({ id: 'app-1', name: 'Test App' })}>
        Select App
      </button>
    </div>
  ),
}));

jest.mock('../components/McpAppRenderer', () => ({
  McpAppRenderer: () => <div data-testid="mcp-app-renderer">MCP App Renderer</div>,
}));

jest.mock('../components/McpAppConfigurator', () => ({
  McpAppConfigurator: () => <div data-testid="mcp-app-configurator">MCP App Configurator</div>,
}));

const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <McpAppsPage />
      <LocationProbe />
    </MemoryRouter>
  );

describe('McpAppsPage path tabs', () => {
  it('lands on Gallery by default', () => {
    renderAt('/app/ai/infrastructure/mcp-apps');
    expect(screen.getByTestId('mcp-app-gallery')).toBeInTheDocument();
    expect(screen.queryByTestId('mcp-app-renderer')).not.toBeInTheDocument();
  });

  it('deep-links directly to the Preview tab', () => {
    renderAt('/app/ai/infrastructure/mcp-apps/preview');
    expect(screen.queryByTestId('mcp-app-gallery')).not.toBeInTheDocument();
    expect(screen.getByText('Select an app from the gallery to preview.')).toBeInTheDocument();
  });

  it('updates the URL when selecting an app moves to Preview', async () => {
    renderAt('/app/ai/infrastructure/mcp-apps');
    fireEvent.click(screen.getByTestId('select-app-btn'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/infrastructure/mcp-apps/preview')
    );
    expect(screen.getByTestId('mcp-app-renderer')).toBeInTheDocument();
  });

  it('updates the URL when the Gallery tab is clicked from Preview', async () => {
    renderAt('/app/ai/infrastructure/mcp-apps/preview');
    await waitFor(() => expect(screen.getByText('Gallery')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Gallery'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/infrastructure/mcp-apps')
    );
    expect(screen.getByTestId('mcp-app-gallery')).toBeInTheDocument();
  });
});
