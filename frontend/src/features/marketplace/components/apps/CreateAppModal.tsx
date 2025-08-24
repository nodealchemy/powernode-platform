import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { AppFormData } from '../../types';
import { useApps } from '../../hooks/useApps';
import { X } from 'lucide-react';

interface CreateAppModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: (app: any) => void;
}

export const CreateAppModal: React.FC<CreateAppModalProps> = ({
CreateAppModal.displayName = 'CreateAppModal';
  isOpen,
  onClose,
  onSuccess
}) => {
  const { createApp } = useApps();
  const [formData, setFormData] = useState<AppFormData>({
    name: '',
    description: '',
    short_description: '',
    category: '',
    icon: '',
    homepage_url: '',
    documentation_url: '',
    support_url: '',
    repository_url: '',
    license: '',
    privacy_policy_url: '',
    terms_of_service_url: '',
    tags: [],
    configuration: {},
    metadata: {}
  });

  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [tagInput, setTagInput] = useState('');

  const validateForm = () => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'App name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'App name must be at least 2 characters';
    } else if (formData.name.length > 255) {
      newErrors.name = 'App name must be less than 255 characters';
    }

    if (!formData.description.trim()) {
      newErrors.description = 'Description is required';
    } else if (formData.description.length > 10000) {
      newErrors.description = 'Description must be less than 10,000 characters';
    }

    if (!formData.short_description.trim()) {
      newErrors.short_description = 'Short description is required';
    } else if (formData.short_description.length > 500) {
      newErrors.short_description = 'Short description must be less than 500 characters';
    }

    if (!formData.category.trim()) {
      newErrors.category = 'Category is required';
    }

    // URL validations
    const urlFields = ['homepage_url', 'documentation_url', 'support_url', 'repository_url', 'privacy_policy_url', 'terms_of_service_url'];
    urlFields.forEach(field => {
      const value = formData[field as keyof AppFormData] as string;
      if (value && value.trim()) {
        try {
          new URL(value.startsWith('http') ? value : `https://${value}`);
        } catch {
          // eslint-disable-next-line security/detect-object-injection
          newErrors[field] = 'Please enter a valid URL';
        }
      }
    });

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) {
      return;
    }

    setSubmitting(true);
    
    try {
      const app = await createApp(formData);
      
      if (app) {
        onSuccess?.(app);
        onClose();
        resetForm();
      }
    } catch (error) {
      console.error('Error creating app:', error);
    } finally {
      setSubmitting(false);
    }
  };

  const resetForm = () => {
    setFormData({
      name: '',
      description: '',
      short_description: '',
      category: '',
      icon: '',
      homepage_url: '',
      documentation_url: '',
      support_url: '',
      repository_url: '',
      license: '',
      privacy_policy_url: '',
      terms_of_service_url: '',
      tags: [],
      configuration: {},
      metadata: {}
    });
    setErrors({});
    setTagInput('');
  };

  const handleClose = () => {
    if (!submitting) {
      resetForm();
      onClose();
    }
  };

  const handleInputChange = (field: keyof AppFormData, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    
    // Clear error when user starts typing
    // eslint-disable-next-line security/detect-object-injection
    if (errors[field]) {
      setErrors(prev => {
        const newErrors = { ...prev };
        // eslint-disable-next-line security/detect-object-injection
        delete newErrors[field];
        return newErrors;
      });
    }
  };

  const addTag = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault();
      const tag = tagInput.trim().toLowerCase();
      
      if (tag && !formData.tags.includes(tag) && formData.tags.length < 10) {
        setFormData(prev => ({
          ...prev,
          tags: [...prev.tags, tag]
        }));
        setTagInput('');
      }
    }
  };

  const removeTag = (tagToRemove: string) => {
    setFormData(prev => ({
      ...prev,
      tags: prev.tags.filter(tag => tag !== tagToRemove)
    }));
  };

  const categories = [
    'productivity',
    'communication',
    'analytics',
    'marketing',
    'development',
    'design',
    'finance',
    'crm',
    'ecommerce',
    'education',
    'utilities',
    'integration',
    'other'
  ];

  const licenses = [
    'MIT',
    'Apache-2.0',
    'GPL-3.0',
    'BSD-3-Clause',
    'ISC',
    'MPL-2.0',
    'LGPL-3.0',
    'Custom',
    'Proprietary'
  ];

  return (
    <Modal isOpen={isOpen} onClose={handleClose} maxWidth="4xl" title="Create New App">

      <form onSubmit={handleSubmit}>
        <div className="space-y-6">
          {/* Basic Information */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <FormField
              label="App Name"
              type="text"
              value={formData.name}
              onChange={(value) => handleInputChange('name', value)}
              placeholder="My Awesome App"
              required
              error={errors.name}
              disabled={submitting}
            />

            <FormField
              label="Category"
              type="select"
              value={formData.category}
              onChange={(value) => handleInputChange('category', value)}
              required
              error={errors.category}
              disabled={submitting}
              options={[
                { value: '', label: 'Select a category' },
                ...categories.map(category => ({
                  value: category,
                  label: category.charAt(0).toUpperCase() + category.slice(1)
                }))
              ]}
            />
          </div>

          <div className="space-y-2">
            <FormField
              label="Short Description"
              type="textarea"
              value={formData.short_description}
              onChange={(value) => handleInputChange('short_description', value)}
              placeholder="A brief description of your app..."
              required
              error={errors.short_description}
              helpText="A brief description that appears in app listings (max 500 characters)"
              rows={2}
              disabled={submitting}
            />
            <div className="text-xs text-theme-tertiary">
              {formData.short_description.length}/500 characters
            </div>
          </div>

          <div className="space-y-2">
            <FormField
              label="Full Description"
              type="textarea"
              value={formData.description}
              onChange={(value) => handleInputChange('description', value)}
              placeholder="Provide a detailed description of your app, its features, and how it helps users..."
              required
              error={errors.description}
              helpText="Detailed description of your app's features and functionality"
              rows={4}
              disabled={submitting}
            />
            <div className="text-xs text-theme-tertiary">
              {formData.description.length}/10,000 characters
            </div>
          </div>

          {/* Tags */}
          <div className="space-y-2">
            <label className="block text-sm font-medium text-theme-primary">
              Tags
            </label>
            <p className="text-sm text-theme-secondary">Add relevant tags to help users discover your app (max 10 tags)</p>
            <input
              type="text"
              value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onKeyDown={addTag}
              placeholder="Type tags and press Enter or comma to add..."
              className="w-full px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent bg-theme-surface text-theme-primary"
              disabled={submitting || formData.tags.length >= 10}
            />
            
            {formData.tags.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {formData.tags.map((tag) => (
                  <span
                    key={tag}
                    className="inline-flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary text-white text-sm rounded-md"
                  >
                    {tag}
                    <button
                      type="button"
                      onClick={() => removeTag(tag)}
                      disabled={submitting}
                      className="text-white hover:text-gray-200 ml-1"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}
          </div>

          {/* URLs */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <FormField
              label="Homepage URL"
              type="url"
              value={formData.homepage_url}
              onChange={(value) => handleInputChange('homepage_url', value)}
              placeholder="https://myapp.com"
              error={errors.homepage_url}
              disabled={submitting}
            />

            <FormField
              label="Documentation URL"
              type="url"
              value={formData.documentation_url}
              onChange={(value) => handleInputChange('documentation_url', value)}
              placeholder="https://docs.myapp.com"
              error={errors.documentation_url}
              disabled={submitting}
            />

            <FormField
              label="Support URL"
              type="url"
              value={formData.support_url}
              onChange={(value) => handleInputChange('support_url', value)}
              placeholder="https://support.myapp.com"
              error={errors.support_url}
              disabled={submitting}
            />

            <FormField
              label="Repository URL"
              type="url"
              value={formData.repository_url}
              onChange={(value) => handleInputChange('repository_url', value)}
              placeholder="https://github.com/user/repo"
              error={errors.repository_url}
              disabled={submitting}
            />
          </div>

          {/* License */}
          <FormField
            label="License"
            type="select"
            value={formData.license}
            onChange={(value) => handleInputChange('license', value)}
            helpText="Select the license for your app"
            disabled={submitting}
            options={[
              { value: '', label: 'Select a license (optional)' },
              ...licenses.map(license => ({ value: license, label: license }))
            ]}
          />

          {/* Icon */}
          <div className="space-y-2">
            <label className="block text-sm font-medium text-theme-primary">
              App Icon
            </label>
            <p className="text-sm text-theme-secondary">Single emoji or character to represent your app</p>
            <input
              type="text"
              value={formData.icon}
              onChange={(e) => handleInputChange('icon', e.target.value.slice(0, 2))}
              placeholder="📱"
              maxLength={2}
              className="w-20 px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent bg-theme-surface text-theme-primary text-center text-xl"
              disabled={submitting}
            />
          </div>
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-3 pt-6 mt-6 border-t border-theme">
          <Button
            type="button"
            variant="outline"
            onClick={handleClose}
            disabled={submitting}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            variant="primary"
            disabled={submitting}
            loading={submitting}
          >
            {submitting ? 'Creating App...' : 'Create App'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};