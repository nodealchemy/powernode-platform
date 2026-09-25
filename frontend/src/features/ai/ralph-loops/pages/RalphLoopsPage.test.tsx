import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { RalphLoopsContent } from './RalphLoopsPage';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';

jest.mock('@/shared/services/ai/RalphLoopsApiService', () => ({
  ralphLoopsApi: {
    getLoop: jest.fn(),
  },
}));

jest.mock('../hooks/useRalphLoopExecutionWebSocket', () => ({
  useRalphLoopExecutionWebSocket: () => ({ isConnected: false }),
}));

jest.mock('@/shared/hooks/useNotification', () => ({
  useNotification: () => ({ showNotification: jest.fn() }),
}));

jest.mock('../components/CreateRalphLoopDialog', () => ({
  CreateRalphLoopDialog: () => null,
}));

jest.mock('../components/RalphLoopListPanel', () => ({
  RalphLoopListPanel: ({ onSelectLoop }: { onSelectLoop: (loop: { id: string; name: string }) => void }) => (
    <div data-testid="ralph-loop-list-panel">
      <button data-testid="select-loop-btn" onClick={() => onSelectLoop({ id: 'loop-1', name: 'Test Loop' })}>
        Select Loop
      </button>
    </div>
  ),
}));

jest.mock('../components/RalphLoopDetailPanel', () => ({
  RalphLoopDetailPanel: ({
    loop,
    activeTab,
    onActiveTabChange,
  }: {
    loop: { id: string } | null;
    activeTab: string;
    onActiveTabChange: (tab: string) => void;
  }) =>
    loop ? (
      <div data-testid="ralph-loop-detail-panel">
        <div data-testid="active-tab">{activeTab}</div>
        <button data-testid="switch-to-iterations" onClick={() => onActiveTabChange('iterations')}>
          Iterations
        </button>
      </div>
    ) : (
      <div data-testid="empty-state">Select a loop to view details</div>
    ),
}));

const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <RalphLoopsContent />
      <LocationProbe />
    </MemoryRouter>
  );

describe('RalphLoopsContent path tabs', () => {
  beforeEach(() => {
    (ralphLoopsApi.getLoop as jest.Mock).mockResolvedValue({
      ralph_loop: { id: 'loop-1', name: 'Test Loop', prd_json: { tasks: [] } },
    });
  });

  it('shows the empty state with no loop selected', () => {
    renderAt('/app/ai/execution');
    expect(screen.getByTestId('empty-state')).toBeInTheDocument();
  });

  it('deep-links directly to a loop tab', async () => {
    renderAt('/app/ai/execution/loop/loop-1/iterations');
    await waitFor(() => expect(screen.getByTestId('ralph-loop-detail-panel')).toBeInTheDocument());
    expect(screen.getByTestId('active-tab')).toHaveTextContent('iterations');
  });

  it('updates the URL when a loop is selected', async () => {
    renderAt('/app/ai/execution');
    fireEvent.click(screen.getByTestId('select-loop-btn'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/execution/loop/loop-1/tasks')
    );
    expect(screen.getByTestId('ralph-loop-detail-panel')).toBeInTheDocument();
  });

  it('updates the URL when the detail panel tab changes', async () => {
    renderAt('/app/ai/execution');
    fireEvent.click(screen.getByTestId('select-loop-btn'));
    await waitFor(() => expect(screen.getByTestId('ralph-loop-detail-panel')).toBeInTheDocument());

    fireEvent.click(screen.getByTestId('switch-to-iterations'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/execution/loop/loop-1/iterations')
    );
  });
});
