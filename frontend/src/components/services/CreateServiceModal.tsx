import React, { useState } from 'react';
import { CreateServiceData } from '../../services/serviceApi';

interface CreateServiceModalProps {
  onClose: () => void;
  onCreate: (data: CreateServiceData) => Promise<void>;
}

export const CreateServiceModal: React.FC<CreateServiceModalProps> = ({ onClose, onCreate }) => {
  const [formData, setFormData] = useState<CreateServiceData>({
    name: '',
    description: '',
    permissions: 'standard'
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!formData.name.trim()) {
      setError('Service name is required');
      return;
    }
    
    try {
      setLoading(true);
      setError(null);
      await onCreate(formData);
    } catch (error: any) {
      setError(error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (field: keyof CreateServiceData, value: any) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    setError(null);
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-md w-full mx-4 max-h-screen overflow-y-auto">
        <div className="px-4 sm:px-6 lg:px-8 py-4 border-b border-theme">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-medium text-theme-primary">Create New Service</h3>
            <button
              onClick={onClose}
              className="text-theme-tertiary hover:text-theme-primary transition-colors duration-200"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="px-4 sm:px-6 lg:px-8 py-4">
          {error && (
            <div className="mb-4 p-3 bg-theme-error border border-theme rounded-md">
              <p className="text-theme-error text-sm">{error}</p>
            </div>
          )}

          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Service Name <span className="text-theme-error">*</span>
              </label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => handleChange('name', e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-md text-sm bg-theme-surface text-theme-primary focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
                placeholder="e.g., API Worker, Report Generator"
                required
              />
              <p className="text-xs text-theme-secondary mt-1">
                A descriptive name for this service
              </p>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Description
              </label>
              <textarea
                value={formData.description}
                onChange={(e) => handleChange('description', e.target.value)}
                rows={3}
                className="w-full px-3 py-2 border border-theme rounded-md text-sm bg-theme-surface text-theme-primary focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
                placeholder="Optional description of what this service does"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Permissions Level
              </label>
              <select
                value={formData.permissions}
                onChange={(e) => handleChange('permissions', e.target.value as any)}
                className="w-full px-3 py-2 border border-theme rounded-md text-sm bg-theme-surface text-theme-primary focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
              >
                <option value="readonly">Read Only - Can only read data</option>
                <option value="standard">Standard - Can process jobs and read/write data</option>
                <option value="admin">Admin - Can manage jobs and access admin functions</option>
                <option value="super_admin">Super Admin - Full access including service management</option>
              </select>
              <p className="text-xs text-theme-secondary mt-1">
                Choose the appropriate access level for this service
              </p>
            </div>

          </div>

          <div className="mt-6 pt-4 border-t border-theme flex gap-3">
            <button
              type="button"
              onClick={onClose}
              disabled={loading}
              className="flex-1 px-4 py-2 border border-theme text-theme-primary rounded-md text-sm font-medium hover:bg-theme-surface-hover disabled:opacity-50 transition-colors duration-200"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading || !formData.name.trim()}
              className="flex-1 bg-theme-interactive-primary text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-theme-interactive-primary-hover disabled:opacity-50 transition-colors duration-200"
            >
              {loading ? 'Creating...' : 'Create Service'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default CreateServiceModal;