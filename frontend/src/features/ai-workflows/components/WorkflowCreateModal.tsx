import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, Workflow, Save, X } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { getErrorMessage } from '@/shared/utils/typeGuards';

// Form data interface for workflow creation
interface CreateWorkflowFormData {
  name?: string;
  description?: string;
  status?: 'draft' | 'published';
  visibility?: 'private' | 'account' | 'public';
  execution_mode?: 'sequential' | 'parallel' | 'conditional';
  timeout_seconds?: number;
  tags?: string[];
}

export interface WorkflowCreateModalProps {
  isOpen: boolean;
  onClose: () => void;
  onWorkflowCreated?: (workflowId: string) => void;
}

export const WorkflowCreateModal: React.FC<WorkflowCreateModalProps> = ({
  isOpen,
  onClose,
  onWorkflowCreated
}) => {
  const navigate = useNavigate();
  const { addNotification } = useNotifications();
  const { currentUser } = useAuth();


  const [formData, setFormData] = useState<CreateWorkflowFormData>({
    name: '',
    description: '',
    status: 'draft',
    visibility: 'private',
    execution_mode: 'sequential',
    timeout_seconds: 300,
    tags: []
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

  const handleInputChange = (
    field: keyof CreateWorkflowFormData,
    value: string | number | string[]
  ) => {
    setFormData((prev: CreateWorkflowFormData) => ({
      ...prev,
      [field]: value
    }));

    // Clear error when user starts typing
    if (errors[field as string]) {
      setErrors((prev: Record<string, string>) => ({
        ...prev,
        [field as string]: ''
      }));
    }
  };

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name?.trim()) {
      newErrors.name = 'Workflow name is required';
    } else if (formData.name.length < 3) {
      newErrors.name = 'Workflow name must be at least 3 characters';
    } else if (formData.name.length > 100) {
      newErrors.name = 'Workflow name must be less than 100 characters';
    }

    if (formData.description && formData.description.length > 500) {
      newErrors.description = 'Description must be less than 500 characters';
    }

    if (formData.timeout_seconds && (formData.timeout_seconds < 30 || formData.timeout_seconds > 3600)) {
      newErrors.timeout_seconds = 'Timeout must be between 30 and 3600 seconds';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) {
      return;
    }

    // Check authentication before submitting
    if (!currentUser) {
      addNotification({
        type: 'error',
        title: 'Authentication Required',
        message: 'You must be logged in to create workflows.'
      });
      return;
    }

    // Check permissions
    if (!currentUser.permissions?.includes('ai.workflows.create')) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to create workflows.'
      });
      return;
    }

    setIsSubmitting(true);
    
    try {
      const response = await workflowsApi.createWorkflow({
        name: formData.name!,
        description: formData.description || '',
        status: formData.status || 'draft',
        visibility: formData.visibility || 'private',
        execution_mode: formData.execution_mode || 'sequential',
        timeout_seconds: formData.timeout_seconds || 300,
        tags: formData.tags || [],
        nodes: [],
        edges: []
      });

      addNotification({
        type: 'success',
        title: 'Workflow Created',
        message: `Workflow "${formData.name}" has been created successfully.`
      });

      // Reset form
      setFormData({
        name: '',
        description: '',
        status: 'draft',
        visibility: 'private',
        execution_mode: 'sequential',
        timeout_seconds: 300,
        tags: []
      });
      setErrors({});

      onClose();

      // Navigate to workflow editor or call callback
      if (onWorkflowCreated) {
        onWorkflowCreated(response.id);
      } else {
        navigate(`/app/ai/workflows/${response.id}/edit`);
      }

    } catch (error: unknown) {
      let errorMessage = 'Failed to create workflow. Please try again.';
      let errorTitle = 'Creation Failed';

      // Handle different types of errors
      if (typeof error === 'object' && error !== null && 'response' in error) {
        const axiosError = error as {
          response?: {
            status: number;
            data?: {
              errors?: Record<string, string | string[]>;
              error?: string;
              message?: string;
            };
          };
          request?: unknown;
          message?: string;
        };

        if (axiosError.response) {
          const statusCode = axiosError.response.status;
          const responseData = axiosError.response.data;

          switch (statusCode) {
            case 401:
              errorTitle = 'Authentication Error';
              errorMessage = 'Your session has expired. Please log in again.';
              break;
            case 403:
              errorTitle = 'Permission Denied';
              errorMessage = 'You do not have permission to create workflows.';
              break;
            case 422:
              errorTitle = 'Validation Error';
              if (responseData?.errors) {
                // Handle Rails validation errors
                const validationErrors = Object.entries(responseData.errors)
                  .map(([field, messages]) =>
                    `${field}: ${Array.isArray(messages) ? messages.join(', ') : String(messages)}`
                  )
                  .join('; ');
                errorMessage = validationErrors;
              } else if (responseData?.error) {
                errorMessage = responseData.error;
              }
              break;
            default:
              if (responseData?.error) {
                errorMessage = responseData.error;
              } else if (responseData?.message) {
                errorMessage = responseData.message;
              }
          }
        } else if (axiosError.request) {
          errorTitle = 'Network Error';
          errorMessage = 'Unable to connect to the server. Please check your internet connection.';
        } else if (axiosError.message) {
          errorMessage = axiosError.message;
        }
      } else {
        errorMessage = getErrorMessage(error);
      }

      addNotification({
        type: 'error',
        title: errorTitle,
        message: errorMessage
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleClose = () => {
    if (!isSubmitting) {
      // Reset form when closing
      setFormData({
        name: '',
        description: '',
        status: 'draft',
        visibility: 'private',
        execution_mode: 'sequential',
        timeout_seconds: 300,
        tags: []
      });
      setErrors({});
      onClose();
    }
  };

  const statusOptions = [
    { value: 'draft', label: 'Draft', description: 'Workflow is being developed' },
    { value: 'published', label: 'Published', description: 'Workflow is ready for use' }
  ];

  const visibilityOptions = [
    { value: 'private', label: 'Private', description: 'Only you can access this workflow' },
    { value: 'account', label: 'Account', description: 'All account members can access this workflow' },
    { value: 'public', label: 'Public', description: 'Anyone can view and use this workflow' }
  ];

  const executionModeOptions = [
    { value: 'sequential', label: 'Sequential', description: 'Execute nodes one after another' },
    { value: 'parallel', label: 'Parallel', description: 'Execute nodes simultaneously when possible' },
    { value: 'conditional', label: 'Conditional', description: 'Execute nodes based on conditions' }
  ];

  const modalFooter = (
    <div className="flex items-center gap-3">
      <Button
        variant="outline"
        onClick={handleClose}
        disabled={isSubmitting}
      >
        <X className="h-4 w-4 mr-2" />
        Cancel
      </Button>
      <Button
        variant="primary"
        onClick={handleSubmit}
        disabled={isSubmitting || !formData.name?.trim()}
        loading={isSubmitting}
      >
        <Save className="h-4 w-4 mr-2" />
        {isSubmitting ? 'Creating...' : 'Create Workflow'}
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create New Workflow"
      subtitle="Set up a new AI workflow to automate your processes"
      icon={<Plus className="h-6 w-6" />}
      maxWidth="lg"
      footer={modalFooter}
      closeOnBackdrop={!isSubmitting}
      closeOnEscape={!isSubmitting}
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Basic Information */}
        <div className="space-y-4">
          <h4 className="text-sm font-semibold text-theme-primary">Basic Information</h4>
          
          <Input
            label="Workflow Name"
            placeholder="Enter workflow name..."
            value={formData.name || ''}
            onChange={(e) => handleInputChange('name', e.target.value)}
            error={errors.name}
            required
            disabled={isSubmitting}
            autoFocus
          />

          <Textarea
            label="Description"
            placeholder="Describe what this workflow does..."
            value={formData.description || ''}
            onChange={(e) => handleInputChange('description', e.target.value)}
            error={errors.description}
            disabled={isSubmitting}
            rows={3}
          />
        </div>

        {/* Configuration */}
        <div className="space-y-4">
          <h4 className="text-sm font-semibold text-theme-primary">Configuration</h4>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <EnhancedSelect
              label="Status"
              value={formData.status || 'draft'}
              onChange={(value) => handleInputChange('status', value)}
              options={statusOptions}
              disabled={isSubmitting}
            />

            <EnhancedSelect
              label="Visibility"
              value={formData.visibility || 'private'}
              onChange={(value) => handleInputChange('visibility', value)}
              options={visibilityOptions}
              disabled={isSubmitting}
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <EnhancedSelect
              label="Execution Mode"
              value={formData.execution_mode || 'sequential'}
              onChange={(value) => handleInputChange('execution_mode', value)}
              options={executionModeOptions}
              disabled={isSubmitting}
            />

            <Input
              label="Timeout (seconds)"
              type="number"
              placeholder="300"
              value={formData.timeout_seconds?.toString() || '300'}
              onChange={(e) => handleInputChange('timeout_seconds', parseInt(e.target.value) || 300)}
              error={errors.timeout_seconds}
              disabled={isSubmitting}
              min={30}
              max={3600}
            />
          </div>
        </div>

        {/* Info Note */}
        <div className="bg-theme-info/10 border border-theme-info/20 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <Workflow className="h-5 w-5 text-theme-info flex-shrink-0 mt-0.5" />
            <div className="text-sm">
              <p className="text-theme-primary font-medium">What happens next?</p>
              <p className="text-theme-secondary mt-1">
                After creating the workflow, you'll be taken to the workflow editor where you can add nodes, 
                configure connections, and define the automation logic.
              </p>
            </div>
          </div>
        </div>
      </form>
    </Modal>
  );
};