import { render, screen, fireEvent } from '@testing-library/react';
import { PolicyEnvironmentSelect } from './PolicyEnvironmentSelect';

const OPTIONS = [
  { slug: 'dev', name: 'Development', tier: 0 },
  { slug: 'staging', name: 'Staging', tier: 1 },
  { slug: 'ops', name: 'Operations', tier: 2 },
];

describe('PolicyEnvironmentSelect', () => {
  it('renders one option per environment, unticked when nothing is selected', () => {
    render(<PolicyEnvironmentSelect options={OPTIONS} status="ready" value={[]} onChange={jest.fn()} />);

    expect(screen.getAllByRole('checkbox')).toHaveLength(3);
    screen.getAllByRole('checkbox').forEach(box => expect(box).not.toBeChecked());
    expect(screen.getByText(/applies in every environment/)).toBeInTheDocument();
  });

  it('pre-selects the environments the policy already names', () => {
    render(<PolicyEnvironmentSelect options={OPTIONS} status="ready" value={['staging', 'ops']} onChange={jest.fn()} />);

    expect(screen.getByLabelText('Staging')).toBeChecked();
    expect(screen.getByLabelText('Operations')).toBeChecked();
    expect(screen.getByLabelText('Development')).not.toBeChecked();
  });

  it('emits an array on toggle, adding and removing', () => {
    const onChange = jest.fn();
    const { rerender } = render(<PolicyEnvironmentSelect options={OPTIONS} status="ready" value={['staging']} onChange={onChange} />);

    fireEvent.click(screen.getByLabelText('Operations'));
    expect(onChange).toHaveBeenLastCalledWith(['staging', 'ops']);

    rerender(<PolicyEnvironmentSelect options={OPTIONS} status="ready" value={['staging', 'ops']} onChange={onChange} />);
    fireEvent.click(screen.getByLabelText('Staging'));
    expect(onChange).toHaveBeenLastCalledWith(['ops']);
  });

  it('keeps a slug that is no longer an environment listed so it can be unticked', () => {
    const onChange = jest.fn();
    render(<PolicyEnvironmentSelect options={OPTIONS} status="ready" value={['staging', 'gone']} onChange={onChange} />);

    const stale = screen.getByLabelText('gone (no longer an environment)');
    expect(stale).toBeChecked();
    fireEvent.click(stale);
    expect(onChange).toHaveBeenLastCalledWith(['staging']);
  });

  it('while loading, shows the selection unflagged and not editable', () => {
    const onChange = jest.fn();
    render(<PolicyEnvironmentSelect options={[]} status="loading" value={['staging']} onChange={onChange} />);

    const box = screen.getByLabelText('staging');
    expect(box).toBeChecked();
    expect(box).toBeDisabled();
    expect(screen.queryByText(/no longer an environment/)).not.toBeInTheDocument();
    expect(screen.getByText('Loading environments...')).toBeInTheDocument();
  });

  it('on a failed load, keeps the selection unflagged and not editable, with an error notice', () => {
    render(<PolicyEnvironmentSelect options={[]} status="error" value={['staging']} onChange={jest.fn()} />);

    expect(screen.getByLabelText('staging')).toBeDisabled();
    expect(screen.queryByText(/no longer an environment/)).not.toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Could not load environments');
  });
});
