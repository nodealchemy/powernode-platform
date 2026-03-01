import React, { useState, useEffect } from 'react';
import { Plus, MessageSquare, Save, X, Bot } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { agentsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { AiAgent, AiConversation } from '@/shared/types/ai';
import { getErrorMessage } from '@/shared/utils/typeGuards';

export interface ConversationCreateModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConversationCreated?: (conversation: AiConversation) => void;
  preselectedAgentId?: string;
}

interface CreateConversationFormData {
  title: string;
  ai_agent_id: string;
  description?: string;
  system_prompt?: string;
  temperature?: number;
  max_tokens?: number;
}

interface ConversationRequestData {
  ai_agent_id: string;
  title: string;
  description?: string;
  system_prompt?: string;
  temperature?: number;
  max_tokens?: number;
  metadata: Record<string, unknown>;
}

export const ConversationCreateModal: React.FC<ConversationCreateModalProps> = ({
  isOpen,
  onClose,
  onConversationCreated,
  preselectedAgentId
}) => {
  const { addNotification } = useNotifications();
  const { currentUser } = useAuth();
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentsLoading, setAgentsLoading] = useState(false);
  const [formData, setFormData] = useState<CreateConversationFormData>({
    title: '',
    ai_agent_id: preselectedAgentId || '',
    description: '',
    system_prompt: '',
    temperature: 0.7,
    max_tokens: 2000
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

  // Load available agents
  const loadAgents = async () => {
    try {
      setAgentsLoading(true);
      const response = await agentsApi.getAgents({ page: 1, per_page: 100, status: 'active' });

      // Response is PaginatedResponse<AiAgent> with items array
      const agents = response.items || [];

      setAgents(agents.filter((agent: AiAgent) => agent.status === 'active'));

      // Pre-select first agent if none is preselected and we have agents
      if (!preselectedAgentId && agents.length > 0) {
        setFormData(prev => ({
          ...prev,
          ai_agent_id: agents[0].id
        }));
      }
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load AI agents. Please try again.'
      });
    } finally {
      setAgentsLoading(false);
    }
  };

   
  useEffect(() => {
    if (isOpen) {
      loadAgents();
      // Reset form when opening
      setFormData({
        title: '',
        ai_agent_id: preselectedAgentId || '',
        description: '',
        system_prompt: '',
        temperature: 0.7,
        max_tokens: 2000
      });
      setErrors({});
    }
  }, [isOpen, preselectedAgentId]);

  const handleInputChange = (
    field: keyof CreateConversationFormData,
    value: string | number
  ) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));

    // Clear error when user starts typing
    if (errors[field]) {
      setErrors(prev => ({
        ...prev,
        [field]: ''
      }));
    }
  };

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.title?.trim()) {
      newErrors.title = 'Conversation title is required';
    } else if (formData.title.length < 3) {
      newErrors.title = 'Title must be at least 3 characters';
    } else if (formData.title.length > 100) {
      newErrors.title = 'Title must be less than 100 characters';
    }

    if (!formData.ai_agent_id) {
      newErrors.ai_agent_id = 'Please select an AI agent';
    }

    if (formData.description && formData.description.length > 500) {
      newErrors.description = 'Description must be less than 500 characters';
    }

    if (formData.system_prompt && formData.system_prompt.length > 2000) {
      newErrors.system_prompt = 'System prompt must be less than 2000 characters';
    }

    if (formData.temperature !== undefined && (formData.temperature < 0 || formData.temperature > 2)) {
      newErrors.temperature = 'Temperature must be between 0 and 2';
    }

    if (formData.max_tokens !== undefined && (formData.max_tokens < 50 || formData.max_tokens > 8000)) {
      newErrors.max_tokens = 'Max tokens must be between 50 and 8000';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm()) {
      return;
    }

    // Check authentication
    if (!currentUser) {
      addNotification({
        type: 'error',
        title: 'Authentication Required',
        message: 'You must be logged in to create conversations.'
      });
      return;
    }

    // Check permissions
    if (!currentUser.permissions?.includes('ai.conversations.create')) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to create conversations.'
      });
      return;
    }

    setIsSubmitting(true);

    try {
      const conversationData: ConversationRequestData = {
        ai_agent_id: formData.ai_agent_id,
        title: formData.title.trim(),
        metadata: {}
      };

      // Add optional fields if provided
      if (formData.description?.trim()) {
        conversationData.description = formData.description.trim();
      }

      if (formData.system_prompt?.trim()) {
        conversationData.system_prompt = formData.system_prompt.trim();
      }

      if (formData.temperature !== undefined) {
        conversationData.temperature = formData.temperature;
      }

      if (formData.max_tokens !== undefined) {
        conversationData.max_tokens = formData.max_tokens;
      }

      const conversation = await agentsApi.createConversation(
        formData.ai_agent_id,
        conversationData
      );

      addNotification({
        type: 'success',
        title: 'Conversation Created',
        message: `Conversation "${formData.title}" has been created successfully.`
      });

      // Reset form
      onClose();

      // Call callback with created conversation
      if (onConversationCreated) {
        onConversationCreated(conversation);
      }
    } catch (error) {
      let errorMessage = 'Failed to create conversation. Please try again.';
      let errorTitle = 'Creation Failed';

      // Handle different types of errors
      if (typeof error === 'object' && error !== null && 'response' in error) {
        const axiosError = error as { response?: { status: number; data?: { errors?: Record<string, string | string[]>; error?: string; message?: string } }; request?: unknown; message?: string };

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
              errorMessage = 'You do not have permission to create conversations.';
              break;
            case 422:
              errorTitle = 'Validation Error';
              if (responseData?.errors) {
                // Handle Rails validation errors
                const validationErrors = Object.entries(responseData.errors)
                  .map(([field, messages]) => `${field}: ${Array.isArray(messages) ? messages.join(', ') : String(messages)}`)
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
      onClose();
    }
  };

  // Convert agents to select options
  const agentOptions = agents.map(agent => ({
    value: agent.id,
    label: agent.name,
    description: `${agent.agent_type.replace('_', ' ')}${agent.provider?.name ? ` • ${agent.provider.name}` : ''}`
  }));

  const temperatureOptions = [
    { value: 0.1, label: '0.1 - Very Focused', description: 'Highly deterministic responses' },
    { value: 0.3, label: '0.3 - Focused', description: 'Mostly consistent responses' },
    { value: 0.5, label: '0.5 - Balanced', description: 'Good balance of creativity and consistency' },
    { value: 0.7, label: '0.7 - Creative', description: 'More varied and creative responses' },
    { value: 0.9, label: '0.9 - Very Creative', description: 'Highly creative and varied responses' },
    { value: 1.0, label: '1.0 - Maximum Creativity', description: 'Most creative responses' }
  ];

  const maxTokensOptions = [
    { value: 500, label: '500 - Short', description: 'Brief responses' },
    { value: 1000, label: '1000 - Medium', description: 'Standard length responses' },
    { value: 2000, label: '2000 - Long', description: 'Detailed responses' },
    { value: 4000, label: '4000 - Very Long', description: 'Comprehensive responses' },
    { value: 8000, label: '8000 - Maximum', description: 'Longest possible responses' }
  ];

  const modalFooter = (
    <div className="flex items-center justify-between pt-4">
      <div className="text-xs text-theme-secondary">
        {formData.title?.trim() && formData.ai_agent_id ? (
          <span className="text-theme-success">Ready to create conversation</span>
        ) : (
          <span>Please fill required fields</span>
        )}
      </div>
      <div className="flex items-center gap-3">
        <Button
          variant="outline"
          onClick={handleClose}
          disabled={isSubmitting}
          className="min-w-[100px]"
        >
          <X className="h-4 w-4 mr-2" />
          Cancel
        </Button>
        <Button
          variant="primary"
          onClick={handleSubmit}
          disabled={isSubmitting || !formData.title?.trim() || !formData.ai_agent_id || agentsLoading}
          loading={isSubmitting}
          className="min-w-[140px]"
        >
          <Save className="h-4 w-4 mr-2" />
          {isSubmitting ? 'Creating...' : 'Start Conversation'}
        </Button>
      </div>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Start New Conversation"
      subtitle="Create a new conversation with an AI agent"
      icon={<Plus className="h-6 w-6" />}
      maxWidth="lg"
      footer={modalFooter}
      closeOnBackdrop={!isSubmitting}
      closeOnEscape={!isSubmitting}
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Basic Information */}
        <div className="space-y-4">
          <div className="border-b border-theme/30 pb-3 mb-4">
            <h4 className="text-base font-semibold text-theme-primary flex items-center gap-2">
              <MessageSquare className="h-4 w-4" />
              Basic Information
            </h4>
            <p className="text-sm text-theme-secondary mt-1">Essential details for your conversation</p>
          </div>

          <div className="space-y-4">
            <Input
              label="Conversation Title"
              placeholder="Enter conversation title..."
              value={formData.title}
              onChange={(e) => handleInputChange('title', e.target.value)}
              error={errors.title}
              required
              disabled={isSubmitting}
              autoFocus
            />

            <EnhancedSelect
              label="AI Agent"
              value={formData.ai_agent_id}
              onChange={(value) => handleInputChange('ai_agent_id', value)}
              options={agentOptions}
              error={errors.ai_agent_id}
              disabled={isSubmitting || agentsLoading}
              placeholder={agentsLoading ? "Loading agents..." : "Select an AI agent..."}
            />

            <Textarea
              label="Description (Optional)"
              placeholder="Describe the purpose of this conversation..."
              value={formData.description || ''}
              onChange={(e) => handleInputChange('description', e.target.value)}
              error={errors.description}
              rows={2}
              disabled={isSubmitting}
            />
          </div>
        </div>

        {/* Advanced Configuration */}
        <div className="space-y-4">
          <div className="border-b border-theme/30 pb-3 mb-4">
            <h4 className="text-base font-semibold text-theme-primary flex items-center gap-2">
              <Bot className="h-4 w-4" />
              Advanced Configuration
            </h4>
            <p className="text-sm text-theme-secondary mt-1">Optional settings to customize AI behavior</p>
          </div>

          <Textarea
            label="System Prompt"
            placeholder="Custom system prompt to guide the AI's behavior..."
            value={formData.system_prompt || ''}
            onChange={(e) => handleInputChange('system_prompt', e.target.value)}
            error={errors.system_prompt}
            rows={3}
            disabled={isSubmitting}
          />

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <EnhancedSelect
              label="Temperature"
              value={formData.temperature?.toString()}
              onChange={(value) => handleInputChange('temperature', parseFloat(value))}
              options={temperatureOptions.map(opt => ({ ...opt, value: opt.value.toString() }))}
              disabled={isSubmitting}
            />

            <EnhancedSelect
              label="Max Tokens"
              value={formData.max_tokens?.toString()}
              onChange={(value) => handleInputChange('max_tokens', parseInt(value))}
              options={maxTokensOptions.map(opt => ({ ...opt, value: opt.value.toString() }))}
              disabled={isSubmitting}
            />
          </div>
        </div>

        {/* Info Note */}
        <div className="bg-theme-info/5 border border-theme-info/20 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <div className="flex-shrink-0 w-8 h-8 bg-theme-info/10 rounded-lg flex items-center justify-center">
              <MessageSquare className="h-4 w-4 text-theme-info" />
            </div>
            <div className="text-sm">
              <p className="text-theme-primary font-medium">What happens next?</p>
              <p className="text-theme-secondary mt-1 leading-relaxed">
                After creating the conversation, you'll be taken to the chat interface where you can start
                messaging with the AI agent. The conversation will be saved and can be resumed later.
              </p>
            </div>
          </div>
        </div>

        {/* No Agents Warning */}
        {!agentsLoading && agents.length === 0 && (
          <div className="bg-theme-warning/5 border border-theme-warning/20 rounded-xl p-4">
            <div className="flex items-start gap-3">
              <div className="flex-shrink-0 w-8 h-8 bg-theme-warning/10 rounded-lg flex items-center justify-center">
                <Bot className="h-4 w-4 text-theme-warning" />
              </div>
              <div className="text-sm">
                <p className="text-theme-primary font-medium">No Active AI Agents Found</p>
                <p className="text-theme-secondary mt-1 leading-relaxed">
                  You need to create and activate at least one AI agent before starting conversations.
                  Go to the AI Agents page to create your first agent.
                </p>
              </div>
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
};
