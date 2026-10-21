import React, { useState } from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { DomainListField } from './DomainListField';

const Harness: React.FC<{ initial?: string; spy?: (v: string) => void }> = ({ initial = '', spy }) => {
  const [value, setValue] = useState(initial);
  return (
    <DomainListField
      id="d"
      value={value}
      onChange={(v) => {
        setValue(v);
        spy?.(v);
      }}
    />
  );
};

describe('DomainListField', () => {
  it('adds domains including wildcards', () => {
    const spy = jest.fn();
    render(<Harness spy={spy} />);
    fireEvent.change(screen.getByTestId('d'), { target: { value: 'ops.example.org' } });
    fireEvent.click(screen.getByTestId('d-add'));
    fireEvent.change(screen.getByTestId('d'), { target: { value: '*.apps.example.org' } });
    fireEvent.click(screen.getByTestId('d-add'));

    expect(screen.getByText('ops.example.org')).toBeInTheDocument();
    expect(screen.getByText('*.apps.example.org')).toBeInTheDocument();
    expect(spy).toHaveBeenLastCalledWith('ops.example.org\n*.apps.example.org');
  });

  it('rejects an invalid hostname', () => {
    const spy = jest.fn();
    render(<Harness spy={spy} />);
    fireEvent.change(screen.getByTestId('d'), { target: { value: 'bad host!' } });
    fireEvent.click(screen.getByTestId('d-add'));

    expect(screen.getByTestId('d-error')).toBeInTheDocument();
    expect(spy).not.toHaveBeenCalled();
  });

  it('removes a domain', () => {
    const spy = jest.fn();
    render(<Harness initial={'a.example.com\nb.example.com'} spy={spy} />);
    fireEvent.click(screen.getByLabelText('Remove a.example.com'));

    expect(screen.queryByText('a.example.com')).not.toBeInTheDocument();
    expect(spy).toHaveBeenLastCalledWith('b.example.com');
  });

  it('shows a note only when a wildcard domain is present', () => {
    const { unmount } = render(<Harness initial="a.example.com" />);
    expect(screen.queryByTestId('d-wildcard-note')).not.toBeInTheDocument();
    unmount();
    render(<Harness initial="*.example.com" />);
    expect(screen.getByTestId('d-wildcard-note')).toBeInTheDocument();
  });

  it('does not duplicate an existing domain', () => {
    const spy = jest.fn();
    render(<Harness initial="a.example.com" spy={spy} />);
    fireEvent.change(screen.getByTestId('d'), { target: { value: 'A.example.com' } });
    fireEvent.click(screen.getByTestId('d-add'));
    expect(spy).not.toHaveBeenCalled();
  });
});
