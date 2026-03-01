import { render, screen } from '@testing-library/react';
import { CapabilityBadge, CapabilityList } from '../components/CapabilityBadge';

describe('CapabilityBadge', () => {
  it('renders skill name', () => {
    render(<CapabilityBadge skill={{ id: 'summarize', name: 'Summarize' }} />);

    expect(screen.getByText('Summarize')).toBeInTheDocument();
  });

  it('shows description when showDescription is true', () => {
    render(
      <CapabilityBadge
        skill={{
          id: 'summarize',
          name: 'Summarize',
          description: 'Summarize long documents',
        }}
        showDescription={true}
      />
    );

    expect(screen.getByText('Summarize')).toBeInTheDocument();
    expect(screen.getByText('Summarize long documents')).toBeInTheDocument();
  });

  it('does not show description by default', () => {
    render(
      <CapabilityBadge
        skill={{
          id: 'summarize',
          name: 'Summarize',
          description: 'Summarize long documents',
        }}
      />
    );

    expect(screen.getByText('Summarize')).toBeInTheDocument();
    expect(screen.queryByText('Summarize long documents')).not.toBeInTheDocument();
  });

  it('renders with custom className', () => {
    const { container } = render(
      <CapabilityBadge
        skill={{ id: 'test', name: 'Test' }}
        className="custom-class"
      />
    );

    expect(container.firstChild).toHaveClass('custom-class');
  });

  it('handles skills without description', () => {
    render(<CapabilityBadge skill={{ id: 'no_desc', name: 'No Description' }} />);

    expect(screen.getByText('No Description')).toBeInTheDocument();
  });

  it('uses skill id as fallback when name is missing', () => {
    render(<CapabilityBadge skill={{ id: 'test_skill' } as { id: string; name?: string }} />);

    expect(screen.getByText('test_skill')).toBeInTheDocument();
  });
});

describe('CapabilityList', () => {
  const mockSkills = [
    { id: 'summarize', name: 'Summarize' },
    { id: 'translate', name: 'Translate' },
    { id: 'analyze', name: 'Analyze' },
    { id: 'generate', name: 'Generate' },
    { id: 'transform', name: 'Transform' },
  ];

  it('renders limited skills by default (maxVisible=3)', () => {
    render(<CapabilityList skills={mockSkills} />);

    expect(screen.getByText('Summarize')).toBeInTheDocument();
    expect(screen.getByText('Translate')).toBeInTheDocument();
    expect(screen.getByText('Analyze')).toBeInTheDocument();
    expect(screen.queryByText('Generate')).not.toBeInTheDocument();
    expect(screen.getByText('+2 more')).toBeInTheDocument();
  });

  it('renders all skills when showAll is true', () => {
    render(<CapabilityList skills={mockSkills} showAll={true} />);

    expect(screen.getByText('Summarize')).toBeInTheDocument();
    expect(screen.getByText('Translate')).toBeInTheDocument();
    expect(screen.getByText('Analyze')).toBeInTheDocument();
    expect(screen.getByText('Generate')).toBeInTheDocument();
    expect(screen.getByText('Transform')).toBeInTheDocument();
    expect(screen.queryByText(/more/)).not.toBeInTheDocument();
  });

  it('respects custom maxVisible value', () => {
    render(<CapabilityList skills={mockSkills} maxVisible={2} />);

    expect(screen.getByText('Summarize')).toBeInTheDocument();
    expect(screen.getByText('Translate')).toBeInTheDocument();
    expect(screen.queryByText('Analyze')).not.toBeInTheDocument();
    expect(screen.getByText('+3 more')).toBeInTheDocument();
  });

  it('does not show more badge when skills fit within maxVisible', () => {
    render(<CapabilityList skills={mockSkills.slice(0, 2)} maxVisible={3} />);

    expect(screen.getByText('Summarize')).toBeInTheDocument();
    expect(screen.getByText('Translate')).toBeInTheDocument();
    expect(screen.queryByText(/more/)).not.toBeInTheDocument();
  });

  it('renders with custom className', () => {
    const { container } = render(
      <CapabilityList skills={mockSkills} className="custom-class" />
    );

    expect(container.firstChild).toHaveClass('custom-class');
  });
});
