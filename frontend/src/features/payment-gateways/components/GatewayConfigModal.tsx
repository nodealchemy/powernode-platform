import React, { useState, useEffect, useMemo } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { useNotification } from '@/shared/hooks/useNotification';
import { paymentGatewaysApi, PaymentGatewayConfig } from '../services/paymentGatewaysApi';
import { Settings, Save } from 'lucide-react';

interface GatewayConfigModalProps {
  isOpen: boolean;
  onClose: () => void;
  gateway: 'stripe' | 'paypal';
  currentConfig?: PaymentGatewayConfig;
  onConfigured: () => void;
}

interface StripeConfig {
  publishable_key: string;
  secret_key: string;
  endpoint_secret: string;
  webhook_tolerance: number;
  enabled: boolean;
  test_mode: boolean;
}

interface PayPalConfig {
  client_id: string;
  client_secret: string;
  webhook_id: string;
  mode: 'sandbox' | 'live';
  enabled: boolean;
  test_mode: boolean;
}

type GatewayConfig = StripeConfig | PayPalConfig;

export const GatewayConfigModal: React.FC<GatewayConfigModalProps> = ({
  isOpen,
  onClose,
  gateway,
  currentConfig,
  onConfigured
}) => {
  const { showNotification } = useNotification();
  const [showSecrets, setShowSecrets] = useState(false);

  // Memoize default values to prevent unnecessary re-renders
  const defaultValues = useMemo((): GatewayConfig => {
    if (gateway === 'stripe') {
      return {
        publishable_key: '',  // Don't pre-fill sensitive keys for security
        secret_key: '',
        endpoint_secret: '',
        webhook_tolerance: 300,
        enabled: currentConfig?.enabled ?? false,
        test_mode: currentConfig?.test_mode ?? true
      } as StripeConfig;
    } else {
      return {
        client_id: '',  // Don't pre-fill sensitive keys for security
        client_secret: '',
        webhook_id: '',
        mode: (currentConfig as any)?.mode || 'sandbox',
        enabled: currentConfig?.enabled ?? false,
        test_mode: currentConfig?.test_mode ?? true
      } as PayPalConfig;
    }
  }, [gateway, currentConfig]);

  // Memoize validation rules to prevent unnecessary re-creation
  const validationRules = useMemo((): FormValidationRules => {
    if (gateway === 'stripe') {
      return {
        publishable_key: {
          required: true,
          custom: (value: string) => {
            if (!value) return null; // Required validation is handled separately
            if (!/^pk_(test_|live_)[a-zA-Z0-9_]{20,}$/.test(value)) {
              return 'Publishable key must start with pk_test_ or pk_live_ followed by at least 20 characters';
            }
            return null;
          }
        },
        secret_key: {
          required: true,
          custom: (value: string) => {
            if (!value) return null; // Required validation is handled separately
            if (!/^sk_(test_|live_)[a-zA-Z0-9_]{20,}$/.test(value)) {
              return 'Secret key must start with sk_test_ or sk_live_ followed by at least 20 characters';
            }
            return null;
          }
        },
        endpoint_secret: {
          custom: (value: string) => {
            if (value && !/^whsec_[a-zA-Z0-9]+$/.test(value)) {
              return 'Webhook endpoint secret must start with whsec_ if provided';
            }
            return null;
          }
        },
        webhook_tolerance: {
          custom: (value: number) => {
            if (value < 1 || value > 3600) {
              return 'Webhook tolerance must be between 1 and 3600 seconds';
            }
            return null;
          }
        }
      };
    } else {
      return {
        client_id: {
          required: true,
          minLength: 10
        },
        client_secret: {
          required: true,
          minLength: 10
        },
        mode: {
          custom: (value: string) => {
            if (value && !['sandbox', 'live'].includes(value)) {
              return 'Mode must be either sandbox or live';
            }
            return null;
          }
        }
      };
    }
  }, [gateway]);

  // Handle form submission
  const handleConfigSubmit = async (formData: GatewayConfig) => {
    try {
      // Only send non-empty values
      const configToSend: Record<string, unknown> = {};
      
      // Define allowed configuration keys for security
      const allowedKeys = gateway === 'stripe' 
        ? ['publishable_key', 'secret_key', 'endpoint_secret', 'webhook_tolerance', 'enabled', 'test_mode']
        : ['client_id', 'client_secret', 'webhook_id', 'mode', 'enabled', 'test_mode'];
      
      Object.entries(formData).forEach(([key, value]) => {
        if (allowedKeys.includes(key) && value !== '' && value !== null && value !== undefined) {
          configToSend[key as keyof typeof configToSend] = value;
        }
      });

      await paymentGatewaysApi.updateGatewayConfiguration(gateway, configToSend);
      
      showNotification(`${gateway.charAt(0).toUpperCase() + gateway.slice(1)} configuration updated successfully`, 'success');
      onConfigured();
      onClose();
    } catch (error: any) {
      let errorMessage = `Failed to update ${gateway} configuration`;
      
      if (error?.response?.data?.error) {
        const backendError = error.response.data.error;
        if (typeof backendError === 'string') {
          errorMessage = backendError.split(', ').join('\n• ');
          if (backendError.includes(',')) {
            errorMessage = `Please fix the following issues:\n• ${errorMessage}`;
          }
        } else {
          errorMessage = backendError;
        }
      } else if (error?.response?.status === 401) {
        errorMessage = 'Authentication required. Please refresh the page and try again.';
      } else if (error?.response?.status === 403) {
        errorMessage = 'You do not have permission to update payment gateway settings.';
      } else if (error?.response?.status === 422) {
        errorMessage = 'Invalid configuration data. Please check your input and try again.';
      } else if (error?.message) {
        errorMessage = error.message;
      }
      
      throw new Error(errorMessage);
    }
  };

  const form = useForm({
    initialValues: defaultValues,
    validationRules: validationRules,
    onSubmit: handleConfigSubmit,
    enableRealTimeValidation: false, // Disable real-time validation to prevent premature errors
    showSuccessNotification: false, // We handle success notification manually
    resetAfterSubmit: true,
  }) as any; // Type assertion to handle union type complexity

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
      form.setValue('enabled', currentConfig.enabled ?? false);
      form.setValue('test_mode', currentConfig.test_mode ?? true);
      if (gateway === 'paypal' && (currentConfig as any).mode) {
        form.setValue('mode', (currentConfig as any).mode);
      }
      if (gateway === 'stripe' && (currentConfig as any).webhook_tolerance && (currentConfig as any).webhook_tolerance !== 300) {
        form.setValue('webhook_tolerance', (currentConfig as any).webhook_tolerance);
      }
    }
  }, [currentConfig, isOpen, gateway, form.setValue]);

  const handleCancel = () => {
    form.reset();
    onClose();
  };

  const renderStripeForm = () => {
    const stripeConfig = form.values as StripeConfig;
    
    return (
      <div className="space-y-6">
        <div className="grid grid-cols-1 gap-6">
          <div>
            <label className="label-theme flex items-center gap-2">
              Publishable Key *
              {(currentConfig as any)?.publishable_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!(currentConfig as any)?.publishable_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <input
              {...form.getFieldProps('publishable_key')}
              type="text"
              className={`input-theme ${(form.errors as any).publishable_key ? 'border-theme-error' : ''}`}
              placeholder={
                (currentConfig as any)?.publishable_key_present 
                  ? "Enter new publishable key to update" 
                  : "pk_test_51ABC...xyz123 (starts with pk_test_ or pk_live_)"
              }
              disabled={form.isSubmitting}
              required
            />
            {(form.errors as any).publishable_key && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).publishable_key}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {(currentConfig as any)?.publishable_key_present
                ? "A publishable key is already configured. Enter a new key to update it."
                : "Your Stripe publishable key (starts with pk_)"}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Secret Key *
              {(currentConfig as any)?.secret_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!(currentConfig as any)?.secret_key_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <div className="relative">
              <input
                {...form.getFieldProps('secret_key')}
                type={showSecrets ? "text" : "password"}
                className={`input-theme pr-10 ${(form.errors as any).secret_key ? 'border-theme-error' : ''}`}
                placeholder={
                  (currentConfig as any)?.secret_key_present
                    ? "Enter new secret key to update"
                    : "sk_test_51ABC...xyz123 (starts with sk_test_ or sk_live_)"
                }
                disabled={form.isSubmitting}
                required
              />
              <button
                type="button"
                onClick={() => setShowSecrets(!showSecrets)}
                className="absolute right-2 top-2 text-theme-secondary hover:text-theme-primary"
              >
                {showSecrets ? '🙈' : '👁️'}
              </button>
            </div>
            {(form.errors as any).secret_key && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).secret_key}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {(currentConfig as any)?.secret_key_present
                ? "A secret key is already configured. Enter a new key to update it."
                : "Your Stripe secret key (starts with sk_)"}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Webhook Endpoint Secret
              {(currentConfig as any)?.endpoint_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!(currentConfig as any)?.endpoint_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-info-subtle text-theme-info-emphasis rounded">
                  Optional
                </span>
              )}
            </label>
            <input
              {...form.getFieldProps('endpoint_secret')}
              type={showSecrets ? "text" : "password"}
              className={`input-theme ${(form.errors as any).endpoint_secret ? 'border-theme-error' : ''}`}
              placeholder={
                (currentConfig as any)?.endpoint_secret_present
                  ? "Enter new webhook secret to update"
                  : "whsec_1234567890abcdef (starts with whsec_)"
              }
              disabled={form.isSubmitting}
            />
            {(form.errors as any).endpoint_secret && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).endpoint_secret}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {(currentConfig as any)?.endpoint_secret_present
                ? "A webhook secret is already configured. Enter a new secret to update it."
                : "Webhook endpoint secret from your Stripe dashboard (optional)"}
            </p>
          </div>

          <div>
            <label className="label-theme">
              Webhook Tolerance (seconds)
            </label>
            <input
              {...form.getFieldProps('webhook_tolerance')}
              type="number"
              min="1"
              max="3600"
              className={`input-theme ${(form.errors as any).webhook_tolerance ? 'border-theme-error' : ''}`}
              disabled={form.isSubmitting}
            />
            {(form.errors as any).webhook_tolerance && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).webhook_tolerance}</p>
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
                checked={stripeConfig.enabled}
                onChange={(e) => (form.setValue as any)('enabled', e.target.checked)}
                className="rounded border-theme text-theme-link focus:ring-theme-link"
                disabled={form.isSubmitting}
              />
              <span className="ml-2 text-sm text-theme-primary">Enable Stripe payments</span>
            </label>
            
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={stripeConfig.test_mode}
                onChange={(e) => (form.setValue as any)('test_mode', e.target.checked)}
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
    const paypalConfig = form.values as PayPalConfig;
    
    return (
      <div className="space-y-6">
        <div className="grid grid-cols-1 gap-6">
          <div>
            <label className="label-theme flex items-center gap-2">
              Client ID *
              {(currentConfig as any)?.client_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!(currentConfig as any)?.client_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <input
              {...form.getFieldProps('client_id')}
              type="text"
              className={`input-theme ${(form.errors as any).client_id ? 'border-theme-error' : ''}`}
              placeholder={
                (currentConfig as any)?.client_id_present
                  ? "Enter new client ID to update"
                  : "Your PayPal client ID"
              }
              disabled={form.isSubmitting}
              required
            />
            {(form.errors as any).client_id && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).client_id}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {(currentConfig as any)?.client_id_present
                ? "A client ID is already configured. Enter a new ID to update it."
                : "Your PayPal application client ID"}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Client Secret *
              {(currentConfig as any)?.client_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!(currentConfig as any)?.client_secret_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-warning-subtle text-theme-warning-emphasis rounded">
                  Not Configured
                </span>
              )}
            </label>
            <div className="relative">
              <input
                {...form.getFieldProps('client_secret')}
                type={showSecrets ? "text" : "password"}
                className={`input-theme pr-10 ${(form.errors as any).client_secret ? 'border-theme-error' : ''}`}
                placeholder={
                  (currentConfig as any)?.client_secret_present
                    ? "Enter new client secret to update"
                    : "Your PayPal client secret"
                }
                disabled={form.isSubmitting}
                required
              />
              <button
                type="button"
                onClick={() => setShowSecrets(!showSecrets)}
                className="absolute right-2 top-2 text-theme-secondary hover:text-theme-primary"
              >
                {showSecrets ? '🙈' : '👁️'}
              </button>
            </div>
            {(form.errors as any).client_secret && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).client_secret}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {(currentConfig as any)?.client_secret_present
                ? "A client secret is already configured. Enter a new secret to update it."
                : "Your PayPal application client secret"}
            </p>
          </div>

          <div>
            <label className="label-theme flex items-center gap-2">
              Webhook ID
              {(currentConfig as any)?.webhook_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-success-subtle text-theme-success-emphasis rounded">
                  Configured
                </span>
              )}
              {!(currentConfig as any)?.webhook_id_present && (
                <span className="px-2 py-0.5 text-xs bg-theme-info-subtle text-theme-info-emphasis rounded">
                  Optional
                </span>
              )}
            </label>
            <input
              {...form.getFieldProps('webhook_id')}
              type="text"
              className={`input-theme ${(form.errors as any).webhook_id ? 'border-theme-error' : ''}`}
              placeholder={
                (currentConfig as any)?.webhook_id_present
                  ? "Enter new webhook ID to update"
                  : "Your PayPal webhook ID"
              }
              disabled={form.isSubmitting}
            />
            {(form.errors as any).webhook_id && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).webhook_id}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              {(currentConfig as any)?.webhook_id_present
                ? "A webhook ID is already configured. Enter a new ID to update it."
                : "PayPal webhook ID for event notifications (optional)"}
            </p>
          </div>

          <div>
            <label className="label-theme">
              Environment Mode
            </label>
            <select
              value={paypalConfig.mode}
              onChange={(e) => (form.setValue as any)('mode', e.target.value as 'sandbox' | 'live')}
              className={`select-theme ${(form.errors as any).mode ? 'border-theme-error' : ''}`}
              disabled={form.isSubmitting}
            >
              <option value="sandbox">Sandbox (Testing)</option>
              <option value="live">Live (Production)</option>
            </select>
            {(form.errors as any).mode && (
              <p className="text-theme-error text-sm mt-1">{(form.errors as any).mode}</p>
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
                checked={paypalConfig.enabled}
                onChange={(e) => (form.setValue as any)('enabled', e.target.checked)}
                className="rounded border-theme text-theme-link focus:ring-theme-link"
                disabled={form.isSubmitting}
              />
              <span className="ml-2 text-sm text-theme-primary">Enable PayPal payments</span>
            </label>
            
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={paypalConfig.test_mode}
                onChange={(e) => (form.setValue as any)('test_mode', e.target.checked)}
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

  // eslint-disable-next-line security/detect-object-injection
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
      title={`${info.name} Configuration`} 
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

export default GatewayConfigModal;