import { render, screen } from '@testing-library/react';

// fc-44: the deleted CI/CD Overview tab's Recent Runs and success-rate
// breakdown now live on the Pipelines tab.

const mockGetAll = jest.fn();
// `@/services/*` has no jest moduleNameMapper entry, so the mock is virtual.
jest.mock(
  '@/services/devopsPipelinesApi',
  () => ({ devopsPipelineRunsApi: { getAll: (...args: unknown[]) => mockGetAll(...args) } }),
  { virtual: true },
);

import { PipelineRunsSummary } from '../PipelineRunsSummary';

const run = (id: string, status: string, pipeline_name?: string) => ({
  id,
  run_number: Number(id),
  status,
  pipeline_name,
});

describe('PipelineRunsSummary', () => {
  beforeEach(() => mockGetAll.mockReset());

  it('lists the five most recent runs', async () => {
    mockGetAll.mockResolvedValue({
      pipeline_runs: [run('1', 'completed', 'build'), run('2', 'failed')],
      meta: { status_counts: {} },
    });

    render(<PipelineRunsSummary />);

    expect(await screen.findByText('build')).toBeInTheDocument();
    expect(screen.getByText('Run #2')).toBeInTheDocument();
    expect(mockGetAll).toHaveBeenCalledWith({ per_page: 5 });
  });

  it('breaks run outcomes down into successful, failed and cancelled, with a success rate', async () => {
    mockGetAll.mockResolvedValue({
      pipeline_runs: [],
      meta: { status_counts: { completed: 5, success: 1, failed: 3, cancelled: 1 } },
    });

    render(<PipelineRunsSummary />);

    expect(await screen.findByText('60% success rate')).toBeInTheDocument();
    expect(screen.getByTestId('runs-successful')).toHaveTextContent('6');
    expect(screen.getByTestId('runs-failed')).toHaveTextContent('3');
    expect(screen.getByTestId('runs-cancelled')).toHaveTextContent('1');
  });

  it('says so when there are no runs yet', async () => {
    mockGetAll.mockResolvedValue({ pipeline_runs: [], meta: { status_counts: {} } });

    render(<PipelineRunsSummary />);

    expect(await screen.findByText('No pipeline runs yet')).toBeInTheDocument();
    expect(screen.getByText('No run data available')).toBeInTheDocument();
  });

  it('shows a loading state until the runs arrive, not "No pipeline runs yet"', () => {
    mockGetAll.mockReturnValue(new Promise(() => {}));

    render(<PipelineRunsSummary />);

    expect(screen.getByText('Loading pipeline runs…')).toBeInTheDocument();
    expect(screen.queryByText('No pipeline runs yet')).not.toBeInTheDocument();
    expect(screen.queryByText('No run data available')).not.toBeInTheDocument();
  });

  it('shows an error state when the runs fail to load, not "No pipeline runs yet"', async () => {
    mockGetAll.mockRejectedValue(new Error('boom'));

    render(<PipelineRunsSummary />);

    expect(await screen.findByText('Could not load pipeline runs.')).toBeInTheDocument();
    expect(screen.queryByText('No pipeline runs yet')).not.toBeInTheDocument();
    expect(screen.queryByText('No run data available')).not.toBeInTheDocument();
  });
});
