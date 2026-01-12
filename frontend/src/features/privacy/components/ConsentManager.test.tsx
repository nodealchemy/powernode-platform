import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ConsentManager } from './ConsentManager';
import { ConsentPreferences } from '../services/privacyApi';

describe('ConsentManager', () => {
  const mockConsents: ConsentPreferences = {
    marketing: {
      granted: true,
      required: false,
      description: 'Receive marketing emails',
      granted_at: '2025-01-15T10:00:00Z'
    },
    analytics: {
      granted: false,
      required: false,
      description: 'Allow usage analytics'
    },
    cookies: {
      granted: true,
      required: true,
      description: 'Essential cookies for service'
    },
    data_sharing: {
      granted: false,
      required: false,
      description: 'Share data with partners'
    },
    third_party: {
      granted: false,
      required: false,
      description: 'Third party data access'
    },
    communications: {
      granted: true,
      required: false,
      description: 'General communications'
    },
    newsletter: {
      granted: false,
      required: false,
      description: 'Newsletter subscription'
    },
    promotional: {
      granted: false,
      required: false,
      description: 'Promotional offers'
    }
  };

  const defaultProps = {
    consents: mockConsents,
    onUpdate: jest.fn().mockResolvedValue(undefined),
    loading: false
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('shows title', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText('Consent Preferences')).toBeInTheDocument();
    });

    it('shows description', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText('Manage how your data is used')).toBeInTheDocument();
    });

    it('shows privacy rights info section', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText('Your Privacy Rights')).toBeInTheDocument();
    });

    it('shows consent type labels', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText('Marketing Communications')).toBeInTheDocument();
      expect(screen.getByText('Usage Analytics')).toBeInTheDocument();
      expect(screen.getByText('Non-Essential Cookies')).toBeInTheDocument();
      expect(screen.getByText('Data Sharing')).toBeInTheDocument();
    });

    it('shows consent descriptions', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText('Receive marketing emails')).toBeInTheDocument();
      expect(screen.getByText('Allow usage analytics')).toBeInTheDocument();
      expect(screen.getByText('Essential cookies for service')).toBeInTheDocument();
    });
  });

  describe('consent toggles', () => {
    it('shows toggle switches for each consent', () => {
      render(<ConsentManager {...defaultProps} />);

      const switches = screen.getAllByRole('switch');
      expect(switches).toHaveLength(4);
    });

    it('shows granted state correctly', () => {
      render(<ConsentManager {...defaultProps} />);

      const switches = screen.getAllByRole('switch');

      // Marketing is granted
      expect(switches[0]).toHaveAttribute('aria-checked', 'true');
      // Analytics is not granted
      expect(switches[1]).toHaveAttribute('aria-checked', 'false');
    });

    it('shows Required badge for required consents', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText('Required')).toBeInTheDocument();
    });

    it('disables toggle for required consents', () => {
      render(<ConsentManager {...defaultProps} />);

      const switches = screen.getAllByRole('switch');
      // Cookies is required (index 2)
      expect(switches[2]).toBeDisabled();
    });

    it('enables toggle for non-required consents', () => {
      render(<ConsentManager {...defaultProps} />);

      const switches = screen.getAllByRole('switch');
      // Marketing is not required (index 0)
      expect(switches[0]).not.toBeDisabled();
    });
  });

  describe('toggle interactions', () => {
    it('toggles consent when switch clicked', () => {
      render(<ConsentManager {...defaultProps} />);

      const switches = screen.getAllByRole('switch');
      // Toggle analytics (currently false)
      fireEvent.click(switches[1]);

      // The local state should change, showing Save Changes button
      expect(screen.getByText('Save Changes')).toBeInTheDocument();
    });

    it('shows Save Changes button after toggling', () => {
      render(<ConsentManager {...defaultProps} />);

      // Initially no Save Changes button
      expect(screen.queryByText('Save Changes')).not.toBeInTheDocument();

      const switches = screen.getAllByRole('switch');
      fireEvent.click(switches[0]); // Toggle marketing

      expect(screen.getByText('Save Changes')).toBeInTheDocument();
    });

    it('does not toggle required consents', () => {
      render(<ConsentManager {...defaultProps} />);

      const switches = screen.getAllByRole('switch');
      // Cookies is required and granted
      const cookiesSwitch = switches[2];

      fireEvent.click(cookiesSwitch);

      // Should still be checked
      expect(cookiesSwitch).toHaveAttribute('aria-checked', 'true');
      // No Save Changes button should appear
      expect(screen.queryByText('Save Changes')).not.toBeInTheDocument();
    });
  });

  describe('save functionality', () => {
    it('calls onUpdate when Save Changes clicked', async () => {
      const onUpdate = jest.fn().mockResolvedValue(undefined);
      render(<ConsentManager {...defaultProps} onUpdate={onUpdate} />);

      const switches = screen.getAllByRole('switch');
      fireEvent.click(switches[1]); // Toggle analytics to true

      fireEvent.click(screen.getByText('Save Changes'));

      await waitFor(() => {
        expect(onUpdate).toHaveBeenCalledWith({ analytics: true });
      });
    });

    it('shows Saving... while saving', async () => {
      const onUpdate = jest.fn().mockImplementation(() => new Promise(() => {}));
      render(<ConsentManager {...defaultProps} onUpdate={onUpdate} />);

      const switches = screen.getAllByRole('switch');
      fireEvent.click(switches[0]); // Toggle marketing

      fireEvent.click(screen.getByText('Save Changes'));

      expect(screen.getByText('Saving...')).toBeInTheDocument();
    });

    it('disables Save button while saving', async () => {
      const onUpdate = jest.fn().mockImplementation(() => new Promise(() => {}));
      render(<ConsentManager {...defaultProps} onUpdate={onUpdate} />);

      const switches = screen.getAllByRole('switch');
      fireEvent.click(switches[0]);

      fireEvent.click(screen.getByText('Save Changes'));

      expect(screen.getByText('Saving...')).toBeDisabled();
    });

    it('hides Save Changes button after successful save', async () => {
      const onUpdate = jest.fn().mockResolvedValue(undefined);
      render(<ConsentManager {...defaultProps} onUpdate={onUpdate} />);

      const switches = screen.getAllByRole('switch');
      fireEvent.click(switches[1]); // Toggle analytics

      fireEvent.click(screen.getByText('Save Changes'));

      await waitFor(() => {
        expect(screen.queryByText('Save Changes')).not.toBeInTheDocument();
      });
    });

    it('only sends changed consents in update', async () => {
      const onUpdate = jest.fn().mockResolvedValue(undefined);
      render(<ConsentManager {...defaultProps} onUpdate={onUpdate} />);

      const switches = screen.getAllByRole('switch');
      // Toggle marketing (from true to false)
      fireEvent.click(switches[0]);
      // Toggle analytics (from false to true)
      fireEvent.click(switches[1]);

      fireEvent.click(screen.getByText('Save Changes'));

      await waitFor(() => {
        expect(onUpdate).toHaveBeenCalledWith({
          marketing: false,
          analytics: true
        });
      });
    });
  });

  describe('granted date display', () => {
    it('shows granted date for granted consents', () => {
      render(<ConsentManager {...defaultProps} />);

      // Marketing has granted_at date
      expect(screen.getByText(/Granted:/)).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('disables all toggles when loading', () => {
      render(<ConsentManager {...defaultProps} loading={true} />);

      const switches = screen.getAllByRole('switch');
      switches.forEach(switchEl => {
        expect(switchEl).toBeDisabled();
      });
    });
  });

  describe('icons', () => {
    it('shows emoji icons for consent types', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText('📢')).toBeInTheDocument(); // marketing
      expect(screen.getByText('📊')).toBeInTheDocument(); // analytics
      expect(screen.getByText('🍪')).toBeInTheDocument(); // cookies
      expect(screen.getByText('🔗')).toBeInTheDocument(); // data_sharing
    });
  });

  describe('privacy info', () => {
    it('shows privacy information', () => {
      render(<ConsentManager {...defaultProps} />);

      expect(screen.getByText(/You can withdraw consent at any time/)).toBeInTheDocument();
      expect(screen.getByText(/Required consents are necessary/)).toBeInTheDocument();
    });
  });

  describe('unknown consent types', () => {
    it('handles unknown consent types with default label', () => {
      const consentsWithUnknown = {
        ...mockConsents,
        unknown_type: {
          granted: false,
          required: false,
          description: 'Unknown consent type'
        }
      };

      render(<ConsentManager {...defaultProps} consents={consentsWithUnknown} />);

      // Unknown type should use the key as label
      expect(screen.getByText('unknown_type')).toBeInTheDocument();
      expect(screen.getByText('⚙️')).toBeInTheDocument(); // default icon
    });
  });
});
