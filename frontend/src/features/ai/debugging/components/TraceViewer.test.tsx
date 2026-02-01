import { render, screen, fireEvent } from '@testing-library/react';
import { TraceViewer } from './TraceViewer';

// Mock trace data
const mockTrace = {
  trace_id: 'trace_123',
  name: 'Test Agent Execution',
  type: 'agent',
  status: 'completed' as const,
  started_at: '2026-01-30T10:00:00Z',
  completed_at: '2026-01-30T10:00:05Z',
  duration_ms: 5000,
  metadata: {},
  error: null,
  spans: [
    {
      id: '1',
      span_id: 'span_root',
      name: 'Test Agent Execution',
      type: 'root',
      parent_span_id: null,
      status: 'completed' as const,
      started_at: '2026-01-30T10:00:00Z',
      completed_at: '2026-01-30T10:00:05Z',
      duration_ms: 5000,
      input: null,
      output: { result: 'success' },
      error: null,
      tokens: { prompt: 100, completion: 50, total: 150 },
      cost: 0.015,
      events: [],
      metadata: {},
      depth: 0,
    },
    {
      id: '2',
      span_id: 'span_llm',
      name: 'LLM Call: openai/gpt-4',
      type: 'llm_call',
      parent_span_id: 'span_root',
      status: 'completed' as const,
      started_at: '2026-01-30T10:00:01Z',
      completed_at: '2026-01-30T10:00:03Z',
      duration_ms: 2000,
      input: { messages: [{ role: 'user', content: 'Hello' }] },
      output: { content: 'Hi there!' },
      error: null,
      tokens: { prompt: 100, completion: 50, total: 150 },
      cost: 0.015,
      events: [],
      metadata: { provider: 'openai', model: 'gpt-4' },
      depth: 1,
    },
    {
      id: '3',
      span_id: 'span_tool',
      name: 'Tool: calculator',
      type: 'tool_execution',
      parent_span_id: 'span_root',
      status: 'completed' as const,
      started_at: '2026-01-30T10:00:03Z',
      completed_at: '2026-01-30T10:00:04Z',
      duration_ms: 1000,
      input: { expression: '2+2' },
      output: { result: 4 },
      error: null,
      tokens: { prompt: 0, completion: 0, total: 0 },
      cost: 0,
      events: [],
      metadata: { tool_name: 'calculator' },
      depth: 1,
    },
  ],
  summary: {
    total_spans: 3,
    llm_calls: 1,
    tool_executions: 1,
    total_tokens: 150,
    total_cost: 0.015,
    failed_spans: 0,
  },
};

