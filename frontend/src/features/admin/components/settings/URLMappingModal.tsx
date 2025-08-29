import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useNotification } from '@/shared/hooks/useNotification';
import { URLMapping } from '../../services/servicesApi';

interface URLMappingModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (mapping: URLMapping) => Promise<void>;
  mapping?: URLMapping | null;
  availableServices: string[];
}

const httpMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD'];

export const URLMappingModal: React.FC<URLMappingModalProps> = ({
  isOpen,
  onClose,
  onSave,
  mapping,
  availableServices
}) => {
  const { showNotification } = useNotification();
  const [saving, setSaving] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    pattern: '',
    target_service: '',
    priority: 999,
    methods: ['GET'] as string[],
    enabled: true,
    description: ''
  });

  useEffect(() => {
    if (mapping) {
      setFormData({
        name: mapping.name,
        pattern: mapping.pattern,
        target_service: mapping.target_service,
        priority: mapping.priority,
        methods: mapping.methods,
        enabled: mapping.enabled,
        description: mapping.description || ''
      });
    } else {
      setFormData({
        name: '',
        pattern: '',
        target_service: availableServices[0] || '',
        priority: 999,
        methods: ['GET'],
        enabled: true,
        description: ''
      });
    }
  }, [mapping, availableServices, isOpen]);

  const handleSave = async () => {
    if (!formData.name.trim() || !formData.pattern.trim() || !formData.target_service) {
      showNotification('Please fill in all required fields', 'error');
      return;
    }

    if (formData.methods.length === 0) {
      showNotification('Please select at least one HTTP method', 'error');
      return;
    }

    try {
      setSaving(true);
      
      const mappingData: URLMapping = {
        id: mapping?.id || `mapping_${Date.now()}`,
        name: formData.name.trim(),
        pattern: formData.pattern.trim(),
        target_service: formData.target_service,
        priority: formData.priority,
        methods: formData.methods,
        enabled: formData.enabled,
        description: formData.description.trim()
      };

      await onSave(mappingData);
      onClose();
      showNotification(`URL mapping ${mapping ? 'updated' : 'created'} successfully`, 'success');
    } catch (error) {
      showNotification(`Failed to ${mapping ? 'update' : 'create'} URL mapping`, 'error');
    } finally {
      setSaving(false);
    }
  };

  const updateFormData = (field: string, value: any) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const toggleMethod = (method: string) => {
    const methods = formData.methods.includes(method)
      ? formData.methods.filter(m => m !== method)
      : [...formData.methods, method];
    updateFormData('methods', methods);
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`${mapping ? 'Edit' : 'Create'} URL Mapping`}
      maxWidth="lg"
    >
      <div className="space-y-4">
        {/* Name */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Name *
          </label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => updateFormData('name', e.target.value)}
            className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            placeholder="e.g., Frontend Routes, API Routes"
          />
        </div>

        {/* Pattern */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            URL Pattern *
          </label>
          <input
            type="text"
            value={formData.pattern}
            onChange={(e) => updateFormData('pattern', e.target.value)}
            className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            placeholder="e.g., /api/v1/*, /, /admin/*"
          />
          <p className="text-xs text-theme-secondary mt-1">
            Use * for wildcards. Examples: /, /api/*, /admin/users/*
          </p>
        </div>

        <div className="grid grid-cols-2 gap-4">
          {/* Target Service */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Target Service *
            </label>
            <select
              value={formData.target_service}
              onChange={(e) => updateFormData('target_service', e.target.value)}
              className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            >
              {availableServices.map(service => (
                <option key={service} value={service}>
                  {service.charAt(0).toUpperCase() + service.slice(1)}
                </option>
              ))}
            </select>
          </div>

          {/* Priority */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Priority
            </label>
            <input
              type="number"
              value={formData.priority}
              onChange={(e) => updateFormData('priority', parseInt(e.target.value) || 999)}
              className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary"
              min="1"
              max="9999"
            />
            <p className="text-xs text-theme-secondary mt-1">
              Lower numbers have higher priority (1 = highest)
            </p>
          </div>
        </div>

        {/* HTTP Methods */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            HTTP Methods *
          </label>
          <div className="flex flex-wrap gap-2">
            {httpMethods.map(method => (
              <Button
                key={method}
                onClick={() => toggleMethod(method)}
                variant={formData.methods.includes(method) ? 'primary' : 'secondary'}
                size="sm"
                className="text-xs"
              >
                {method}
              </Button>
            ))}
          </div>
        </div>

        {/* Description */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Description
          </label>
          <textarea
            value={formData.description}
            onChange={(e) => updateFormData('description', e.target.value)}
            placeholder="Optional description for this URL mapping..."
            rows={3}
            className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary resize-vertical"
          />
        </div>

        {/* Enabled Toggle */}
        <div className="flex items-center justify-between">
          <div>
            <label className="block text-sm font-medium text-theme-primary">
              Enabled
            </label>
            <p className="text-sm text-theme-secondary">
              Whether this URL mapping is active
            </p>
          </div>
          <Button
            onClick={() => updateFormData('enabled', !formData.enabled)}
            variant={formData.enabled ? 'success' : 'secondary'}
            size="sm"
          >
            {formData.enabled ? 'Enabled' : 'Disabled'}
          </Button>
        </div>
      </div>

      {/* Modal Actions */}
      <div className="flex justify-end space-x-3 mt-6 pt-4 border-t border-theme">
        <Button
          onClick={onClose}
          variant="secondary"
          disabled={saving}
        >
          Cancel
        </Button>
        <Button
          onClick={handleSave}
          variant="primary"
          disabled={saving}
          loading={saving}
        >
          {mapping ? 'Update' : 'Create'} Mapping
        </Button>
      </div>
    </Modal>
  );
};