import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { RagContent } from './RagPage';

jest.mock('@/shared/services/ai/RagApiService', () => ({
  ragApi: {
    listKnowledgeBases: jest.fn().mockResolvedValue({ knowledge_bases: [] }),
    listDocuments: jest.fn().mockResolvedValue({ documents: [] }),
    getQueryHistory: jest.fn().mockResolvedValue({ queries: [] }),
    listConnectors: jest.fn().mockResolvedValue({ connectors: [] }),
    getAnalytics: jest.fn().mockResolvedValue(null),
  },
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({
  usePageWebSocket: () => undefined,
}));

jest.mock('react-redux', () => ({
  ...jest.requireActual('react-redux'),
  useDispatch: () => jest.fn(),
}));

// Surfaces the current URL so a click-driven navigation can be asserted on.
const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <RagContent />
      <LocationProbe />
    </MemoryRouter>
  );

describe('RagContent path tabs', () => {
  it('lands on Knowledge Bases by default', async () => {
    renderAt('/app/ai/knowledge/rag');
    await waitFor(() => expect(screen.getByText('Knowledge Bases')).toBeInTheDocument());

    expect(screen.getByText('No knowledge bases')).toBeInTheDocument();
  });

  it('deep-links directly to the Query tab', async () => {
    renderAt('/app/ai/knowledge/rag/query');
    await waitFor(() => expect(screen.getByText('Select a knowledge base to query')).toBeInTheDocument());
  });

  it('deep-links directly to the Connectors tab', async () => {
    renderAt('/app/ai/knowledge/rag/connectors');
    await waitFor(() => expect(screen.getByText('Select a knowledge base to view connectors')).toBeInTheDocument());
  });

  it('deep-links directly to the Analytics tab', async () => {
    renderAt('/app/ai/knowledge/rag/analytics');
    await waitFor(() => expect(screen.getByText('Select a knowledge base to view analytics')).toBeInTheDocument());
  });

  it('updates the URL when a tab is clicked', async () => {
    renderAt('/app/ai/knowledge/rag');
    await waitFor(() => expect(screen.getByText('Knowledge Bases')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Query'));

    await waitFor(() => expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/knowledge/rag/query'));
    expect(screen.getByText('Select a knowledge base to query')).toBeInTheDocument();
  });
});
