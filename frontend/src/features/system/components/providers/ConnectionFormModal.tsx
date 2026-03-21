import React, { useState, useEffect } from 'react';
import { X, Server, AlertCircle, CheckCircle, XCircle, RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderConnection } from '@/features/system/types/system.types';

interface ConnectionFormModalProps {
  /** Provider ID for this connection */
  providerId: string;
  /** Connection to edit (null for create mode) */
  connection: SystemProviderConnection | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when connection is saved */
  onConnectionSaved?: () => void;
}

interface FormData {
  name: string;
  description: string;
  endpoint_url: string;
  access_key: string;
  secret_key: string;
  tenant: string;
}

interface FormErrors {
  name?: string;
  access_key?: string;
  secret_key?: string;
}

type TestStatus = 'idle' | 'testing' | 'success' | 'error';

/**
 * ConnectionFormModal - Modal for creating/editing provider connections with test functionality
 */
export const ConnectionFormModal: React.FC<ConnectionFormModalProps> = ({
  providerId,
  connection,
  isOpen,
  onClose,
  onConnectionSaved
}) => {
  const { addNotification } = useNotifications();
  const isEditMode = !!connection;

  // State
  const [submitting, setSubmitting] = useState(false);
  const [testStatus, setTestStatus] = useState<TestStatus>('idle');
  const [testMessage, setTestMessage] = useState('');
  const [formData, setFormData] = useState<FormData>({
    name: '',
    description: '',
    endpoint_url: '',
    access_key: '',
    secret_key: '',
    tenant: ''
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Initialize form
  useEffect(() => {
    if (isOpen) {
      if (connection) {
        setFormData({
          name: connection.name,
          description: connection.description || '',
          endpoint_url: connection.endpoint_url || '',
          access_key: '', // Don't pre-fill credentials for security
          secret_key: '',
          tenant: ''
        });
      } else {
        setFormData({
          name: '',
          description: '',
          endpoint_url: '',
          access_key: '',
          secret_key: '',
          tenant: ''
        });
      }
      setErrors({});
      setTestStatus('idle');
      setTestMessage('');
    }
  }, [isOpen, connection]);

  // Validate form
  const validate = (): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    }

    // For create mode, credentials are required
    // For edit mode, they're optional (keep existing if not provided)
    if (!isEditMode) {
      if (!formData.access_key.trim()) {
        newErrors.access_key = 'Access key is required';
      }
      if (!formData.secret_key.trim()) {
        newErrors.secret_key = 'Secret key is required';
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handle field change
  const handleChange = (field: keyof FormData, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (errors[field as keyof FormErrors]) {
      setErrors(prev => ({ ...prev, [field]: undefined }));
    }
    // Reset test status when form changes
    if (testStatus !== 'idle') {
      setTestStatus('idle');
      setTestMessage('');
    }
  };

  // Test connection
  const handleTest = async () => {
    if (!formData.access_key || !formData.secret_key) {
      addNotification({
        type: 'warning',
        message: 'Please enter credentials to test the connection'
      });
      return;
    }

    setTestStatus('testing');
    setTestMessage('');

    try {
      // For existing connections, use the API test endpoint
      // For new connections, we'd need a test-before-save endpoint
      if (isEditMode && connection) {
        const result = await systemApi.testProviderConnection(connection.id);
        if (result.success) {
          setTestStatus('success');
          setTestMessage(result.message || 'Connection successful');
        } else {
          setTestStatus('error');
          setTestMessage(result.message || 'Connection failed');
        }
      } else {
        // For new connections, we simulate a test (actual implementation would need backend support)
        addNotification({
          type: 'info',
          message: 'Save the connection first, then test it from the connections list'
        });
        setTestStatus('idle');
      }
    } catch (error) {
      setTestStatus('error');
      setTestMessage(error instanceof Error ? error.message : 'Connection test failed');
    }
  };

  // Handle submit
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate()) {
      return;
    }

    setSubmitting(true);

    try {
      const payload: Record<string, unknown> = {
        name: formData.name.trim(),
        description: formData.description.trim() || undefined,
        endpoint_url: formData.endpoint_url.trim() || undefined,
        provider_id: providerId,
        config: {}
      };

      // Only include credentials if provided
      if (formData.access_key.trim()) {
        payload.access_key = formData.access_key.trim();
      }
      if (formData.secret_key.trim()) {
        payload.secret_key = formData.secret_key.trim();
      }
      if (formData.tenant.trim()) {
        payload.tenant = formData.tenant.trim();
      }

      if (isEditMode && connection) {
        await systemApi.updateProviderConnection(connection.id, payload);
        addNotification({
          type: 'success',
          message: `Connection "${payload.name}" updated successfully`
        });
      } else {
        await systemApi.createProviderConnection(payload as Parameters<typeof systemApi.createProviderConnection>[0]);
        addNotification({
          type: 'success',
          message: `Connection "${payload.name}" created successfully`
        });
      }

      onConnectionSaved?.();
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update connection: ${errorMessage}`
          : `Failed to create connection: ${errorMessage}`
      });
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[60] overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-lg bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Server className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Connection' : 'Add Connection'}
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit}>
            <div className="p-4 space-y-4 max-h-[60vh] overflow-y-auto">
              {/* Name */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Name <span className="text-theme-error">*</span>
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => handleChange('name', e.target.value)}
                  placeholder="Enter connection name"
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                    errors.name ? 'border-theme-error' : 'border-theme'
                  }`}
                  disabled={submitting}
                />
                {errors.name && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.name}
                  </p>
                )}
              </div>

              {/* Description */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Description
                </label>
                <textarea
                  value={formData.description}
                  onChange={(e) => handleChange('description', e.target.value)}
                  placeholder="Optional description"
                  rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                  disabled={submitting}
                />
              </div>

              {/* Endpoint URL */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Endpoint URL
                </label>
                <input
                  type="url"
                  value={formData.endpoint_url}
                  onChange={(e) => handleChange('endpoint_url', e.target.value)}
                  placeholder="https://api.provider.com"
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary font-mono placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                  disabled={submitting}
                />
              </div>

              {/* Credentials Section */}
              <div className="pt-4 border-t border-theme">
                <h4 className="text-sm font-medium text-theme-primary mb-3">Credentials</h4>

                {/* Access Key */}
                <div className="mb-4">
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Access Key {!isEditMode && <span className="text-theme-error">*</span>}
                  </label>
                  <input
                    type="text"
                    value={formData.access_key}
                    onChange={(e) => handleChange('access_key', e.target.value)}
                    placeholder={isEditMode ? "Leave empty to keep existing" : "Enter access key"}
                    className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary font-mono placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                      errors.access_key ? 'border-theme-error' : 'border-theme'
                    }`}
                    disabled={submitting}
                  />
                  {errors.access_key && (
                    <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                      <AlertCircle className="w-4 h-4" />
                      {errors.access_key}
                    </p>
                  )}
                </div>

                {/* Secret Key */}
                <div className="mb-4">
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Secret Key {!isEditMode && <span className="text-theme-error">*</span>}
                  </label>
                  <input
                    type="password"
                    value={formData.secret_key}
                    onChange={(e) => handleChange('secret_key', e.target.value)}
                    placeholder={isEditMode ? "Leave empty to keep existing" : "Enter secret key"}
                    className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary font-mono placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                      errors.secret_key ? 'border-theme-error' : 'border-theme'
                    }`}
                    disabled={submitting}
                  />
                  {errors.secret_key && (
                    <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                      <AlertCircle className="w-4 h-4" />
                      {errors.secret_key}
                    </p>
                  )}
                </div>

                {/* Tenant (optional) */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Tenant / Project ID
                  </label>
                  <input
                    type="text"
                    value={formData.tenant}
                    onChange={(e) => handleChange('tenant', e.target.value)}
                    placeholder="Optional tenant or project ID"
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary font-mono placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                    disabled={submitting}
                  />
                </div>
              </div>

              {/* Test Connection */}
              {isEditMode && (
                <div className="pt-4 border-t border-theme">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-theme-primary">Test Connection</span>
                      {testStatus === 'success' && (
                        <Badge variant="success" size="sm">
                          <CheckCircle className="w-3 h-3 mr-1" />
                          Success
                        </Badge>
                      )}
                      {testStatus === 'error' && (
                        <Badge variant="danger" size="sm">
                          <XCircle className="w-3 h-3 mr-1" />
                          Failed
                        </Badge>
                      )}
                    </div>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={handleTest}
                      disabled={testStatus === 'testing' || submitting}
                    >
                      {testStatus === 'testing' ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Testing...
                        </>
                      ) : (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2" />
                          Test
                        </>
                      )}
                    </Button>
                  </div>
                  {testMessage && (
                    <p className={`mt-2 text-sm ${testStatus === 'success' ? 'text-theme-success' : 'text-theme-error'}`}>
                      {testMessage}
                    </p>
                  )}
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="flex justify-end gap-3 p-4 border-t border-theme">
              <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
                Cancel
              </Button>
              <Button type="submit" variant="primary" disabled={submitting}>
                {submitting ? (
                  <>
                    <LoadingSpinner size="sm" className="mr-2" />
                    {isEditMode ? 'Updating...' : 'Creating...'}
                  </>
                ) : (
                  isEditMode ? 'Update Connection' : 'Add Connection'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default ConnectionFormModal;