describe('TraceViewer', () => {
  it('renders trace header with name and status', () => {
    render(<TraceViewer trace={mockTrace} />);

    // There may be multiple elements with the trace name (header and span tree)
    expect(screen.getAllByText('Test Agent Execution').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('completed')).toBeInTheDocument();
    expect(screen.getByText('agent')).toBeInTheDocument();
  });

  it('displays summary metrics', () => {
    render(<TraceViewer trace={mockTrace} />);

    // Check metrics are present - use getAllByText since values may appear multiple times
    expect(screen.getAllByText('5.00s').length).toBeGreaterThanOrEqual(1); // Duration
    expect(screen.getAllByText('3').length).toBeGreaterThanOrEqual(1); // Span count
    expect(screen.getAllByText('1').length).toBeGreaterThanOrEqual(1); // LLM calls
    expect(screen.getAllByText('150').length).toBeGreaterThanOrEqual(1); // Total tokens
  });

  it('renders all spans in tree view', () => {
    render(<TraceViewer trace={mockTrace} />);

    expect(screen.getByText('LLM Call: openai/gpt-4')).toBeInTheDocument();
    expect(screen.getByText('Tool: calculator')).toBeInTheDocument();
  });

  it('expands root span by default', () => {
    render(<TraceViewer trace={mockTrace} />);

    // Child spans should be visible since root is expanded
    expect(screen.getByText('LLM Call: openai/gpt-4')).toBeInTheDocument();
  });

  it('selects span when clicked', () => {
    render(<TraceViewer trace={mockTrace} />);

    const llmSpanRow = screen.getByText('LLM Call: openai/gpt-4').closest('div[class*="flex items-center"]');
    fireEvent.click(llmSpanRow!);

    // Span details should show the selected span name
    expect(screen.getAllByText('LLM Call: openai/gpt-4').length).toBeGreaterThanOrEqual(2);
  });

  it('shows span details when selected', () => {
    render(<TraceViewer trace={mockTrace} />);

    // Click on LLM span
    const llmSpanRow = screen.getByText('LLM Call: openai/gpt-4').closest('div[class*="flex items-center"]');
    fireEvent.click(llmSpanRow!);

    // Should show metrics - use getAllByText since there may be multiple elements
    expect(screen.getAllByText(/2\.00s|2s/).length).toBeGreaterThanOrEqual(1); // Duration
    expect(screen.getAllByText('150').length).toBeGreaterThanOrEqual(1); // Tokens
    expect(screen.getAllByText(/\$0\.015/).length).toBeGreaterThanOrEqual(1); // Cost
  });

  it('switches between tree and timeline views', () => {
    render(<TraceViewer trace={mockTrace} />);

    // Should start in tree view
    expect(screen.getByRole('button', { name: /Tree View/i })).toBeInTheDocument();

    // Switch to timeline
    fireEvent.click(screen.getByRole('button', { name: /Timeline/i }));

    // Timeline view should be active (component still renders spans)
    expect(screen.getByText('LLM Call: openai/gpt-4')).toBeInTheDocument();
  });

  it('displays span input/output in details', () => {
    render(<TraceViewer trace={mockTrace} />);

    // Click on tool span
    const toolSpanRow = screen.getByText('Tool: calculator').closest('div[class*="flex items-center"]');
    fireEvent.click(toolSpanRow!);

    // Should show input and output sections
    expect(screen.getByText('Input')).toBeInTheDocument();
    expect(screen.getByText('Output')).toBeInTheDocument();
  });

  it('shows "Select a span" message when no span selected', () => {
    render(<TraceViewer trace={mockTrace} />);

    expect(screen.getByText('Select a span to view details')).toBeInTheDocument();
  });

  describe('with failed spans', () => {
    const traceWithError = {
      ...mockTrace,
      status: 'failed' as const,
      spans: [
        ...mockTrace.spans.slice(0, 2),
        {
          ...mockTrace.spans[2],
          status: 'failed' as const,
          error: 'Division by zero',
        },
      ],
      summary: {
        ...mockTrace.summary,
        failed_spans: 1,
      },
    };

    it('displays error in span details', () => {
      render(<TraceViewer trace={traceWithError} />);

      // Click on failed span
      const toolSpanRow = screen.getByText('Tool: calculator').closest('div[class*="flex items-center"]');
      fireEvent.click(toolSpanRow!);

      expect(screen.getByText('Error')).toBeInTheDocument();
      expect(screen.getByText('Division by zero')).toBeInTheDocument();
    });

    it('shows error indicator on failed span row', () => {
      render(<TraceViewer trace={traceWithError} />);

      // Failed span should have danger/red styling indicator
      const failedRow = screen.getByText('Tool: calculator').closest('div[class*="flex items-center"]');
      expect(failedRow?.querySelector('.text-theme-danger')).toBeInTheDocument();
    });
  });

  describe('with events', () => {
    const traceWithEvents = {
      ...mockTrace,
      spans: [
        {
          ...mockTrace.spans[0],
          events: [
            { name: 'checkpoint_reached', data: { step: 1 }, timestamp: '2026-01-30T10:00:02Z' },
            { name: 'retry_attempt', data: { attempt: 1 }, timestamp: '2026-01-30T10:00:03Z' },
          ],
        },
        ...mockTrace.spans.slice(1),
      ],
    };

    it('displays events in span details', () => {
      render(<TraceViewer trace={traceWithEvents} />);

      // Click on root span (which has events) - find parent element
      const rootSpanElements = screen.getAllByText('Test Agent Execution');
      const rootSpanRow = rootSpanElements[rootSpanElements.length - 1].parentElement;
      if (rootSpanRow) {
        fireEvent.click(rootSpanRow);
      }

      expect(screen.getByText('Events')).toBeInTheDocument();
      expect(screen.getByText('checkpoint_reached')).toBeInTheDocument();
      expect(screen.getByText('retry_attempt')).toBeInTheDocument();
    });
  });
});
