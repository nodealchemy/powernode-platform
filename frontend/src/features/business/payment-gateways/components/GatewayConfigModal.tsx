import React, { useState, useEffect, useMemo } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useForm, FormValidationRules, UseFormReturn } from '@/shared/hooks/useForm';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { paymentGatewaysApi, PaymentGatewayConfig } from '../services/paymentGatewaysApi';
import { Settings, Save } from 'lucide-react';

interface GatewayConfigModalProps {
  isOpen: boolean;
  onClose: () => void;
  gateway: 'stripe' | 'paypal';
  currentConfig?: PaymentGatewayConfig;
  onConfigured: () => void;
}

interface StripeFormValues {
  publishable_key: string;
  secret_key: string;
  endpoint_secret: string;
  webhook_tolerance: number;
  enabled: boolean;
  test_mode: boolean;
}

interface PayPalFormValues {
  client_id: string;
  client_secret: string;
  webhook_id: string;
  mode: 'sandbox' | 'live';
  enabled: boolean;
  test_mode: boolean;
}

// Error types for form validation
type StripeFormErrors = Record<keyof StripeFormValues, string | undefined>;
type PayPalFormErrors = Record<keyof PayPalFormValues, string | undefined>;

// Union type for gateway-agnostic form handling
type GatewayFormValues = StripeFormValues | PayPalFormValues;

