import { render, screen } from '@testing-library/react';
import { ChartFrame, MeterBar, Sparkline, StatTile } from '@/shared/components/charts';

describe('Sparkline', () => {
  it('renders one point per datum, mapping the largest value to the top', () => {
    render(<Sparkline data={[1, 2, 3]} width={160} height={34} />);

    // padding 4 → x spans 4..156; y is inverted (3 is the max, so it sits at the top)
    expect(screen.getByTestId('sparkline-line')).toHaveAttribute('points', '4,30 80,17 156,4');
  });

  it('flattens a constant series to the vertical midline instead of dividing by zero', () => {
    render(<Sparkline data={[5, 5, 5]} width={160} height={34} />);

    expect(screen.getByTestId('sparkline-line')).toHaveAttribute('points', '4,17 80,17 156,17');
  });

  it('emphasises the final point with a ringed endpoint dot', () => {
    render(<Sparkline data={[1, 2, 3]} width={160} height={34} />);

    const endpoint = screen.getByTestId('sparkline-endpoint');
    expect(endpoint).toHaveAttribute('cx', '156');
    expect(endpoint).toHaveAttribute('cy', '4');
  });

  it('drops non-finite entries', () => {
    render(<Sparkline data={[1, NaN, 3]} width={160} height={34} />);

    expect(screen.getByTestId('sparkline-line')).toHaveAttribute('points', '4,30 156,4');
  });

  it('renders nothing when there is no data', () => {
    render(<Sparkline data={[]} />);

    expect(screen.queryByTestId('sparkline')).not.toBeInTheDocument();
  });

  it('draws the optional endpoint label', () => {
    render(<Sparkline data={[1, 2]} endLabel="42/s" />);

    expect(screen.getByTestId('sparkline-end-label')).toHaveTextContent('42/s');
  });

  it('takes its colour from the theme token for the requested tone', () => {
    render(<Sparkline data={[1, 2]} tone="success" />);

    // jsdom resolves no custom properties, so the kit falls back to the CSS
    // variable itself — still theme-aware, never a hardcoded hue.
    expect(screen.getByTestId('sparkline-line')).toHaveAttribute('stroke', 'var(--color-success)');
  });
});

describe('StatTile', () => {
  it('renders a locale-formatted value with its unit and sub line', () => {
    render(<StatTile label="Active nodes" value={1284} unit="nodes" sub="vs 1,190 last week" />);

    expect(screen.getByText('Active nodes')).toBeInTheDocument();
    expect(screen.getByTestId('stat-tile-value')).toHaveTextContent('1,284');
    expect(screen.getByTestId('stat-tile-unit')).toHaveTextContent('nodes');
    expect(screen.getByTestId('stat-tile-sub')).toHaveTextContent('vs 1,190 last week');
  });

  it('renders a string value verbatim', () => {
    render(<StatTile label="Uptime" value="99.98%" />);

    expect(screen.getByTestId('stat-tile-value')).toHaveTextContent('99.98%');
    expect(screen.queryByTestId('stat-tile-unit')).not.toBeInTheDocument();
  });

  it('hosts a chart in its children slot', () => {
    render(
      <StatTile label="Throughput" value={42}>
        <Sparkline data={[1, 2, 3]} />
      </StatTile>
    );

    expect(screen.getByTestId('stat-tile-chart')).toContainElement(screen.getByTestId('sparkline'));
  });
});

describe('MeterBar', () => {
  it('fills proportionally and exposes the progress to assistive tech', () => {
    render(<MeterBar value={25} max={100} ariaLabel="Disk used" />);

    const meter = screen.getByRole('progressbar', { name: 'Disk used' });
    expect(meter).toHaveAttribute('aria-valuenow', '25');
    expect(meter).toHaveAttribute('aria-valuemax', '100');
    expect(screen.getByTestId('meter-bar-fill')).toHaveStyle({ width: '25%' });
  });

  it('clamps an over-max value to a full bar', () => {
    render(<MeterBar value={180} max={100} />);

    expect(screen.getByTestId('meter-bar-fill')).toHaveStyle({ width: '100%' });
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '100');
  });

  it('renders an empty meter rather than NaN when max is zero', () => {
    render(<MeterBar value={5} max={0} />);

    expect(screen.getByTestId('meter-bar-fill')).toHaveStyle({ width: '0%' });
  });

  it('places the cap marker at the requested fraction only when one is given', () => {
    const { rerender } = render(<MeterBar value={10} max={100} />);
    expect(screen.queryByTestId('meter-bar-cap')).not.toBeInTheDocument();

    rerender(<MeterBar value={10} max={100} capMarker={0.8} />);
    expect(screen.getByTestId('meter-bar-cap')).toHaveStyle({ left: 'calc(80% - 1px)' });
  });
});

describe('ChartFrame', () => {
  it('titles the plot and gives it a fixed height', () => {
    render(
      <ChartFrame title="Fleet load" subtitle="Last 24h" height={200}>
        <div data-testid="plot" />
      </ChartFrame>
    );

    expect(screen.getByRole('heading', { name: 'Fleet load' })).toBeInTheDocument();
    expect(screen.getByText('Last 24h')).toBeInTheDocument();
    expect(screen.getByTestId('chart-frame-body')).toHaveStyle({ height: '200px' });
    expect(screen.getByTestId('plot')).toBeInTheDocument();
  });
});
