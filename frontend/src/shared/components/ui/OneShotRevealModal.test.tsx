import { render, screen, within } from '@testing-library/react';
import { OneShotRevealModal } from './OneShotRevealModal';

// IMP-246994888a1f — the shared one-shot reveal has no schema: it renders
// whatever fields a server operation minted. These pin what it does with the
// shapes it cannot predict.

describe('OneShotRevealModal', () => {
  it('drops fields that carry nothing to save', () => {
    render(
      <OneShotRevealModal
        values={{ token: 'tok_zz_test_only', revoked_at: null, note: undefined }}
        onDone={() => undefined}
      />
    );

    const reveal = screen.getByTestId('one-shot-reveal');
    expect(within(reveal).getByText('tok_zz_test_only')).toBeInTheDocument();
    expect(within(reveal).queryByText('Revoked at')).not.toBeInTheDocument();
    expect(within(reveal).queryByText('null')).not.toBeInTheDocument();
  });

  it('serializes a non-string value rather than rendering [object Object]', () => {
    render(
      <OneShotRevealModal values={{ rotated: { attempt: 2 } }} onDone={() => undefined} />
    );

    expect(screen.getByText('{"attempt":2}')).toBeInTheDocument();
    expect(screen.queryByText('[object Object]')).not.toBeInTheDocument();
  });

  it('labels a field without mangling an acronym in its key', () => {
    render(<OneShotRevealModal values={{ webhook_url: 'https://example.invalid/h' }} onDone={() => undefined} />);

    expect(screen.getByText('Webhook URL')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Copy Webhook URL' })).toBeInTheDocument();
  });
});
