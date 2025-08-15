import React, { useState } from 'react';
import { CreateWorkerData } from '../../services/workerApi';

interface CreateWorkerModalProps {
  onClose: () => void;
  onCreate: (data: CreateWorkerData) => Promise<void>;
}

export const CreateWorkerModal: React.FC<CreateWorkerModalProps> = ({ onClose, onCreate }) => {
  const [formData, setFormData] = useState<CreateWorkerData>({
    name: '',
    description: '',
    permissions: 'standard',
    role: 'account'
  });

  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      await onCreate(formData);
      onClose();
    } catch (error) {
      console.error('Failed to create worker:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md">
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-xl font-semibold text-theme-primary">Create New Worker</h2>
          <button
            onClick={onClose}
            className="text-theme-secondary hover:text-theme-primary"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Worker Name
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              placeholder="Enter worker name"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Description
            </label>
            <textarea
              value={formData.description || ''}
              onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              placeholder="Enter description (optional)"
              rows={3}
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Permissions
            </label>
            <select
              value={formData.permissions || 'standard'}
              onChange={(e) => setFormData(prev => ({ ...prev, permissions: e.target.value as any }))}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            >
              <option value="readonly">Read Only</option>
              <option value="standard">Standard</option>
              <option value="admin">Admin</option>
              <option value="super_admin">Super Admin</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Role
            </label>
            <select
              value={formData.role || 'account'}
              onChange={(e) => setFormData(prev => ({ ...prev, role: e.target.value as any }))}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            >
              <option value="account">Account Worker</option>
              <option value="system">System Worker</option>
            </select>
          </div>

          <div className="flex justify-end space-x-3 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 border border-theme rounded-md text-theme-secondary hover:text-theme-primary transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading || !formData.name.trim()}
              className="px-4 py-2 bg-theme-interactive-primary hover:bg-theme-interactive-primary/80 text-white rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? 'Creating...' : '✨ Create Worker'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default CreateWorkerModal;