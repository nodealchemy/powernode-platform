import React, { useState } from 'react';
import { Worker, UpdateWorkerData } from '../../services/workerApi';

interface WorkerEditFormProps {
  worker: Worker;
  onUpdate: (data: UpdateWorkerData) => Promise<void>;
  onCancel: () => void;
}

export const WorkerEditForm: React.FC<WorkerEditFormProps> = ({ worker, onUpdate, onCancel }) => {
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    name: worker.name,
    description: worker.description || '',
    permissions: worker.permissions
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      await onUpdate(formData);
    } catch (error) {
      console.error('Failed to update worker:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-semibold text-theme-primary">Edit Worker</h3>
      
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
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Description
          </label>
          <textarea
            value={formData.description}
            onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            rows={3}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Permissions
          </label>
          <select
            value={formData.permissions}
            onChange={(e) => setFormData(prev => ({ ...prev, permissions: e.target.value as any }))}
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
          >
            <option value="readonly">Read Only</option>
            <option value="standard">Standard</option>
            <option value="admin">Admin</option>
            <option value="super_admin">Super Admin</option>
          </select>
        </div>


        <div className="flex justify-end space-x-3 pt-4">
          <button
            type="button"
            onClick={onCancel}
            className="px-4 py-2 border border-theme rounded-md text-theme-secondary hover:text-theme-primary transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={loading || !formData.name.trim()}
            className="px-4 py-2 bg-theme-interactive-primary hover:bg-theme-interactive-primary/80 text-white rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading ? 'Updating...' : 'Update Worker'}
          </button>
        </div>
      </form>
    </div>
  );
};

export default WorkerEditForm;