import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SpendDashboard, SpendSummary } from './SpendDashboard';

// Mock the API client used by the component to fetch spend data.
const mockGet = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
  },
}));

// Silence the structured logger in tests.
jest.mock('@/shared/utils/logger', () => ({
  logger: {
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

const buildSummary = (overrides: Partial<SpendSummary> = {}): SpendSummary => ({
  mtd_spend_usd: 120.5,
  plan_cap_usd: 200,
  components: { llm_usd: 80.25, compute_usd: 40.25 },
  top_missions: [
    { id: 'm1', name: 'Mission Alpha', amount_usd: 50 },
    { id: 'm2', name: 'Mission Beta', amount_usd: 30 },
    { id: 'm3', name: 'Mission Gamma', amount_usd: 20 },
    { id: 'm4', name: 'Mission Delta', amount_usd: 15 },
    { id: 'm5', name: 'Mission Epsilon', amount_usd: 5 },
    { id: 'm6', name: 'Mission Zeta', amount_usd: 0.5 },
  ],
  ...overrides,
});

describe('SpendDashboard', () => {
  beforeEach(() => {
    mockGet.mockReset();
  });

  it('renders MTD spend, plan cap, and remaining when given initial summary', () => {
    render(<SpendDashboard initialSummary={buildSummary()} />);

    expect(screen.getByTestId('spend-mtd')).toHaveTextContent('$120.50');
    expect(screen.getByTestId('spend-cap')).toHaveTextContent('$200.00');
    expect(screen.getByTestId('spend-remaining')).toHaveTextContent('$79.50');
    expect(screen.getByTestId('spend-utilization-label')).toHaveTextContent('60.3% used');
  });

  it('renders the top-five mission breakdown (truncating beyond 5)', () => {
    render(<SpendDashboard initialSummary={buildSummary()} />);

    expect(screen.getByTestId('spend-mission-m1')).toBeInTheDocument();
    expect(screen.getByTestId('spend-mission-m5')).toBeInTheDocument();
    // m6 must NOT render — the component caps at 5 entries.
    expect(screen.queryByTestId('spend-mission-m6')).not.toBeInTheDocument();
  });

  it('shows the empty-state message when no missions are reported', () => {
    render(
      <SpendDashboard initialSummary={buildSummary({ top_missions: [] })} />,
    );

    expect(screen.getByTestId('spend-breakdown-empty')).toBeInTheDocument();
  });

  it('shows the "approaching cap" alert chip at >=90% utilization', () => {
    render(
      <SpendDashboard
        initialSummary={buildSummary({ mtd_spend_usd: 185, plan_cap_usd: 200 })}
      />,
    );

    expect(screen.getByTestId('spend-alert-near')).toBeInTheDocument();
    expect(screen.queryByTestId('spend-alert-over')).not.toBeInTheDocument();
  });

  it('shows the "over cap" alert chip when MTD exceeds the plan cap', () => {
    render(
      <SpendDashboard
        initialSummary={buildSummary({ mtd_spend_usd: 250, plan_cap_usd: 200 })}
      />,
    );

    expect(screen.getByTestId('spend-alert-over')).toBeInTheDocument();
    // "Approaching" chip is mutually exclusive with "over" — over wins.
    expect(screen.queryByTestId('spend-alert-near')).not.toBeInTheDocument();
  });

  it('renders LLM/compute component chips when supplied', () => {
    render(<SpendDashboard initialSummary={buildSummary()} />);

    expect(screen.getByTestId('spend-component-llm')).toHaveTextContent('LLM $80.25');
    expect(screen.getByTestId('spend-component-compute')).toHaveTextContent(
      'Compute $40.25',
    );
  });

  it('omits component chips when sub-component figures are absent', () => {
    render(
      <SpendDashboard initialSummary={buildSummary({ components: undefined })} />,
    );

    expect(screen.queryByTestId('spend-component-llm')).not.toBeInTheDocument();
    expect(screen.queryByTestId('spend-component-compute')).not.toBeInTheDocument();
  });

  it('fetches the summary when no initialSummary is provided', async () => {
    mockGet.mockResolvedValueOnce({ data: buildSummary() });

    render(<SpendDashboard />);

    await waitFor(() => expect(screen.queryByTestId('spend-mtd')).toBeInTheDocument());
    expect(mockGet).toHaveBeenCalledWith('/governance/spend');
  });

  it('displays an error state when the fetch fails', async () => {
    mockGet.mockRejectedValueOnce(new Error('boom'));

    render(<SpendDashboard />);

    await waitFor(() =>
      expect(screen.getByTestId('spend-dashboard-error')).toBeInTheDocument(),
    );
  });

  it('refetches when the refresh button is clicked', async () => {
    mockGet
      .mockResolvedValueOnce({ data: buildSummary({ mtd_spend_usd: 50 }) })
      .mockResolvedValueOnce({ data: buildSummary({ mtd_spend_usd: 75 }) });

    render(<SpendDashboard />);

    await waitFor(() =>
      expect(screen.getByTestId('spend-mtd')).toHaveTextContent('$50.00'),
    );

    fireEvent.click(screen.getByTestId('spend-dashboard-refresh'));

    await waitFor(() =>
      expect(screen.getByTestId('spend-mtd')).toHaveTextContent('$75.00'),
    );
    expect(mockGet).toHaveBeenCalledTimes(2);
  });
});
