import { render, screen } from '@testing-library/react';
import { CapabilityBadge } from '../components/CapabilityBadge';

describe('CapabilityBadge', () => {
  it('renders skill name', () => {
    render(<CapabilityBadge skill={{ id: 'summarize', name: 'Summarize' }} />);

    expect(screen.getByText('Summarize')).toBeInTheDocument();
  });

  it('shows tooltip with description on hover', () => {
    render(
      <CapabilityBadge
        skill={{
          id: 'summarize',
          name: 'Summarize',
          description: 'Summarize long documents',
        }}
      />
    );

    expect(screen.getByTitle('Summarize long documents')).toBeInTheDocument();
  });

  it('applies category-based color for data skills', () => {
    const { container } = render(
      <CapabilityBadge skill={{ id: 'data_analysis', name: 'Data Analysis' }} />
    );

    // Should have a data-related color class
    expect(container.firstChild).toHaveClass('bg-');
  });

  it('applies category-based color for communication skills', () => {
    const { container } = render(
      <CapabilityBadge skill={{ id: 'translate', name: 'Translate' }} />
    );

    expect(container.firstChild).toHaveClass('bg-');
  });

  it('applies default color for unknown skills', () => {
    const { container } = render(
      <CapabilityBadge skill={{ id: 'unknown_skill', name: 'Unknown' }} />
    );

    expect(container.firstChild).toHaveClass('bg-');
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
});