export const GatewayConfigModal: React.FC<GatewayConfigModalProps> = ({
  isOpen,
  onClose,
  gateway,
  currentConfig,
  onConfigured
}) => {
  const { showNotification } = useNotifications();
  const [showSecrets, setShowSecrets] = useState(false);

  // Memoize default values to prevent unnecessary re-renders
  const defaultValues = useMemo((): GatewayFormValues => {
    if (gateway === 'stripe') {
      return {
        publishable_key: '',  // Don't pre-fill sensitive keys for security
        secret_key: '',
        endpoint_secret: '',
        webhook_tolerance: 300,
        enabled: currentConfig?.enabled ?? false,
        test_mode: currentConfig?.test_mode ?? true
      } satisfies StripeFormValues;
    } else {
      return {
        client_id: '',  // Don't pre-fill sensitive keys for security
        client_secret: '',
        webhook_id: '',
        mode: currentConfig?.mode ?? 'sandbox',
        enabled: currentConfig?.enabled ?? false,
        test_mode: currentConfig?.test_mode ?? true
      } satisfies PayPalFormValues;
    }
  }, [gateway, currentConfig]);

  // Memoize validation rules to prevent unnecessary re-creation
  const validationRules = useMemo((): FormValidationRules => {
    if (gateway === 'stripe') {
      return {
        publishable_key: {
          required: false, // Optional - only validate format if provided
          custom: (value: unknown) => {
            const keyValue = value as string;
            if (!keyValue || keyValue.trim() === '') return null; // Allow empty values
            if (!/^pk_(test_|live_)[a-zA-Z0-9_]{20,}$/.test(keyValue)) {
              return 'Publishable key must start with pk_test_ or pk_live_ followed by at least 20 characters';
            }
            return null;
          }
        },
        secret_key: {
          required: false, // Optional - only validate format if provided
          custom: (value: unknown) => {
            const keyValue = value as string;
            if (!keyValue || keyValue.trim() === '') return null; // Allow empty values
            if (!/^sk_(test_|live_)[a-zA-Z0-9_]{20,}$/.test(keyValue)) {
              return 'Secret key must start with sk_test_ or sk_live_ followed by at least 20 characters';
            }
            return null;
          }
        },
        endpoint_secret: {
          custom: (value: unknown) => {
            const secretValue = value as string;
            if (secretValue && !/^whsec_[a-zA-Z0-9]+$/.test(secretValue)) {
              return 'Webhook endpoint secret must start with whsec_ if provided';
            }
            return null;
          }
        },
        webhook_tolerance: {
          custom: (value: unknown) => {
            const numValue = value as number;
            if (numValue < 1 || numValue > 3600) {
              return 'Webhook tolerance must be between 1 and 3600 seconds';
            }
            return null;
          }
        }
      };
    } else {
      return {
        client_id: {
          required: false, // Optional - only validate format if provided
          minLength: 10
        },
        client_secret: {
          required: false, // Optional - only validate format if provided
          minLength: 10
        },
        mode: {
          custom: (value: unknown) => {
            const modeValue = value as string;
            if (modeValue && !['sandbox', 'live'].includes(modeValue)) {
              return 'Mode must be either sandbox or live';
            }
            return null;
          }
        }
      };
    }
  }, [gateway]);

  // Handle form submission
  const handleConfigSubmit = async (formData: GatewayFormValues) => {
    try {
      // Only send non-empty values
      const configToSend: Record<string, unknown> = {};
      
      // Define allowed configuration keys for security
      const allowedKeys = gateway === 'stripe' 
        ? ['publishable_key', 'secret_key', 'endpoint_secret', 'webhook_tolerance', 'enabled', 'test_mode']
        : ['client_id', 'client_secret', 'webhook_id', 'mode', 'enabled', 'test_mode'];
      
      Object.entries(formData).forEach(([key, value]) => {
        if (allowedKeys.includes(key) && value !== '' && value !== null && value !== undefined) {
          // For string values, also check if they're not just whitespace
          if (typeof value === 'string' && value.trim() === '') {
            return; // Skip empty strings
          }
          configToSend[key as keyof typeof configToSend] = value;
        }
      });

      await paymentGatewaysApi.updateGatewayConfiguration(gateway, configToSend);
      
      showNotification(`${gateway.charAt(0).toUpperCase() + gateway.slice(1)} configuration updated successfully`, 'success');
      onConfigured();
      onClose();
    } catch {
      let errorMessage = `Failed to update ${gateway} configuration`;
      
      const httpError = error as { response?: { data?: { error?: string }; status?: number } };
      if (httpError?.response?.data?.error) {
        const backendError = httpError.response.data.error;
        if (typeof backendError === 'string') {
          errorMessage = backendError.split(', ').join('\n• ');
          if (backendError.includes(',')) {
            errorMessage = `Please fix the following issues:\n• ${errorMessage}`;
          }
        } else {
          errorMessage = backendError;
        }
      } else if (httpError?.response?.status === 401) {
        errorMessage = 'Authentication required. Please refresh the page and try again.';
      } else if (httpError?.response?.status === 403) {
        errorMessage = 'You do not have permission to update payment gateway settings.';
      } else if (httpError?.response?.status === 422) {
        errorMessage = 'Invalid configuration data. Please check your input and try again.';
      } else if ((error as Error)?.message) {
        errorMessage = (error as Error).message;
      }
      
      throw new Error(errorMessage);
    }
  };

  // Create typed form - use generic type assertion for the specific gateway
  const form = useForm<GatewayFormValues>({
    initialValues: defaultValues,
    validationRules: validationRules,
    onSubmit: handleConfigSubmit,
    enableRealTimeValidation: false, // Disable real-time validation to prevent premature errors
    showSuccessNotification: false, // We handle success notification manually
    resetAfterSubmit: true,
  });

  // Type-safe accessors for gateway-specific forms
  const stripeForm = form as UseFormReturn<StripeFormValues>;
  const paypalForm = form as UseFormReturn<PayPalFormValues>;

  // Get typed errors based on gateway
  const stripeErrors = form.errors as StripeFormErrors;
  const paypalErrors = form.errors as PayPalFormErrors;

  // Reset form when modal opens or closes
  useEffect(() => {
    if (isOpen) {
      form.reset();
    }
  }, [isOpen]); // Remove 'form' from dependencies to prevent constant resets

  // Update form when config changes
  useEffect(() => {
    if (currentConfig && isOpen) {
      // Update the checkbox states based on current config
      // Note: Don't set text field values to avoid triggering validation on empty fields
      if (gateway === 'stripe') {
        stripeForm.setValue('enabled', currentConfig.enabled ?? false);
        stripeForm.setValue('test_mode', currentConfig.test_mode ?? true);
        if (currentConfig.webhook_tolerance && currentConfig.webhook_tolerance !== 300) {
          stripeForm.setValue('webhook_tolerance', currentConfig.webhook_tolerance);
        }
      } else {
        paypalForm.setValue('enabled', currentConfig.enabled ?? false);
        paypalForm.setValue('test_mode', currentConfig.test_mode ?? true);
        if (currentConfig.mode) {
          paypalForm.setValue('mode', currentConfig.mode);
        }
      }
    }
  }, [currentConfig, isOpen, gateway]); // Remove form.setValue to prevent infinite loop

  const handleCancel = () => {
    form.reset();
    onClose();
  };

  const renderStripeForm = () => {
    const stripeValues = stripeForm.values;

    return (
      <div className="space-y-6">
        <div className="grid grid-cols-1 gap-6">
          <div>
            <label className="label-theme flex items-center gap-2">
              Publishable Key
              {currentConfig?.publishable_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!currentConfig?.publishable_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <input
              {...stripeForm.getFieldProps('publishable_key')}
              type="text"
              className={`input-theme ${stripeErrors.publishable_key ? 'border-theme-error' : ''}`}
              placeholder={
                currentConfig?.publishable_key_present
                  ? "Leave blank to keep current key, or enter new key to update"
                  : "pk_test_51ABC...xyz123 (starts with pk_test_ or pk_live_)"
              }
              disabled={form.isSubmitting}
            />
            {stripeErrors.publishable_key && (
              <p className="text-theme-error text-sm mt-1">{stripeErrors.publishable_key}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {currentConfig?.publishable_key_present
                ? "A publishable key is already configured. Leave blank to keep current key, or enter a new key to update it."
                : "Your Stripe publishable key (starts with pk_). Leave blank if not updating."}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Secret Key
              {currentConfig?.secret_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!currentConfig?.secret_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <div className="relative">
              <input
                {...stripeForm.getFieldProps('secret_key')}
                type={showSecrets ? "text" : "password"}
                className={`input-theme pr-10 ${stripeErrors.secret_key ? 'border-theme-error' : ''}`}
                placeholder={
                  currentConfig?.secret_key_present
                    ? "Leave blank to keep current key, or enter new key to update"
                    : "sk_test_51ABC...xyz123 (starts with sk_test_ or sk_live_)"
                }
                disabled={form.isSubmitting}
              />
              <button
                type="button"
                onClick={() => setShowSecrets(!showSecrets)}
                className="absolute right-2 top-2 text-theme-secondary hover:text-theme-primary"
              >
                {showSecrets ? '🙈' : '👁️'}
              </button>
            </div>
            {stripeErrors.secret_key && (
              <p className="text-theme-error text-sm mt-1">{stripeErrors.secret_key}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {currentConfig?.secret_key_present
                ? "A secret key is already configured. Leave blank to keep current key, or enter a new key to update it."
                : "Your Stripe secret key (starts with sk_). Leave blank if not updating."}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Webhook Endpoint Secret
              {currentConfig?.endpoint_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!currentConfig?.endpoint_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-info-subtle text-theme-info-emphasis rounded">
                  Optional
                </span>
              )}
            </label>
            <input
              {...stripeForm.getFieldProps('endpoint_secret')}
              type={showSecrets ? "text" : "password"}
              className={`input-theme ${stripeErrors.endpoint_secret ? 'border-theme-error' : ''}`}
              placeholder={
                currentConfig?.endpoint_secret_present
                  ? "Enter new webhook secret to update"
                  : "whsec_1234567890abcdef (starts with whsec_)"
              }
              disabled={form.isSubmitting}
            />
            {stripeErrors.endpoint_secret && (
              <p className="text-theme-error text-sm mt-1">{stripeErrors.endpoint_secret}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {currentConfig?.endpoint_secret_present
                ? "A webhook secret is already configured. Enter a new secret to update it."
                : "Webhook endpoint secret from your Stripe dashboard (optional)"}
            </p>
          </div>

          <div>
            <label className="label-theme">
              Webhook Tolerance (seconds)
            </label>
            <input
              {...stripeForm.getFieldProps('webhook_tolerance')}
              type="number"
              min="1"
              max="3600"
              className={`input-theme ${stripeErrors.webhook_tolerance ? 'border-theme-error' : ''}`}
              disabled={form.isSubmitting}
            />
            {stripeErrors.webhook_tolerance && (
              <p className="text-theme-error text-sm mt-1">{stripeErrors.webhook_tolerance}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              Webhook timestamp tolerance (default: 300 seconds)
            </p>
          </div>
        </div>

        <div className="flex items-center justify-between py-4 border-t border-theme">
          <div className="flex items-center space-x-4">
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={stripeValues.enabled}
                onChange={(e) => stripeForm.setValue('enabled', e.target.checked)}
                className="rounded border-theme text-theme-link focus:ring-theme-link"
                disabled={form.isSubmitting}
              />
              <span className="ml-2 text-sm text-theme-primary">Enable Stripe payments</span>
            </label>

            <label className="flex items-center">
              <input
                type="checkbox"
                checked={stripeValues.test_mode}
                onChange={(e) => stripeForm.setValue('test_mode', e.target.checked)}
                className="rounded border-theme text-theme-link focus:ring-theme-link"
                disabled={form.isSubmitting}
              />
              <span className="ml-2 text-theme-primary">Test mode</span>
            </label>
          </div>
        </div>
      </div>
    );
  };

  const renderPayPalForm = () => {
    const paypalValues = paypalForm.values;

    return (
      <div className="space-y-6">
        <div className="grid grid-cols-1 gap-6">
          <div>
            <label className="label-theme flex items-center gap-2">
              Client ID
              {currentConfig?.client_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!currentConfig?.client_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <input
              {...paypalForm.getFieldProps('client_id')}
              type="text"
              className={`input-theme ${paypalErrors.client_id ? 'border-theme-error' : ''}`}
              placeholder={
                currentConfig?.client_id_present
                  ? "Leave blank to keep current ID, or enter new ID to update"
                  : "Your PayPal client ID"
              }
              disabled={form.isSubmitting}
            />
            {paypalErrors.client_id && (
              <p className="text-theme-error text-sm mt-1">{paypalErrors.client_id}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {currentConfig?.client_id_present
                ? "A client ID is already configured. Leave blank to keep current ID, or enter a new ID to update it."
                : "Your PayPal application client ID. Leave blank if not updating."}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Client Secret
              {currentConfig?.client_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!currentConfig?.client_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <div className="relative">
              <input
                {...paypalForm.getFieldProps('client_secret')}
                type={showSecrets ? "text" : "password"}
                className={`input-theme pr-10 ${paypalErrors.client_secret ? 'border-theme-error' : ''}`}
                placeholder={
                  currentConfig?.client_secret_present
                    ? "Leave blank to keep current secret, or enter new secret to update"
                    : "Your PayPal client secret"
                }
                disabled={form.isSubmitting}
              />
              <button
                type="button"
                onClick={() => setShowSecrets(!showSecrets)}
                className="absolute right-2 top-2 text-theme-secondary hover:text-theme-primary"
              >
                {showSecrets ? '🙈' : '👁️'}
              </button>
            </div>
            {paypalErrors.client_secret && (
              <p className="text-theme-error text-sm mt-1">{paypalErrors.client_secret}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {currentConfig?.client_secret_present
                ? "A client secret is already configured. Leave blank to keep current secret, or enter a new secret to update it."
                : "Your PayPal application client secret. Leave blank if not updating."}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Webhook ID
              {currentConfig?.webhook_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!currentConfig?.webhook_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-info-subtle text-theme-info-emphasis rounded">
                  Optional
                </span>
              )}
            </label>
            <input
              {...paypalForm.getFieldProps('webhook_id')}
              type="text"
              className={`input-theme ${paypalErrors.webhook_id ? 'border-theme-error' : ''}`}
              placeholder={
                currentConfig?.webhook_id_present
                  ? "Enter new webhook ID to update"
                  : "Your PayPal webhook ID"
              }
              disabled={form.isSubmitting}
            />
            {paypalErrors.webhook_id && (
              <p className="text-theme-error text-sm mt-1">{paypalErrors.webhook_id}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {currentConfig?.webhook_id_present
                ? "A webhook ID is already configured. Enter a new ID to update it."
                : "PayPal webhook ID for event notifications (optional)"}
            </p>
          </div>

          <div>
            <label className="label-theme">
              Environment Mode
            </label>
            <select
              value={paypalValues.mode}
              onChange={(e) => paypalForm.setValue('mode', e.target.value as 'sandbox' | 'live')}
              className={`select-theme ${paypalErrors.mode ? 'border-theme-error' : ''}`}
              disabled={form.isSubmitting}
            >
              <option value="sandbox">Sandbox (Testing)</option>
              <option value="live">Live (Production)</option>
            </select>
            {paypalErrors.mode && (
              <p className="text-theme-error text-sm mt-1">{paypalErrors.mode}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              Choose sandbox for testing or live for production
            </p>
          </div>
        </div>

        <div className="flex items-center justify-between py-4 border-t border-theme">
          <div className="flex items-center space-x-4">
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={paypalValues.enabled}
                onChange={(e) => paypalForm.setValue('enabled', e.target.checked)}
                className="rounded border-theme text-theme-link focus:ring-theme-link"
                disabled={form.isSubmitting}
              />
              <span className="ml-2 text-sm text-theme-primary">Enable PayPal payments</span>
            </label>

            <label className="flex items-center">
              <input
                type="checkbox"
                checked={paypalValues.test_mode}
                onChange={(e) => paypalForm.setValue('test_mode', e.target.checked)}
                className="rounded border-theme text-theme-link focus:ring-theme-link"
                disabled={form.isSubmitting}
              />
              <span className="ml-2 text-sm text-theme-primary">Test mode</span>
            </label>
          </div>
        </div>
      </div>
    );
  };

  const gatewayInfo = {
    stripe: { name: 'Stripe', logo: '💳', description: 'Configure Stripe payment processing' },
    paypal: { name: 'PayPal', logo: '🅿️', description: 'Configure PayPal payment processing' }
  } as const;

   
  const info = gatewayInfo[gateway];

  const modalFooter = (
    <div className="flex justify-end space-x-3">
      <Button
        variant="secondary"
        onClick={handleCancel}
        disabled={form.isSubmitting}
      >
        Cancel
      </Button>
      <Button
        variant="primary"
        type="submit"
        form="gateway-config-form"
        loading={form.isSubmitting}
      >
        {!form.isSubmitting && <Save className="w-4 h-4 mr-2" />}
        {form.isSubmitting ? 'Saving...' : 'Save Configuration'}
      </Button>
    </div>
  );

  return (
    <Modal 
      isOpen={isOpen} 
      onClose={handleCancel} 
      title={`Configure ${info.name}`} 
      subtitle={info.description}
      icon={<Settings />}
      maxWidth="lg"
      footer={modalFooter}
      closeOnBackdrop={!form.isSubmitting}
      closeOnEscape={!form.isSubmitting}
    >
      <div className="flex items-center space-x-4 mb-6">
        <div className={`w-12 h-12 rounded-lg flex items-center justify-center text-white text-xl font-bold ${gateway === 'stripe' ? 'bg-theme-interactive-secondary' : 'bg-theme-info'}`}>
          {info.logo}
        </div>
      </div>

      <form id="gateway-config-form" onSubmit={form.handleSubmit}>
        {gateway === 'stripe' ? renderStripeForm() : renderPayPalForm()}
      </form>
    </Modal>
  );
};

