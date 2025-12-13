import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Plus, CheckCircle } from 'lucide-react';
import type { AddServiceModalProps } from './types';

export const AddServiceModal: React.FC<AddServiceModalProps> = ({
  isOpen,
  onClose,
  onAddService,
  existingServices,
  templates
}) => {
  const { showNotification } = useNotifications();
  const [serviceName, setServiceName] = useState('');
  const [selectedTemplate, setSelectedTemplate] = useState<string>('');
  const [customConfig, setCustomConfig] = useState({
    host: 'localhost',
    port: 3000,
    protocol: 'http',
    health_check_path: '/health'
  });
  const [useTemplate, setUseTemplate] = useState(true);

  const resetForm = () => {
    setServiceName('');
    setSelectedTemplate('');
    setCustomConfig({
      host: 'localhost',
      port: 3000,
      protocol: 'http',
      health_check_path: '/health'
    });
    setUseTemplate(true);
  };

  const handleClose = () => {
    resetForm();
    onClose();
  };

  const handleSubmit = () => {
    if (!serviceName.trim()) {
      showNotification('Please enter a service name', 'error');
      return;
    }

    if (existingServices.includes(serviceName.toLowerCase())) {
      showNotification('A service with this name already exists', 'error');
      return;
    }

    let config;
    if (useTemplate && selectedTemplate) {
      const template = templates.find(t => t.type === selectedTemplate);
      config = template ? { ...template.config } : customConfig;
    } else {
      config = {
        ...customConfig,
        base_url: `${customConfig.protocol}://${customConfig.host}:${customConfig.port}`
      };
    }

    onAddService(serviceName.toLowerCase(), config);
    handleClose();
  };

  useEffect(() => {
    if (!isOpen) {
      resetForm();
    }
  }, [isOpen]);

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Add New Service"
      maxWidth="lg"
    >
      <div className="space-y-6">
        {/* Service Name */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Service Name *
          </label>
          <input
            type="text"
            value={serviceName}
            onChange={(e) => setServiceName(e.target.value)}
            className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            placeholder="e.g., frontend, backend, api"
          />
          <p className="text-xs text-theme-secondary mt-1">
            Use lowercase letters, numbers, and underscores only
          </p>
        </div>

        {/* Configuration Method */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-3">
            Configuration Method
          </label>
          <div className="flex space-x-4">
            <Button
              onClick={() => setUseTemplate(true)}
              variant={useTemplate ? 'primary' : 'secondary'}
              size="sm"
            >
              Use Template
            </Button>
            <Button
              onClick={() => setUseTemplate(false)}
              variant={!useTemplate ? 'primary' : 'secondary'}
              size="sm"
            >
              Custom Configuration
            </Button>
          </div>
        </div>

        {/* Template Selection */}
        {useTemplate && (
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Service Template
            </label>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {templates.map((template) => (
                <Card
                  key={template.type}
                  className={`p-3 cursor-pointer border-2 transition-all ${
                    selectedTemplate === template.type
                      ? 'border-theme-primary bg-theme-primary/5'
                      : 'border-theme hover:border-theme-primary/50'
                  }`}
                  onClick={() => setSelectedTemplate(template.type)}
                >
                  <div className="flex justify-between items-center mb-2">
                    <h4 className="font-medium text-theme-primary text-sm">{template.name}</h4>
                    {selectedTemplate === template.type && (
                      <CheckCircle className="w-4 h-4 text-theme-primary" />
                    )}
                  </div>
                  <div className="text-xs space-y-1 text-theme-secondary">
                    <div>Port: {template.config.port}</div>
                    <div>Protocol: {template.config.protocol}</div>
                  </div>
                </Card>
              ))}
            </div>
          </div>
        )}

        {/* Custom Configuration */}
        {!useTemplate && (
          <div className="space-y-4">
            <h4 className="text-sm font-medium text-theme-primary">Custom Configuration</h4>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Host
                </label>
                <input
                  type="text"
                  value={customConfig.host}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, host: e.target.value }))}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="localhost"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Port
                </label>
                <input
                  type="number"
                  value={customConfig.port}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, port: parseInt(e.target.value) || 3000 }))}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="3000"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Protocol
                </label>
                <select
                  value={customConfig.protocol}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, protocol: e.target.value }))}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                >
                  <option value="http">HTTP</option>
                  <option value="https">HTTPS</option>
                  <option value="tcp">TCP</option>
                  <option value="ws">WebSocket</option>
                  <option value="wss">WebSocket Secure</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Health Check Path
                </label>
                <input
                  type="text"
                  value={customConfig.health_check_path}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, health_check_path: e.target.value }))}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="/health"
                />
              </div>
            </div>

            {/* Preview */}
            <div className="p-3 bg-theme-surface border border-theme rounded-lg">
              <p className="text-sm text-theme-secondary mb-1">Service URL Preview:</p>
              <p className="text-theme-primary font-mono">
                {customConfig.protocol}://{customConfig.host}:{customConfig.port}{customConfig.health_check_path}
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Modal Actions */}
      <div className="flex justify-end space-x-3 mt-6 pt-4 border-t border-theme">
        <Button
          onClick={handleClose}
          variant="secondary"
        >
          Cancel
        </Button>
        <Button
          onClick={handleSubmit}
          variant="primary"
          disabled={!serviceName.trim() || (useTemplate && !selectedTemplate)}
        >
          <Plus className="w-4 h-4 mr-2" />
          Add Service
        </Button>
      </div>
    </Modal>
  );
};
