import { render, screen } from '@testing-library/react';

// fc-44: runner health moved from the deleted CI/CD Overview tab to the
// Runners tab.

const mockGetRunners = jest.fn();
jest.mock('@/features/devops/git/services/git/runnersApi', () => ({
  runnersApi: { getRunners: (...args: unknown[]) => mockGetRunners(...args) },
}));

import { RunnerHealthPanel } from '../RunnerHealthPanel';

describe('RunnerHealthPanel', () => {
  beforeEach(() => mockGetRunners.mockReset());

  it('shows online, busy and offline runner counts', async () => {
    mockGetRunners.mockResolvedValue({ runners: [], stats: { total: 6, online: 3, busy: 2, offline: 1 } });

    render(<RunnerHealthPanel />);

    expect(await screen.findByTestId('runners-online')).toHaveTextContent('3');
    expect(screen.getByTestId('runners-busy')).toHaveTextContent('2');
    expect(screen.getByTestId('runners-offline')).toHaveTextContent('1');
    expect(mockGetRunners).toHaveBeenCalledWith({ per_page: 1 });
  });

  it('flags offline runners', async () => {
    mockGetRunners.mockResolvedValue({ runners: [], stats: { total: 3, online: 1, busy: 0, offline: 2 } });

    render(<RunnerHealthPanel />);

    expect(await screen.findByText('2 runners offline')).toBeInTheDocument();
  });

  it('says so when no runners are configured', async () => {
    mockGetRunners.mockResolvedValue({ runners: [], stats: { total: 0, online: 0, busy: 0, offline: 0 } });

    render(<RunnerHealthPanel />);

    expect(await screen.findByText('No runners configured')).toBeInTheDocument();
  });

  it('shows a loading state until the stats arrive', () => {
    mockGetRunners.mockReturnValue(new Promise(() => {}));

    render(<RunnerHealthPanel />);

    expect(screen.getByText('Loading runner health…')).toBeInTheDocument();
    expect(screen.queryByText('No runners configured')).not.toBeInTheDocument();
  });

  it('shows an error state when the stats fail to load, not "No runners configured"', async () => {
    mockGetRunners.mockRejectedValue(new Error('boom'));

    render(<RunnerHealthPanel />);

    expect(await screen.findByText('Could not load runner health.')).toBeInTheDocument();
    expect(screen.queryByText('No runners configured')).not.toBeInTheDocument();
  });
});
