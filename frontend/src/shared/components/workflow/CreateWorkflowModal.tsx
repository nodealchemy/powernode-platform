import React, { useState, useCallback } from 'react';
import { Save, Play, Workflow, Settings, FileText } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { WorkflowBuilderProvider } from '@/shared/components/workflow/WorkflowBuilder';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { workflowsApi } from '@/shared/services/ai';
import { AiWorkflowNode, AiWorkflowEdge } from '@/shared/types/workflow';

export interface CreateWorkflowModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: (workflowId: string) => void;
}

interface WorkflowFormData {
  name: string;
  description: string;
  status: 'draft' | 'published';
  visibility: 'private' | 'account' | 'public';
  executionMode: 'sequential' | 'parallel' | 'conditional';
  timeoutSeconds: number;
  tags: string[];
  configuration: Record<string, any>;
  nodes: AiWorkflowNode[];
  edges: AiWorkflowEdge[];
}

export const CreateWorkflowModal: React.FC<CreateWorkflowModalProps> = ({
  isOpen,
  onClose,
  onSuccess
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  // Load grid preference from localStorage
  const [showGrid, setShowGrid] = useState(() => {
    const savedPreference = localStorage.getItem('workflowGridEnabled');
    return savedPreference !== null ? savedPreference === 'true' : true;
  });

  // Load snap-to-grid preference from localStorage
  const [snapToGrid, setSnapToGrid] = useState(() => {
    const savedPreference = localStorage.getItem('workflowSnapToGridEnabled');
    return savedPreference !== null ? savedPreference === 'true' : false;
  });

  // Load layout orientation preference from localStorage
  const [layoutOrientation, setLayoutOrientation] = useState<'horizontal' | 'vertical'>(() => {
    const savedPreference = localStorage.getItem('workflowLayoutOrientation');
    return (savedPreference === 'horizontal' || savedPreference === 'vertical') ? savedPreference : 'vertical';
  });

  // Handle grid toggle with localStorage persistence
  const handleGridToggle = useCallback((enabled: boolean) => {
    setShowGrid(enabled);
    localStorage.setItem('workflowGridEnabled', enabled.toString());
  }, []);

  // Handle snap-to-grid toggle with localStorage persistence
  const handleSnapToGridToggle = useCallback((enabled: boolean) => {
    setSnapToGrid(enabled);
    localStorage.setItem('workflowSnapToGridEnabled', enabled.toString());
  }, []);

  // Handle layout orientation change with localStorage persistence
  const handleLayoutOrientationChange = useCallback((orientation: 'horizontal' | 'vertical') => {
    setLayoutOrientation(orientation);
    localStorage.setItem('workflowLayoutOrientation', orientation);
  }, []);

  const [formData, setFormData] = useState<WorkflowFormData>({
    name: '',
    description: '',
    status: 'draft',
    visibility: 'private',
    executionMode: 'sequential',
    timeoutSeconds: 3600,
    tags: [],
    configuration: {
      execution_mode: 'sequential',
      timeout_seconds: 3600,
      max_parallel_nodes: 5,
      auto_retry: false,
      error_handling: 'stop',
      notifications: {
        on_completion: false,
        on_error: true
      }
    },
    nodes: [],
    edges: []
  });

  const [newTag, setNewTag] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [activeTab, setActiveTab] = useState('basic');

  // Check permissions
  const canCreateWorkflows = currentUser?.permissions?.includes('ai.workflows.create') || false;

  // Validate form
  const validateForm = () => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Workflow name is required';
    } else if (formData.name.length < 3) {
      newErrors.name = 'Workflow name must be at least 3 characters';
    } else if (formData.name.length > 255) {
      newErrors.name = 'Workflow name must be less than 255 characters';
    }

    if (!formData.description.trim()) {
      newErrors.description = 'Description is required';
    } else if (formData.description.length < 10) {
      newErrors.description = 'Description must be at least 10 characters';
    }

    if (formData.timeoutSeconds < 60) {
      newErrors.timeoutSeconds = 'Timeout must be at least 60 seconds';
    } else if (formData.timeoutSeconds > 86400) {
      newErrors.timeoutSeconds = 'Timeout cannot exceed 24 hours (86400 seconds)';
    }

    // Validate workflow has at least one node
    if (formData.nodes.length === 0) {
      newErrors.workflow = 'Workflow must have at least one node';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handle form field changes
   
  const handleInputChange = (field: keyof WorkflowFormData, value: any) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));

    // Clear error when user starts typing
    if (errors[field]) {
      setErrors(prev => {
        const newErrors = { ...prev };
        delete newErrors[field];
        return newErrors;
      });
    }
  };

  // Handle workflow builder data
  const handleWorkflowData = (workflowData: {
    nodes: any[];
    edges: any[];
    configuration: Record<string, unknown>;
  }) => {
    setFormData(prev => ({
      ...prev,
      nodes: workflowData.nodes,
      edges: workflowData.edges,
      configuration: {
        ...prev.configuration,
        ...workflowData.configuration
      }
    }));

    // Clear workflow error
    if (errors.workflow) {
      setErrors(prev => {
        const newErrors = { ...prev };
        delete newErrors.workflow;
        return newErrors;
      });
    }
  };

  // Add tag
  const addTag = () => {
    if (newTag.trim() && !formData.tags.includes(newTag.trim())) {
      handleInputChange('tags', [...formData.tags, newTag.trim()]);
      setNewTag('');
    }
  };

  // Remove tag
  const removeTag = (tagToRemove: string) => {
    handleInputChange('tags', formData.tags.filter(tag => tag !== tagToRemove));
  };

  // Handle tag key press
  const handleTagKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      addTag();
    }
  };

  // Submit form
  const handleSubmit = async (saveAs: 'draft' | 'published' = 'draft') => {
    if (!canCreateWorkflows) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to create workflows.'
      });
      return;
    }

    if (!validateForm()) {
      addNotification({
        type: 'error',
        title: 'Validation Error',
        message: 'Please correct the errors in the form.'
      });
      return;
    }

    try {
      setIsSubmitting(true);

      const requestData = {
        name: formData.name.trim(),
        description: formData.description.trim(),
        status: saveAs,
        visibility: formData.visibility,
        executionMode: formData.executionMode,
        timeoutSeconds: formData.timeoutSeconds,
        tags: formData.tags,
        configuration: {
          ...formData.configuration,
          execution_mode: formData.executionMode,
          timeout_seconds: formData.timeoutSeconds
        },
        nodes: formData.nodes,
        edges: formData.edges
      };

      const response = await workflowsApi.createWorkflow(requestData);

      addNotification({
        type: 'success',
        title: 'Workflow Created',
        message: `Workflow "${response.name}" has been created successfully.`
      });

      onClose();
      onSuccess?.(response.id);
    } catch (error) {
      console.error('Failed to create workflow:', error);
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: 'Failed to create workflow. Please try again.'
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const footer = (
    <div className="flex gap-3">
      <Button
        variant="outline"
        onClick={onClose}
        disabled={isSubmitting}
      >
        Cancel
      </Button>
      <Button
        variant="outline"
        onClick={() => handleSubmit('draft')}
        disabled={isSubmitting}
      >
        <Save className="h-4 w-4 mr-2" />
        Save as Draft
      </Button>
      <Button
        onClick={() => handleSubmit('published')}
        disabled={isSubmitting}
      >
        <Play className="h-4 w-4 mr-2" />
        Save & Publish
      </Button>
    </div>
  );

  if (!canCreateWorkflows) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Access Denied"
        maxWidth="md"
        icon={<Workflow />}
        footer={
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        }
      >
        <div className="text-center py-8">
          <p className="text-theme-muted">
            You don't have permission to create workflows.
          </p>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Create New Workflow"
      subtitle="Build an automated AI workflow for your business processes"
      maxWidth="full"
      variant="fullscreen"
      icon={<Workflow />}
      footer={footer}
    >
      <div className="h-full flex flex-col">
        <Tabs value={activeTab} onValueChange={setActiveTab} defaultValue="basic" className="flex-1 flex flex-col">
          <TabsList>
            <TabsTrigger value="basic" className="flex items-center gap-2">
              <FileText className="h-4 w-4" />
              Basic Information
            </TabsTrigger>
            <TabsTrigger value="workflow" className="flex items-center gap-2">
              <Workflow className="h-4 w-4" />
              Workflow Builder
            </TabsTrigger>
            <TabsTrigger value="configuration" className="flex items-center gap-2">
              <Settings className="h-4 w-4" />
              Configuration
            </TabsTrigger>
          </TabsList>

          <TabsContent value="basic" className="space-y-6 mt-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <Input
                  label="Name *"
                  value={formData.name}
                  onChange={(e) => handleInputChange('name', e.target.value)}
                  placeholder="Enter workflow name..."
                  error={errors.name}
                />
              </div>

              <div>
                <EnhancedSelect
                  label="Visibility"
                  value={formData.visibility}
                  onChange={(value) => handleInputChange('visibility', value)}
                  options={[
                    { value: 'private', label: 'Private (Only you)' },
                    { value: 'account', label: 'Account (Team members)' },
                    { value: 'public', label: 'Public (Everyone)' }
                  ]}
                />
              </div>
            </div>

            <div>
              <Textarea
                label="Description *"
                value={formData.description}
                onChange={(e) => handleInputChange('description', e.target.value)}
                placeholder="Describe what this workflow does..."
                rows={3}
                error={errors.description}
              />
            </div>

            <div>
              <EnhancedSelect
                label="Execution Mode"
                value={formData.executionMode}
                onChange={(value) => handleInputChange('executionMode', value)}
                options={[
                  { 
                    value: 'sequential', 
                    label: 'Sequential',
                    description: 'Execute nodes one after another'
                  },
                  { 
                    value: 'parallel', 
                    label: 'Parallel',
                    description: 'Execute multiple nodes simultaneously'
                  },
                  { 
                    value: 'conditional', 
                    label: 'Conditional',
                    description: 'Execute nodes based on conditions'
                  }
                ]}
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Tags
              </label>
              <div className="flex gap-2 mb-2">
                <Input
                  value={newTag}
                  onChange={(e) => setNewTag(e.target.value)}
                  onKeyPress={handleTagKeyPress}
                  placeholder="Add a tag..."
                  className="flex-1"
                />
                <Button type="button" onClick={addTag} variant="outline">
                  Add
                </Button>
              </div>
              {formData.tags.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {formData.tags.map(tag => (
                    <span
                      key={tag}
                      className="px-2 py-1 bg-theme-secondary text-theme-primary rounded-md text-sm flex items-center gap-1"
                    >
                      {tag}
                      <button
                        type="button"
                        onClick={() => removeTag(tag)}
                        className="hover:text-theme-error"
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              )}
            </div>
          </TabsContent>

          <TabsContent value="workflow" className="flex-1 mt-6">
            <div className="h-full min-h-[600px] border border-theme rounded-lg">
              {errors.workflow && (
                <div className="p-4 bg-theme-error-background text-theme-error text-sm border-b border-theme">
                  {errors.workflow}
                </div>
              )}
              <WorkflowBuilderProvider
                onSave={handleWorkflowData}
                showGrid={showGrid}
                onGridToggle={handleGridToggle}
                snapToGrid={snapToGrid}
                onSnapToGridToggle={handleSnapToGridToggle}
                layoutOrientation={layoutOrientation}
                onLayoutOrientationChange={handleLayoutOrientationChange}
                className="h-full"
              />
            </div>
          </TabsContent>

          <TabsContent value="configuration" className="space-y-6 mt-6">
            <div>
              <Input
                label="Timeout (seconds) *"
                type="number"
                value={formData.timeoutSeconds}
                onChange={(e) => handleInputChange('timeoutSeconds', parseInt(e.target.value) || 3600)}
                min={60}
                max={86400}
                error={errors.timeoutSeconds}
              />
              <p className="text-sm text-theme-muted mt-1">
                Maximum time allowed for workflow execution (60 seconds - 24 hours)
              </p>
            </div>

            <div>
              <Input
                label="Max Parallel Nodes"
                type="number"
                value={formData.configuration.max_parallel_nodes}
                onChange={(e) => handleInputChange('configuration', {
                  ...formData.configuration,
                  max_parallel_nodes: parseInt(e.target.value) || 5
                })}
                min={1}
                max={20}
              />
              <p className="text-sm text-theme-muted mt-1">
                Maximum number of nodes that can execute simultaneously in parallel mode
              </p>
            </div>

            <div>
              <EnhancedSelect
                label="Error Handling"
                value={formData.configuration.error_handling}
                onChange={(value) => handleInputChange('configuration', {
                  ...formData.configuration,
                  error_handling: value
                })}
                options={[
                  { value: 'stop', label: 'Stop on Error' },
                  { value: 'continue', label: 'Continue on Error' },
                  { value: 'retry', label: 'Retry on Error' }
                ]}
              />
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </Modal>
  );
};