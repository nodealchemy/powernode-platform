import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { KnowledgeGraphContent } from './KnowledgeGraphPage';

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: () => true }),
}));

jest.mock('../components/KnowledgeGraphVisualization', () => ({
  KnowledgeGraphVisualization: () => <div data-testid="graph-explorer-panel">Graph Explorer</div>,
}));

jest.mock('../components/HybridSearchResults', () => ({
  HybridSearchResults: () => <div data-testid="hybrid-search-panel">Hybrid Search</div>,
}));

const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <KnowledgeGraphContent />
      <LocationProbe />
    </MemoryRouter>
  );

describe('KnowledgeGraphContent path tabs', () => {
  it('lands on Graph Explorer by default', async () => {
    renderAt('/app/ai/knowledge/graph');
    await waitFor(() => expect(screen.getByTestId('graph-explorer-panel')).toBeInTheDocument());
    expect(screen.queryByTestId('hybrid-search-panel')).not.toBeInTheDocument();
  });

  it('deep-links directly to Hybrid Search', async () => {
    renderAt('/app/ai/knowledge/graph/hybrid-search');
    await waitFor(() => expect(screen.getByTestId('hybrid-search-panel')).toBeInTheDocument());
    expect(screen.queryByTestId('graph-explorer-panel')).not.toBeInTheDocument();
  });

  it('updates the URL when a tab is clicked', async () => {
    renderAt('/app/ai/knowledge/graph');
    await waitFor(() => expect(screen.getByText('Hybrid Search')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Hybrid Search'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/knowledge/graph/hybrid-search')
    );
    expect(screen.getByTestId('hybrid-search-panel')).toBeInTheDocument();
  });
});
