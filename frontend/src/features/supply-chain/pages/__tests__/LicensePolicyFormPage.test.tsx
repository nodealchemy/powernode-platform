import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { LicensePolicyFormPage } from '../LicensePolicyFormPage';
import {
  useLicensePolicy,
  useCreateLicensePolicy,
  useUpdateLicensePolicy,
} from '../../hooks/useLicenseCompliance';
import { createMockLicensePolicy } from '../../testing/mockFactories';

jest.mock('../../hooks/useLicenseCompliance');
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: jest.fn() }),
}));

const mockNavigate = jest.fn();
const mockParams: { id: string | undefined } = { id: undefined };
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: () => mockParams,
}));

const mockUseLicensePolicy = useLicensePolicy as jest.MockedFunction<typeof useLicensePolicy>;
const mockUseCreateLicensePolicy = useCreateLicensePolicy as jest.MockedFunction<typeof useCreateLicensePolicy>;
const mockUseUpdateLicensePolicy = useUpdateLicensePolicy as jest.MockedFunction<typeof useUpdateLicensePolicy>;

describe('LicensePolicyFormPage', () => {
  const mockExistingPolicy = createMockLicensePolicy({
    id: 'policy-123',
    name: 'Existing Policy',
    description: 'Test policy description',
    policy_type: 'allowlist',
    enforcement_level: 'block',
    is_active: true,
    block_copyleft: true,
    block_strong_copyleft: false,
    allowed_licenses: ['MIT', 'Apache-2.0'],
    denied_licenses: ['GPL-3.0'],
  });

  const mockCreateMutation = {
    mutateAsync: jest.fn(),
    isLoading: false,
    error: null,
  };

  const mockUpdateMutation = {
    mutateAsync: jest.fn(),
    isLoading: false,
    error: null,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockParams.id = undefined;
    mockUseLicensePolicy.mockReturnValue({
      data: null,
      isLoading: false,
      error: null,
      refetch: jest.fn(),
    });
    mockUseCreateLicensePolicy.mockReturnValue(mockCreateMutation);
    mockUseUpdateLicensePolicy.mockReturnValue(mockUpdateMutation);
  });

  const renderComponent = () => {
    return render(
      <BreadcrumbProvider>
        <BrowserRouter>
          <LicensePolicyFormPage />
        </BrowserRouter>
      </BreadcrumbProvider>
    );
  };

  describe('create mode', () => {
    it('renders create title when no ID in params', () => {
      renderComponent();
      expect(screen.getByText('Create License Policy')).toBeInTheDocument();
    });

    it('renders create description', () => {
      renderComponent();
      expect(screen.getByText('Define a new license compliance policy')).toBeInTheDocument();
    });

    it('renders breadcrumbs for create', () => {
      renderComponent();
      expect(screen.getByText('New Policy')).toBeInTheDocument();
    });

    it('shows Create Policy submit button', () => {
      renderComponent();
      expect(screen.getByText('Create Policy')).toBeInTheDocument();
    });
  });

  describe('edit mode', () => {
    beforeEach(() => {
      mockParams.id = 'policy-123';
      mockUseLicensePolicy.mockReturnValue({
        data: mockExistingPolicy,
        isLoading: false,
        error: null,
        refetch: jest.fn(),
      });
    });

    it('renders edit title when ID in params', () => {
      renderComponent();
      expect(screen.getByText('Edit License Policy')).toBeInTheDocument();
    });

    it('renders edit description', () => {
      renderComponent();
      expect(screen.getByText('Update license compliance policy settings')).toBeInTheDocument();
    });

    it('renders breadcrumbs for edit', () => {
      renderComponent();
      expect(screen.getByText('Edit Policy')).toBeInTheDocument();
    });

    it('shows Update Policy submit button', () => {
      renderComponent();
      expect(screen.getByText('Update Policy')).toBeInTheDocument();
    });

    it('pre-fills form with existing policy data', () => {
      renderComponent();
      const nameInput = screen.getByPlaceholderText('e.g., Production Strict Policy') as HTMLInputElement;
      expect(nameInput.value).toBe('Existing Policy');
    });

    it('shows loading spinner while loading policy', () => {
      mockUseLicensePolicy.mockReturnValue({
        data: null,
        isLoading: true,
        error: null,
        refetch: jest.fn(),
      });
      const { container } = renderComponent();
      expect(container.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('shows error when policy fails to load', () => {
      mockUseLicensePolicy.mockReturnValue({
        data: null,
        isLoading: false,
        error: 'Failed to load',
        refetch: jest.fn(),
      });
      renderComponent();
      expect(screen.getByText('Failed to load policy')).toBeInTheDocument();
    });
  });

  describe('basic information section', () => {
    it('renders policy name field', () => {
      renderComponent();
      expect(screen.getByText(/Policy Name/)).toBeInTheDocument();
      expect(screen.getByPlaceholderText('e.g., Production Strict Policy')).toBeInTheDocument();
    });

    it('renders description field', () => {
      renderComponent();
      expect(screen.getByText('Description')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('Describe the purpose and scope of this policy...')).toBeInTheDocument();
    });

    it('renders active checkbox', () => {
      renderComponent();
      const checkbox = screen.getByLabelText('Policy is active');
      expect(checkbox).toBeInTheDocument();
      expect(checkbox).toBeChecked();
    });

    it('allows unchecking active checkbox', () => {
      renderComponent();
      const checkbox = screen.getByLabelText('Policy is active') as HTMLInputElement;
      fireEvent.click(checkbox);
      expect(checkbox.checked).toBe(false);
    });
  });

  describe('policy type selection', () => {
    it('renders all policy type options', () => {
      renderComponent();
      expect(screen.getByText('Allowlist')).toBeInTheDocument();
      expect(screen.getByText('Denylist')).toBeInTheDocument();
      expect(screen.getByText('Hybrid')).toBeInTheDocument();
    });

    it('shows policy type descriptions', () => {
      renderComponent();
      expect(screen.getByText('Only explicitly allowed licenses are permitted')).toBeInTheDocument();
      expect(screen.getByText('All licenses are allowed except those explicitly denied')).toBeInTheDocument();
      expect(screen.getByText('Combines allowlist and denylist rules')).toBeInTheDocument();
    });

    it('defaults to denylist', () => {
      renderComponent();
      const denylisRadio = screen.getByDisplayValue('denylist') as HTMLInputElement;
      expect(denylisRadio.checked).toBe(true);
    });

    it('allows selecting different policy type', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist') as HTMLInputElement;
      fireEvent.click(allowlistRadio);
      expect(allowlistRadio.checked).toBe(true);
    });
  });

  describe('enforcement level selection', () => {
    it('renders all enforcement level options', () => {
      renderComponent();
      expect(screen.getByText('Log Only')).toBeInTheDocument();
      expect(screen.getByText('Warn')).toBeInTheDocument();
      expect(screen.getByText('Block')).toBeInTheDocument();
    });

    it('shows enforcement level descriptions', () => {
      renderComponent();
      expect(screen.getByText('Log violations without blocking')).toBeInTheDocument();
      expect(screen.getByText('Show warnings but allow builds to proceed')).toBeInTheDocument();
      expect(screen.getByText('Block builds with license violations')).toBeInTheDocument();
    });

    it('defaults to warn', () => {
      renderComponent();
      const warnRadio = screen.getByDisplayValue('warn') as HTMLInputElement;
      expect(warnRadio.checked).toBe(true);
    });

    it('allows selecting different enforcement level', () => {
      renderComponent();
      const blockRadio = screen.getByDisplayValue('block') as HTMLInputElement;
      fireEvent.click(blockRadio);
      expect(blockRadio.checked).toBe(true);
    });
  });

  describe('license restrictions', () => {
    it('renders all restriction checkboxes', () => {
      renderComponent();
      expect(screen.getByLabelText('Block all copyleft licenses')).toBeInTheDocument();
      expect(screen.getByLabelText('Block strong copyleft (GPL, etc.)')).toBeInTheDocument();
      expect(screen.getByLabelText('Block network copyleft (AGPL, etc.)')).toBeInTheDocument();
      expect(screen.getByLabelText('Block unknown licenses')).toBeInTheDocument();
      expect(screen.getByLabelText('Require OSI-approved licenses')).toBeInTheDocument();
      expect(screen.getByLabelText('Require attribution notices')).toBeInTheDocument();
    });

    it('allows checking restriction checkboxes', () => {
      renderComponent();
      const checkbox = screen.getByLabelText('Block all copyleft licenses') as HTMLInputElement;
      fireEvent.click(checkbox);
      expect(checkbox.checked).toBe(true);
    });

    it('allows unchecking restriction checkboxes', () => {
      renderComponent();
      const checkbox = screen.getByLabelText('Block all copyleft licenses') as HTMLInputElement;
      fireEvent.click(checkbox);
      fireEvent.click(checkbox);
      expect(checkbox.checked).toBe(false);
    });
  });

  describe('allowed licenses section', () => {
    it('hides allowed licenses for denylist policy', () => {
      renderComponent();
      expect(screen.queryByText('Allowed Licenses')).not.toBeInTheDocument();
    });

    it('shows allowed licenses for allowlist policy', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);
      expect(screen.getByText('Allowed Licenses')).toBeInTheDocument();
    });

    it('shows allowed licenses for hybrid policy', () => {
      renderComponent();
      const hybridRadio = screen.getByDisplayValue('hybrid');
      fireEvent.click(hybridRadio);
      expect(screen.getByText('Allowed Licenses')).toBeInTheDocument();
    });

    it('shows input field for adding licenses', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);
      expect(screen.getByPlaceholderText(/Enter SPDX license identifier/)).toBeInTheDocument();
    });

    it('allows adding a license', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      const input = screen.getByPlaceholderText(/Enter SPDX license identifier/) as HTMLInputElement;
      fireEvent.change(input, { target: { value: 'MIT' } });

      const addButton = input.nextElementSibling as HTMLElement;
      fireEvent.click(addButton);

      const mitBadges = screen.getAllByText('MIT');
      expect(mitBadges.some(el => el.tagName === 'SPAN')).toBe(true);
    });

    it('clears input after adding license', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      const input = screen.getByPlaceholderText(/Enter SPDX license identifier/) as HTMLInputElement;
      fireEvent.change(input, { target: { value: 'MIT' } });

      const addButton = input.nextElementSibling as HTMLElement;
      fireEvent.click(addButton);

      expect(input.value).toBe('');
    });

    it('allows adding license with Enter key', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      const input = screen.getByPlaceholderText(/Enter SPDX license identifier/);
      fireEvent.change(input, { target: { value: 'Apache-2.0' } });
      fireEvent.keyDown(input, { key: 'Enter', code: 'Enter' });

      const apacheBadges = screen.getAllByText('Apache-2.0');
      expect(apacheBadges.some(el => el.tagName === 'SPAN')).toBe(true);
    });

    it('prevents duplicate licenses', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      const input = screen.getByPlaceholderText(/Enter SPDX license identifier/) as HTMLInputElement;
      const addButton = input.nextElementSibling as HTMLElement;

      fireEvent.change(input, { target: { value: 'MIT' } });
      fireEvent.click(addButton);
      fireEvent.change(input, { target: { value: 'MIT' } });
      fireEvent.click(addButton);

      const mitBadges = screen.getAllByText('MIT');
      const mitBadgesInSpans = mitBadges.filter(el => el.tagName === 'SPAN');
      expect(mitBadgesInSpans.length).toBe(1);
    });

    it('allows removing a license', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      const input = screen.getByPlaceholderText(/Enter SPDX license identifier/) as HTMLInputElement;
      fireEvent.change(input, { target: { value: 'MIT' } });
      const addButton = input.nextElementSibling as HTMLElement;
      fireEvent.click(addButton);

      const mitBadges = screen.getAllByText('MIT');
      const mitBadgeSpan = mitBadges.find(el => el.tagName === 'SPAN') as HTMLElement;
      const removeButton = mitBadgeSpan.querySelector('button') as HTMLElement;
      fireEvent.click(removeButton);

      const remainingMitBadges = screen.queryAllByText('MIT');
      expect(remainingMitBadges.every(el => el.tagName !== 'SPAN')).toBe(true);
    });

    it('shows quick add buttons for common licenses', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      expect(screen.getByText('Quick add common licenses:')).toBeInTheDocument();
    });

    it('allows quick adding a common license', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      const quickAddButtons = screen.getAllByRole('button');
      const mitButton = quickAddButtons.find(btn => btn.textContent === 'MIT');
      if (mitButton) fireEvent.click(mitButton);

      const mitBadges = screen.getAllByText('MIT');
      expect(mitBadges.some(el => el.tagName === 'SPAN')).toBe(true);
    });
  });

  describe('denied licenses section', () => {
    it('shows denied licenses for denylist policy', () => {
      renderComponent();
      expect(screen.getByText('Denied Licenses')).toBeInTheDocument();
    });

    it('shows denied licenses for hybrid policy', () => {
      renderComponent();
      const hybridRadio = screen.getByDisplayValue('hybrid');
      fireEvent.click(hybridRadio);
      expect(screen.getByText('Denied Licenses')).toBeInTheDocument();
    });

    it('hides denied licenses for allowlist policy', () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);
      expect(screen.queryByText('Denied Licenses')).not.toBeInTheDocument();
    });

    it('allows adding a denied license', () => {
      renderComponent();
      const input = screen.getByPlaceholderText(/Enter SPDX license identifier \(e.g., GPL-3.0-only\)/) as HTMLInputElement;
      fireEvent.change(input, { target: { value: 'GPL-3.0' } });

      const addButton = input.nextElementSibling as HTMLElement;
      fireEvent.click(addButton);

      expect(screen.getByText('GPL-3.0')).toBeInTheDocument();
    });

    it('shows quick add buttons for copyleft licenses', () => {
      renderComponent();
      expect(screen.getByText('Quick add copyleft licenses:')).toBeInTheDocument();
    });
  });

  describe('form validation', () => {
    it('shows error when name is empty', async () => {
      renderComponent();
      const submitButton = screen.getByText('Create Policy');

      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Policy name is required')).toBeInTheDocument();
      });
    });

    it('shows error when allowlist has no allowed licenses', async () => {
      renderComponent();
      const allowlistRadio = screen.getByDisplayValue('allowlist');
      fireEvent.click(allowlistRadio);

      const nameInput = screen.getByPlaceholderText('e.g., Production Strict Policy');
      fireEvent.change(nameInput, { target: { value: 'Test Policy' } });

      const submitButton = screen.getByText('Create Policy');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Allowlist policy requires at least one allowed license')).toBeInTheDocument();
      });
    });

    it('does not show validation errors when form is valid', async () => {
      renderComponent();
      const nameInput = screen.getByPlaceholderText('e.g., Production Strict Policy');
      fireEvent.change(nameInput, { target: { value: 'Test Policy' } });

      const submitButton = screen.getByText('Create Policy');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.queryByText('Policy name is required')).not.toBeInTheDocument();
      });
    });
  });

  describe('form submission - create', () => {
    it('calls create mutation with correct data', async () => {
      mockCreateMutation.mutateAsync.mockResolvedValue({});
      renderComponent();

      const nameInput = screen.getByPlaceholderText('e.g., Production Strict Policy');
      fireEvent.change(nameInput, { target: { value: 'New Policy' } });

      const descInput = screen.getByPlaceholderText('Describe the purpose and scope of this policy...');
      fireEvent.change(descInput, { target: { value: 'Test description' } });

      const submitButton = screen.getByText('Create Policy');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockCreateMutation.mutateAsync).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'New Policy',
            description: 'Test description',
            policy_type: 'denylist',
            enforcement_level: 'warn',
            is_active: true,
          })
        );
      });
    });

    it('navigates to list after successful create', async () => {
      mockCreateMutation.mutateAsync.mockResolvedValue({});
      renderComponent();

      const nameInput = screen.getByPlaceholderText('e.g., Production Strict Policy');
      fireEvent.change(nameInput, { target: { value: 'New Policy' } });

      const submitButton = screen.getByText('Create Policy');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies');
      });
    });

    it('disables submit button while submitting', () => {
      mockUseCreateLicensePolicy.mockReturnValue({
        ...mockCreateMutation,
        isLoading: true,
      });
      renderComponent();

      const submitButton = screen.getByText('Create Policy');
      expect(submitButton).toBeDisabled();
    });
  });

  describe('form submission - update', () => {
    beforeEach(() => {
      mockParams.id = 'policy-123';
      mockUseLicensePolicy.mockReturnValue({
        data: mockExistingPolicy,
        isLoading: false,
        error: null,
        refetch: jest.fn(),
      });
    });

    it('calls update mutation with correct data', async () => {
      mockUpdateMutation.mutateAsync.mockResolvedValue({});
      renderComponent();

      const nameInput = screen.getByPlaceholderText('e.g., Production Strict Policy') as HTMLInputElement;
      fireEvent.change(nameInput, { target: { value: 'Updated Policy' } });

      const submitButton = screen.getByText('Update Policy');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockUpdateMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'policy-123',
          data: expect.objectContaining({
            name: 'Updated Policy',
          }),
        });
      });
    });

    it('navigates to list after successful update', async () => {
      mockUpdateMutation.mutateAsync.mockResolvedValue({});
      renderComponent();

      const submitButton = screen.getByText('Update Policy');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies');
      });
    });
  });

  describe('cancel action', () => {
    it('renders Cancel button', () => {
      renderComponent();
      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('navigates to list page when Cancel clicked', () => {
      renderComponent();
      const cancelButton = screen.getByText('Cancel');

      fireEvent.click(cancelButton);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies');
    });

    it('disables Cancel button while submitting', () => {
      mockUseCreateLicensePolicy.mockReturnValue({
        ...mockCreateMutation,
        isLoading: true,
      });
      renderComponent();

      const cancelButton = screen.getByText('Cancel');
      expect(cancelButton).toBeDisabled();
    });
  });

  describe('info box', () => {
    it('renders information about license policies', () => {
      renderComponent();
      expect(screen.getByText('About License Policies')).toBeInTheDocument();
      expect(screen.getByText(/License policies are evaluated against SBOMs/)).toBeInTheDocument();
    });
  });
});
