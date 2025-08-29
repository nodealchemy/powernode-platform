import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { AppEndpoint, AppEndpointFormData, HttpMethod } from '../../types';
import { X, Plus, Minus } from 'lucide-react';

interface EndpointFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: AppEndpointFormData) => Promise<AppEndpoint | null>;
  endpoint?: AppEndpoint | null;
  title: string;
}

const httpMethods: HttpMethod[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

const initialFormData: AppEndpointFormData = {
  name: '',
  description: '',
  http_method: 'GET',
  path: '',
  requires_auth: true,
  is_public: false,
  is_active: true,
  version: '1.0',
  headers: {},
  parameters: {},
  authentication: {},
  rate_limits: {
    requests_per_minute: 100,
    requests_per_hour: 1000
  },
  metadata: {}
};

export const EndpointFormModal: React.FC<EndpointFormModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
  endpoint,
  title
}) => {
  const [formData, setFormData] = useState<AppEndpointFormData>(initialFormData);
  const [submitting, setSubmitting] = useState(false);
  const [activeTab, setActiveTab] = useState<'basic' | 'config' | 'schema'>('basic');
  const [newHeader, setNewHeader] = useState({ key: '', value: '' });
  const [newParameter, setNewParameter] = useState({ key: '', value: '', type: 'string' });

  useEffect(() => {
    if (endpoint) {
      setFormData({
        name: endpoint.name,
        slug: endpoint.slug,
        description: endpoint.description || '',
        http_method: endpoint.http_method,
        path: endpoint.path,
        requires_auth: endpoint.requires_auth,
        is_public: endpoint.is_public,
        is_active: endpoint.is_active,
        version: endpoint.version,
        headers: endpoint.headers || {},
        parameters: endpoint.parameters || {},
        authentication: endpoint.authentication || {},
        rate_limits: endpoint.rate_limits || {
          requests_per_minute: 100,
          requests_per_hour: 1000
        },
        metadata: endpoint.metadata || {}
      });
    } else {
      setFormData(initialFormData);
    }
  }, [endpoint, isOpen]);

  const handleChange = (field: keyof AppEndpointFormData, value: any) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);

    try {
      await onSubmit(formData);
      onClose();
    } catch (error) {
    } finally {
      setSubmitting(false);
    }
  };

  const addHeader = () => {
    if (newHeader.key && newHeader.value) {
      setFormData(prev => ({
        ...prev,
        headers: { ...prev.headers, [newHeader.key]: newHeader.value }
      }));
      setNewHeader({ key: '', value: '' });
    }
  };

  const removeHeader = (key: string) => {
    setFormData(prev => {
      const headers = { ...prev.headers };
      if (Object.prototype.hasOwnProperty.call(headers, key)) {
        delete headers[key as keyof typeof headers];
      }
      return { ...prev, headers };
    });
  };

  const addParameter = () => {
    if (newParameter.key && newParameter.value) {
      setFormData(prev => ({
        ...prev,
        parameters: { 
          ...prev.parameters, 
          [newParameter.key]: {
            type: newParameter.type,
            default: newParameter.value,
            required: false
          }
        }
      }));
      setNewParameter({ key: '', value: '', type: 'string' });
    }
  };

  const removeParameter = (key: string) => {
    setFormData(prev => {
      const parameters = { ...prev.parameters };
      if (Object.prototype.hasOwnProperty.call(parameters, key)) {
        delete parameters[key as keyof typeof parameters];
      }
      return { ...prev, parameters };
    });
  };

  const tabs = [
    { id: 'basic', label: 'Basic Info', icon: '📝' },
    { id: 'config', label: 'Configuration', icon: '⚙️' },
    { id: 'schema', label: 'Schema & Docs', icon: '📋' }
  ] as const;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title} maxWidth="xl">
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="flex items-center justify-between pb-4 border-b border-theme">
          <h2 className="text-xl font-semibold text-theme-primary">{title}</h2>
          <Button variant="ghost" size="sm" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </div>

        {/* Tabs */}
        <div className="border-b border-theme">
          <div className="flex space-x-8 -mb-px overflow-x-auto scrollbar-hide">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab.id
                    ? 'border-theme-link text-theme-link'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                <span className="text-base">{tab.icon}</span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Basic Info Tab */}
        {activeTab === 'basic' && (
          <div className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Endpoint Name *
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => handleChange('name', e.target.value)}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  placeholder="User Profile API"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  HTTP Method *
                </label>
                <select
                  value={formData.http_method}
                  onChange={(e) => handleChange('http_method', e.target.value as HttpMethod)}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  required
                >
                  {httpMethods.map(method => (
                    <option key={method} value={method}>{method}</option>
                  ))}
                </select>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                API Path *
              </label>
              <input
                type="text"
                value={formData.path}
                onChange={(e) => handleChange('path', e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                placeholder="/api/v1/users/profile"
                required
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Description
              </label>
              <textarea
                value={formData.description}
                onChange={(e) => handleChange('description', e.target.value)}
                rows={3}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                placeholder="Describe what this endpoint does..."
              />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    checked={formData.requires_auth}
                    onChange={(e) => handleChange('requires_auth', e.target.checked)}
                    className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                  />
                  <span className="text-sm font-medium text-theme-primary">Requires Authentication</span>
                </label>
              </div>

              <div>
                <label className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    checked={formData.is_public}
                    onChange={(e) => handleChange('is_public', e.target.checked)}
                    className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                  />
                  <span className="text-sm font-medium text-theme-primary">Public API</span>
                </label>
              </div>

              <div>
                <label className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    checked={formData.is_active}
                    onChange={(e) => handleChange('is_active', e.target.checked)}
                    className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                  />
                  <span className="text-sm font-medium text-theme-primary">Active</span>
                </label>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Version
              </label>
              <input
                type="text"
                value={formData.version}
                onChange={(e) => handleChange('version', e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                placeholder="1.0"
              />
            </div>
          </div>
        )}

        {/* Configuration Tab */}
        {activeTab === 'config' && (
          <div className="space-y-6">
            {/* Headers */}
            <div>
              <h3 className="text-lg font-medium text-theme-primary mb-4">Request Headers</h3>
              
              {Object.entries(formData.headers || {}).map(([key, value]) => (
                <div key={key} className="flex items-center space-x-2 mb-2">
                  <input
                    type="text"
                    value={key}
                    readOnly
                    className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  />
                  <input
                    type="text"
                    value={String(value)}
                    readOnly
                    className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  />
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => removeHeader(key)}
                  >
                    <Minus className="w-4 h-4" />
                  </Button>
                </div>
              ))}

              <div className="flex items-center space-x-2">
                <input
                  type="text"
                  placeholder="Header name"
                  value={newHeader.key}
                  onChange={(e) => setNewHeader(prev => ({ ...prev, key: e.target.value }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <input
                  type="text"
                  placeholder="Header value"
                  value={newHeader.value}
                  onChange={(e) => setNewHeader(prev => ({ ...prev, value: e.target.value }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <Button type="button" variant="outline" size="sm" onClick={addHeader}>
                  <Plus className="w-4 h-4" />
                </Button>
              </div>
            </div>

            {/* Parameters */}
            <div>
              <h3 className="text-lg font-medium text-theme-primary mb-4">Query Parameters</h3>
              
              {Object.entries(formData.parameters || {}).map(([key, param]) => (
                <div key={key} className="flex items-center space-x-2 mb-2">
                  <input
                    type="text"
                    value={key}
                    readOnly
                    className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  />
                  <input
                    type="text"
                    value={typeof param === 'object' ? param.default || '' : String(param)}
                    readOnly
                    className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  />
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => removeParameter(key)}
                  >
                    <Minus className="w-4 h-4" />
                  </Button>
                </div>
              ))}

              <div className="flex items-center space-x-2">
                <input
                  type="text"
                  placeholder="Parameter name"
                  value={newParameter.key}
                  onChange={(e) => setNewParameter(prev => ({ ...prev, key: e.target.value }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <input
                  type="text"
                  placeholder="Default value"
                  value={newParameter.value}
                  onChange={(e) => setNewParameter(prev => ({ ...prev, value: e.target.value }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <select
                  value={newParameter.type}
                  onChange={(e) => setNewParameter(prev => ({ ...prev, type: e.target.value }))}
                  className="px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                >
                  <option value="string">String</option>
                  <option value="number">Number</option>
                  <option value="boolean">Boolean</option>
                </select>
                <Button type="button" variant="outline" size="sm" onClick={addParameter}>
                  <Plus className="w-4 h-4" />
                </Button>
              </div>
            </div>

            {/* Rate Limits */}
            <div>
              <h3 className="text-lg font-medium text-theme-primary mb-4">Rate Limits</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Requests per Minute
                  </label>
                  <input
                    type="number"
                    value={formData.rate_limits?.requests_per_minute || 100}
                    onChange={(e) => handleChange('rate_limits', {
                      ...formData.rate_limits,
                      requests_per_minute: parseInt(e.target.value)
                    })}
                    className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Requests per Hour
                  </label>
                  <input
                    type="number"
                    value={formData.rate_limits?.requests_per_hour || 1000}
                    onChange={(e) => handleChange('rate_limits', {
                      ...formData.rate_limits,
                      requests_per_hour: parseInt(e.target.value)
                    })}
                    className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Schema & Documentation Tab */}
        {activeTab === 'schema' && (
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-medium text-theme-primary mb-4">Request Schema (JSON)</h3>
              <textarea
                value={formData.request_schema || ''}
                onChange={(e) => handleChange('request_schema', e.target.value)}
                rows={8}
                placeholder='{"type": "object", "properties": {"name": {"type": "string"}}}'
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-sm focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>

            <div>
              <h3 className="text-lg font-medium text-theme-primary mb-4">Response Schema (JSON)</h3>
              <textarea
                value={formData.response_schema || ''}
                onChange={(e) => handleChange('response_schema', e.target.value)}
                rows={8}
                placeholder='{"type": "object", "properties": {"success": {"type": "boolean"}}}'
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-sm focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>

            <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4">
              <div className="flex items-start space-x-3">
                <span className="text-lg">💡</span>
                <div>
                  <h4 className="font-medium text-theme-primary">Schema Guidelines</h4>
                  <p className="text-sm text-theme-secondary mt-1">
                    Use JSON Schema format to define request and response structures. This helps with API documentation and validation.
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Form Actions */}
        <div className="flex items-center justify-end space-x-3 pt-6 border-t border-theme">
          <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? (
              <>
                <LoadingSpinner size="sm" />
                <span className="ml-2">{endpoint ? 'Updating...' : 'Creating...'}</span>
              </>
            ) : (
              <span>{endpoint ? 'Update Endpoint' : 'Create Endpoint'}</span>
            )}
          </Button>
        </div>
      </form>
    </Modal>
  );
};