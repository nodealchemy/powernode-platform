import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { EvaluationContent } from './EvaluationDashboardPage';

jest.mock('../components/EvalResultsViewer', () => ({
  EvalResultsViewer: () => <div data-testid="eval-results-viewer">Evaluation Results</div>,
}));

jest.mock('../components/BenchmarkBuilder', () => ({
  BenchmarkBuilder: () => <div data-testid="benchmark-builder">Benchmarks</div>,
}));

jest.mock('../components/EvalComparison', () => ({
  EvalComparison: () => <div data-testid="eval-comparison">Agent Comparison</div>,
}));

const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <EvaluationContent />
      <LocationProbe />
    </MemoryRouter>
  );

describe('EvaluationContent path tabs', () => {
  it('lands on Evaluation Results by default', () => {
    renderAt('/app/ai/observability/evaluation');
    expect(screen.getByTestId('eval-results-viewer')).toBeInTheDocument();
    expect(screen.queryByTestId('benchmark-builder')).not.toBeInTheDocument();
  });

  it('deep-links directly to the Benchmarks tab', () => {
    renderAt('/app/ai/observability/evaluation/benchmarks');
    expect(screen.getByTestId('benchmark-builder')).toBeInTheDocument();
    expect(screen.queryByTestId('eval-results-viewer')).not.toBeInTheDocument();
  });

  it('deep-links directly to the Agent Comparison tab', () => {
    renderAt('/app/ai/observability/evaluation/comparison');
    expect(screen.getByTestId('eval-comparison')).toBeInTheDocument();
  });

  it('updates the URL when a tab is clicked', async () => {
    renderAt('/app/ai/observability/evaluation');
    fireEvent.click(screen.getByText('Benchmarks'));

    await waitFor(() =>
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/observability/evaluation/benchmarks')
    );
    expect(screen.getByTestId('benchmark-builder')).toBeInTheDocument();
  });
});
