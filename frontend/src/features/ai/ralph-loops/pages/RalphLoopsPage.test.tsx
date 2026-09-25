import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation, useNavigate } from 'react-router-dom';
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

const NavigateButton = ({ to }: { to: string }) => {
  const navigate = useNavigate();
  return (
    <button data-testid={`navigate-to:${to}`} onClick={() => navigate(to)}>
      go to {to}
    </button>
  );
};

const renderAt = (path: string, extraPaths: string[] = []) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <RalphLoopsContent />
      <LocationProbe />
      {extraPaths.map((p) => (
        <NavigateButton key={p} to={p} />
      ))}
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

  // fc-46 review, item 6.
  it('loads the selected loop exactly once, not twice (select → navigate → the location effect loading it again)', async () => {
    renderAt('/app/ai/execution');
    fireEvent.click(screen.getByTestId('select-loop-btn'));

    await waitFor(() => expect(screen.getByTestId('ralph-loop-detail-panel')).toBeInTheDocument());
    expect(ralphLoopsApi.getLoop).toHaveBeenCalledTimes(1);
  });

  it('clears the selected loop when the URL moves back to the bare execution path', async () => {
    renderAt('/app/ai/execution/loop/loop-1/tasks', ['/app/ai/execution']);
    await waitFor(() => expect(screen.getByTestId('ralph-loop-detail-panel')).toBeInTheDocument());

    fireEvent.click(screen.getByTestId('navigate-to:/app/ai/execution'));

    await waitFor(() => expect(screen.getByTestId('empty-state')).toBeInTheDocument());
  });

  it('clears the old loop when the URL moves to a different (invalid) loop id', async () => {
    (ralphLoopsApi.getLoop as jest.Mock).mockImplementation((id: string) =>
      id === 'loop-1'
        ? Promise.resolve({ ralph_loop: { id: 'loop-1', name: 'Test Loop', prd_json: { tasks: [] } } })
        : Promise.reject(new Error('not found'))
    );
    renderAt('/app/ai/execution/loop/loop-1/tasks', ['/app/ai/execution/loop/does-not-exist/tasks']);
    await waitFor(() => expect(screen.getByTestId('ralph-loop-detail-panel')).toBeInTheDocument());

    fireEvent.click(screen.getByTestId('navigate-to:/app/ai/execution/loop/does-not-exist/tasks'));

    // loop-1's stale content must not linger under the new (invalid) URL —
    // whether that resolves to the empty state or an error state, it must
    // not still be "ralph-loop-detail-panel" showing loop-1.
    await waitFor(() => expect(screen.queryByTestId('ralph-loop-detail-panel')).not.toBeInTheDocument());
  });
});
