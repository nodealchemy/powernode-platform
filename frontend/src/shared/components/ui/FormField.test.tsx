import { render, screen, fireEvent } from '@testing-library/react';
import { FormField } from './FormField';

/**
 * FormField renders its label as a SIBLING of the control, not a wrapper. That
 * makes the label/control association entirely dependent on `htmlFor` + `id`:
 * without them the control is unlabelled to assistive technology, and
 * `getByLabelText` cannot find it either — which is why every caller that had
 * adopted this component was querying by placeholder instead.
 *
 * These examples pin the association per control type, because each type is a
 * separate branch of `renderInput` and wiring one says nothing about the rest.
 */
describe('FormField label association', () => {
  it('associates the label with a text input', () => {
    const onChange = jest.fn();
    render(<FormField label="Node name" value="" onChange={onChange} />);

    const input = screen.getByLabelText('Node name');
    fireEvent.change(input, { target: { value: 'web-01' } });
    expect(onChange).toHaveBeenCalledWith('web-01');
  });

  it('associates the label with a select', () => {
    const onChange = jest.fn();
    render(
      <FormField
        label="Variety"
        type="select"
        value="cloud"
        onChange={onChange}
        options={[
          { value: 'cloud', label: 'Cloud' },
          { value: 'physical', label: 'Physical' },
        ]}
      />,
    );

    const select = screen.getByLabelText('Variety');
    fireEvent.change(select, { target: { value: 'physical' } });
    expect(onChange).toHaveBeenCalledWith('physical');
  });

  it('associates the label with a textarea', () => {
    const onChange = jest.fn();
    render(<FormField label="Description" type="textarea" value="" onChange={onChange} />);

    const textarea = screen.getByLabelText('Description');
    fireEvent.change(textarea, { target: { value: 'notes' } });
    expect(onChange).toHaveBeenCalledWith('notes');
  });

  it('associates the label with a password input', () => {
    const onChange = jest.fn();
    render(<FormField label="Token" type="password" value="" onChange={onChange} />);

    expect(screen.getByLabelText('Token')).toBeInTheDocument();
  });

  it('gives two fields sharing a label text distinct ids', () => {
    // The generated id must be per-instance, or the second field's label would
    // point at the first field's control.
    render(
      <>
        <FormField label="Name" value="a" onChange={jest.fn()} />
        <FormField label="Name" value="b" onChange={jest.fn()} />
      </>,
    );

    const [first, second] = screen.getAllByLabelText('Name');
    expect(first.id).not.toBe('');
    expect(second.id).not.toBe('');
    expect(first.id).not.toBe(second.id);
  });

  it('lets a caller pin the id', () => {
    render(<FormField label="Region" id="region-field" value="" onChange={jest.fn()} />);

    expect(screen.getByLabelText('Region')).toHaveAttribute('id', 'region-field');
  });

  it('passes numeric bounds through to a number input', () => {
    // Without these a caller adopting FormField would have to drop a
    // browser-enforced constraint it previously had.
    render(
      <FormField label="Size (GB)" type="number" value="10" onChange={jest.fn()} min={1} max={16384} />,
    );

    const input = screen.getByLabelText('Size (GB)');
    expect(input).toHaveAttribute('min', '1');
    expect(input).toHaveAttribute('max', '16384');
  });

  it('passes a virtual-keyboard hint through to a text input', () => {
    // The numeric catalog fields are typed as text so a half-typed value
    // survives, and would otherwise lose their numeric keypad on adoption.
    render(
      <FormField label="vCPUs" value="4" onChange={jest.fn()} inputMode="decimal" />,
    );

    expect(screen.getByLabelText('vCPUs')).toHaveAttribute('inputmode', 'decimal');
  });

  it('keeps an inline label annotation while an error is showing', () => {
    // helpText is suppressed by an error, so a permanent annotation on the
    // field's name has to live in the label itself.
    render(
      <FormField
        label={<>Configuration <span>(JSON)</span></>}
        value="{"
        onChange={jest.fn()}
        error="Invalid JSON"
      />,
    );

    expect(screen.getByLabelText('Configuration (JSON)')).toBeInTheDocument();
    expect(screen.getByText('Invalid JSON')).toBeInTheDocument();
  });

  it('renders helpText until an error replaces it', () => {
    const { rerender } = render(
      <FormField label="CIDR" value="" onChange={jest.fn()} helpText="e.g. 10.0.0.0/16" />,
    );
    expect(screen.getByText('e.g. 10.0.0.0/16')).toBeInTheDocument();

    rerender(
      <FormField
        label="CIDR"
        value=""
        onChange={jest.fn()}
        helpText="e.g. 10.0.0.0/16"
        error="Invalid CIDR"
      />,
    );
    expect(screen.getByText('Invalid CIDR')).toBeInTheDocument();
    expect(screen.queryByText('e.g. 10.0.0.0/16')).not.toBeInTheDocument();
  });
});
