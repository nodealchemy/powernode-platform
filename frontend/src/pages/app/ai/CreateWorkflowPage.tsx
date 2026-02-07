import React, { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Save,
  Play,
  Plus,
  X,
  FileText,
  GitBranch,
  Zap,
  AlertCircle
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Badge } from '@/shared/components/ui/Badge';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { WorkflowBuilderProvider } from '@/shared/components/workflow/WorkflowBuilder';
import { workflowsApi, CreateWorkflowRequest } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { logger } from '@/shared/utils/logger';
import { AiWorkflowNode, AiWorkflowEdge } from '@/shared/types/workflow';

interface WorkflowFormData {
  name: string;
  description: string;
  status: 'draft' | 'published';
  visibility: 'private' | 'account' | 'public';
  execution_mode: 'sequential' | 'parallel' | 'conditional';
  timeout_seconds: number;
  tags: string[];
   
  configuration: Record<string, any>;
  nodes: AiWorkflowNode[];
  edges: AiWorkflowEdge[];
}

export const CreateWorkflowPage: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

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
    execution_mode: 'sequential',
    timeout_seconds: 3600,
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

  // Check permissions
  const canCreateWorkflows = currentUser?.permissions?.includes('ai.workflows.create') || false;

  // Validate form
  const validateForm = useCallback(() => {
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

    if (formData.timeout_seconds < 60) {
      newErrors.timeout_seconds = 'Timeout must be at least 60 seconds';
    } else if (formData.timeout_seconds > 86400) {
      newErrors.timeout_seconds = 'Timeout cannot exceed 24 hours (86400 seconds)';
    }

    // Validate workflow has at least one node
    if (formData.nodes.length === 0) {
      newErrors.workflow = 'Workflow must have at least one node';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }, [formData]);

  // Handle form field changes
   
  const handleInputChange = useCallback((field: keyof WorkflowFormData, value: unknown) => {
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
  }, [errors]);

  // Handle configuration changes
   
  const handleConfigChange = useCallback((key: string, value: unknown) => {
    setFormData(prev => ({
      ...prev,
      configuration: {
        ...prev.configuration,
        [key]: value
      }
    }));
  }, []);

  // Handle workflow builder data
   
  const handleWorkflowData = useCallback((workflowData: {
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
  }, [errors.workflow]);

  // Add tag
  const addTag = useCallback(() => {
    if (newTag.trim() && !formData.tags.includes(newTag.trim())) {
      handleInputChange('tags', [...formData.tags, newTag.trim()]);
      setNewTag('');
    }
  }, [newTag, formData.tags, handleInputChange]);

  // Remove tag
  const removeTag = useCallback((tagToRemove: string) => {
    handleInputChange('tags', formData.tags.filter(tag => tag !== tagToRemove));
  }, [formData.tags, handleInputChange]);

  // Handle key press for tag input
  const handleTagKeyPress = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      addTag();
    }
  }, [addTag]);

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

      const requestData: CreateWorkflowRequest = {
        name: formData.name.trim(),
        description: formData.description.trim(),
        status: saveAs,
        visibility: formData.visibility,
        execution_mode: formData.execution_mode,
        timeout_seconds: formData.timeout_seconds,
        tags: formData.tags,
        configuration: {
          ...formData.configuration,
          execution_mode: formData.execution_mode,
          timeout_seconds: formData.timeout_seconds
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

      // Navigate to the new workflow
      navigate(`/app/ai/workflows/${response.id}`);
    } catch (error) {
      logger.error('Failed to create workflow', error);
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: 'Failed to create workflow. Please try again.'
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  // Get execution mode icon
  const getExecutionModeIcon = (mode: string) => {
    switch (mode) {
      case 'sequential': return FileText;
      case 'parallel': return GitBranch;
      case 'conditional': return Zap;
      default: return FileText;
    }
  };

  if (!canCreateWorkflows) {
    return (
      <PageContainer
        title="Access Denied"
        description="You don't have permission to create workflows"
      >
        <Card>
          <CardContent className="text-center py-8">
            <AlertCircle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">Access Denied</h3>
            <p className="text-theme-muted">
              You don't have permission to create workflows.
            </p>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Create New Workflow"
      description="Build an automated AI workflow for your business processes"
      breadcrumbs={[
        { label: 'AI', href: '/app/ai' },
        { label: 'Workflows', href: '/app/ai/workflows' },
        { label: 'Create' }
      ]}
      actions={[
        {
          label: 'Save as Draft',
          onClick: () => handleSubmit('draft'),
          icon: Save,
          variant: 'outline',
          disabled: isSubmitting
        },
        {
          label: 'Save & Activate',
          onClick: () => handleSubmit('published'),
          icon: Play,
          variant: 'primary',
          disabled: isSubmitting
        }
      ]}
    >
      <div className="space-y-6">
        <Tabs defaultValue="basic" className="space-y-4">
          <TabsList>
            <TabsTrigger value="basic">Basic Information</TabsTrigger>
            <TabsTrigger value="workflow">Workflow Builder</TabsTrigger>
            <TabsTrigger value="configuration">Configuration</TabsTrigger>
            <TabsTrigger value="advanced">Advanced Settings</TabsTrigger>
          </TabsList>

          <TabsContent value="basic" className="space-y-6">
            <Card>

                <CardTitle>Workflow Details</CardTitle>

              <CardContent className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Name *
                  </label>
                  <Input
                    value={formData.name}
                    onChange={(e) => handleInputChange('name', e.target.value)}
                    placeholder="Enter workflow name..."
                    error={errors.name}
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Description *
                  </label>
                  <Textarea
                    value={formData.description}
                    onChange={(e) => handleInputChange('description', e.target.value)}
                    placeholder="Describe what this workflow does..."
                    rows={3}
                    error={errors.description}
                  />
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      Visibility
                    </label>
                    <EnhancedSelect
                      value={formData.visibility}
                      onChange={(value) => handleInputChange('visibility', value)}
                      options={[
                        { value: 'private', label: 'Private (Only you)' },
                        { value: 'account', label: 'Account (Team members)' },
                        { value: 'public', label: 'Public (Everyone)' }
                      ]}
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      Execution Mode
                    </label>
                    <EnhancedSelect
                      value={formData.execution_mode}
                      onChange={(value) => handleInputChange('execution_mode', value)}
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
                      renderOption={(option) => {
                        const Icon = getExecutionModeIcon(option.value);
                        return (
                          <div className="flex items-center gap-2">
                            <Icon className="h-4 w-4" />
                            <div>
                              <div className="font-medium">{option.label}</div>
                              {option.description && (
                                <div className="text-sm text-theme-muted">{option.description}</div>
                              )}
                            </div>
                          </div>
                        );
                      }}
                    />
                  </div>
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
                      <Plus className="h-4 w-4" />
                    </Button>
                  </div>
                  {formData.tags.length > 0 && (
                    <div className="flex flex-wrap gap-2">
                      {formData.tags.map(tag => (
                        <Badge key={tag} variant="outline" className="flex items-center gap-1">
                          {tag}
                          <button
                            type="button"
                            onClick={() => removeTag(tag)}
                            className="hover:text-theme-error"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </Badge>
                      ))}
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="workflow" className="space-y-6">
            <Card>

                <CardTitle>Visual Workflow Builder</CardTitle>

              <CardContent>
                {errors.workflow && (
                  <div className="mb-4 p-4 bg-theme-error-background text-theme-error text-sm border border-theme-error rounded-lg">
                    {errors.workflow}
                  </div>
                )}
                <div className="h-96 border border-theme rounded-lg">
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
                <p className="text-sm text-theme-muted mt-2">
                  Build your workflow by dragging nodes from the palette and connecting them. 
                  Configure each node by clicking on it.
                </p>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="configuration" className="space-y-6">
            <Card>

                <CardTitle>Execution Configuration</CardTitle>

              <CardContent className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Timeout (seconds) *
                  </label>
                  <Input
                    type="number"
                    value={formData.timeout_seconds}
                    onChange={(e) => handleInputChange('timeout_seconds', parseInt(e.target.value) || 3600)}
                    min={60}
                    max={86400}
                    error={errors.timeout_seconds}
                  />
                  <p className="text-sm text-theme-muted mt-1">
                    Maximum time allowed for workflow execution (60 seconds - 24 hours)
                  </p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Max Parallel Nodes
                  </label>
                  <Input
                    type="number"
                    value={formData.configuration.max_parallel_nodes}
                    onChange={(e) => handleConfigChange('max_parallel_nodes', parseInt(e.target.value) || 5)}
                    min={1}
                    max={20}
                  />
                  <p className="text-sm text-theme-muted mt-1">
                    Maximum number of nodes that can execute simultaneously in parallel mode
                  </p>
                </div>

                <div className="space-y-3">
                  <Checkbox
                    label="Auto Retry on Failure"
                    checked={formData.configuration.auto_retry}
                    onCheckedChange={(checked) => handleConfigChange('auto_retry', checked)}
                  />

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      Error Handling
                    </label>
                    <EnhancedSelect
                      value={formData.configuration.error_handling}
                      onChange={(value) => handleConfigChange('error_handling', value)}
                      options={[
                        { value: 'stop', label: 'Stop on Error' },
                        { value: 'continue', label: 'Continue on Error' },
                        { value: 'retry', label: 'Retry on Error' }
                      ]}
                    />
                  </div>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="advanced" className="space-y-6">
            <Card>

                <CardTitle>Notification Settings</CardTitle>

              <CardContent className="space-y-4">
                <div className="space-y-3">
                  <Checkbox
                    label="Notify on Completion"
                    checked={formData.configuration.notifications?.on_completion}
                    onCheckedChange={(checked) => handleConfigChange('notifications', {
                      ...formData.configuration.notifications,
                      on_completion: checked
                    })}
                  />

                  <Checkbox
                    label="Notify on Error"
                    checked={formData.configuration.notifications?.on_error}
                    onCheckedChange={(checked) => handleConfigChange('notifications', {
                      ...formData.configuration.notifications,
                      on_error: checked
                    })}
                  />
                </div>
              </CardContent>
            </Card>

            <Card>

                <CardTitle>Resource Limits</CardTitle>

              <CardContent className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Cost Limit (USD)
                  </label>
                  <Input
                    type="number"
                    step="0.01"
                    placeholder="No limit"
                    onChange={(e) => handleConfigChange('cost_limit', parseFloat(e.target.value) || null)}
                  />
                  <p className="text-sm text-theme-muted mt-1">
                    Maximum cost allowed for a single workflow execution
                  </p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Memory Limit (MB)
                  </label>
                  <Input
                    type="number"
                    placeholder="No limit"
                    onChange={(e) => handleConfigChange('memory_limit', parseInt(e.target.value) || null)}
                  />
                  <p className="text-sm text-theme-muted mt-1">
                    Maximum memory usage allowed for workflow execution
                  </p>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        {/* Submit Actions */}
        <div className="flex items-center justify-between pt-6 border-t border-theme-border">
          <Button
            variant="ghost"
            onClick={() => navigate('/app/ai/workflows')}
            disabled={isSubmitting}
          >
            Cancel
          </Button>
          <div className="flex gap-3">
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
              Save & Activate
            </Button>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};