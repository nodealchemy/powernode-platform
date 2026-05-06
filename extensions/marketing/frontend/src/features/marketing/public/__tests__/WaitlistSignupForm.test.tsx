import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { WaitlistSignupForm } from '../WaitlistSignupForm';
import { leadsApi } from '../../services/leadsApi';

// Mock the API client — tests assert on call arguments + control responses
jest.mock('../../services/leadsApi', () => ({
  leadsApi: {
    submitWaitlist: jest.fn(),
  },
}));

const mockSubmit = leadsApi.submitWaitlist as jest.MockedFunction<typeof leadsApi.submitWaitlist>;

describe('WaitlistSignupForm', () => {
  beforeEach(() => {
    mockSubmit.mockReset();
    // Reset URL so tests don't leak UTM state between cases
    window.history.replaceState({}, '', '/');
  });

  describe('initial render', () => {
    it('shows the form with email input and disabled submit button', () => {
      render(<WaitlistSignupForm />);

      expect(screen.getByTestId('waitlist-form')).toBeInTheDocument();
      expect(screen.getByTestId('waitlist-email-input')).toBeInTheDocument();
      expect(screen.getByTestId('waitlist-submit')).toBeDisabled();
    });

    it('enables the submit button once the user types an email', async () => {
      const user = userEvent.setup();
      render(<WaitlistSignupForm />);

      await user.type(screen.getByTestId('waitlist-email-input'), 'foo@example.com');
      expect(screen.getByTestId('waitlist-submit')).toBeEnabled();
    });
  });

  describe('happy-path submission', () => {
    it('calls leadsApi.submitWaitlist with the email + source', async () => {
      mockSubmit.mockResolvedValue({
        data: { id: 'abc', email: 'foo@example.com', status: 'confirmed' },
        message: "You're on the waitlist.",
      });

      const user = userEvent.setup();
      render(<WaitlistSignupForm source="pricing-page" />);

      await user.type(screen.getByTestId('waitlist-email-input'), 'foo@example.com');
      await user.click(screen.getByTestId('waitlist-submit'));

      await waitFor(() => {
        expect(mockSubmit).toHaveBeenCalledWith(expect.objectContaining({
          email: 'foo@example.com',
          source: 'pricing-page',
        }));
      });
    });

    it('shows the success state with the API message after a successful submit', async () => {
      mockSubmit.mockResolvedValue({
        data: { id: 'abc', email: 'foo@example.com', status: 'confirmed' },
        message: 'Welcome aboard!',
      });

      const user = userEvent.setup();
      render(<WaitlistSignupForm />);

      await user.type(screen.getByTestId('waitlist-email-input'), 'foo@example.com');
      await user.click(screen.getByTestId('waitlist-submit'));

      await waitFor(() => {
        expect(screen.getByTestId('waitlist-success')).toBeInTheDocument();
      });
      expect(screen.getByText('Welcome aboard!')).toBeInTheDocument();
      // Form is replaced by success state
      expect(screen.queryByTestId('waitlist-form')).not.toBeInTheDocument();
    });

    it('captures UTM params from window.location.search', async () => {
      window.history.replaceState({}, '', '/?utm_source=twitter&utm_medium=social&utm_campaign=launch');
      mockSubmit.mockResolvedValue({
        data: { id: 'abc', email: 'foo@example.com', status: 'confirmed' },
        message: 'OK',
      });

      const user = userEvent.setup();
      render(<WaitlistSignupForm />);

      await user.type(screen.getByTestId('waitlist-email-input'), 'foo@example.com');
      await user.click(screen.getByTestId('waitlist-submit'));

      await waitFor(() => {
        expect(mockSubmit).toHaveBeenCalledWith(expect.objectContaining({
          utm_source: 'twitter',
          utm_medium: 'social',
          utm_campaign: 'launch',
        }));
      });
    });
  });

  describe('error handling', () => {
    it('shows the error message when the API rejects', async () => {
      mockSubmit.mockRejectedValue(new Error('Server unavailable'));

      const user = userEvent.setup();
      render(<WaitlistSignupForm />);

      await user.type(screen.getByTestId('waitlist-email-input'), 'foo@example.com');
      await user.click(screen.getByTestId('waitlist-submit'));

      await waitFor(() => {
        expect(screen.getByTestId('waitlist-error')).toHaveTextContent('Server unavailable');
      });
      // Form remains visible so user can retry
      expect(screen.getByTestId('waitlist-form')).toBeInTheDocument();
    });

    it('rejects locally if the email lacks an @ sign', async () => {
      const user = userEvent.setup();
      render(<WaitlistSignupForm />);

      const input = screen.getByTestId('waitlist-email-input');
      // Bypass the input's type=email validation by setting the value directly
      // via fireEvent-equivalent — we want to test the component's own check.
      // The button stays enabled with non-empty content; click triggers submit.
      await user.type(input, 'plaintext');

      // The HTML5 type=email blocks submit at the browser level when the
      // browser is strict; jsdom is permissive, so the component's own
      // `email.includes('@')` check is the load-bearing guard. Force-submit
      // the form to exercise that path.
      const form = screen.getByTestId('waitlist-form');
      form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));

      await waitFor(() => {
        expect(screen.getByTestId('waitlist-error')).toHaveTextContent(/valid email/i);
      });
      expect(mockSubmit).not.toHaveBeenCalled();
    });
  });

  describe('loading state', () => {
    it('shows "Joining…" and disables the button while the API call is in flight', async () => {
      let resolveSubmit: (value: { data: object; message: string }) => void = () => {};
      mockSubmit.mockImplementation(() => new Promise(resolve => { resolveSubmit = resolve; }));

      const user = userEvent.setup();
      render(<WaitlistSignupForm />);

      await user.type(screen.getByTestId('waitlist-email-input'), 'foo@example.com');
      await user.click(screen.getByTestId('waitlist-submit'));

      expect(screen.getByTestId('waitlist-submit')).toHaveTextContent(/joining/i);
      expect(screen.getByTestId('waitlist-submit')).toBeDisabled();

      // Cleanly resolve the pending promise so the test doesn't dangle
      resolveSubmit({ data: { status: 'confirmed' }, message: 'OK' });
      await waitFor(() => expect(screen.getByTestId('waitlist-success')).toBeInTheDocument());
    });
  });
});
