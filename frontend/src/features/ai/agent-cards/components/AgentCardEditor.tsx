import React from 'react';
import {
  Bot,
  Save,
  X,
  CheckCircle,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { cn } from '@/shared/utils/cn';
import type { AgentCard } from '@/shared/services/ai/types/a2a-types';
import { useAgentCardForm } from './useAgentCardForm';
import { CardBasicFields } from './CardBasicFields';
import { SkillEditor } from './SkillEditor';
import { CardPreview } from './CardPreview';

interface AgentCardEditorProps {
  cardId?: string;
  onSave?: (card: AgentCard) => void;
  onCancel?: () => void;
  className?: string;
}

export const AgentCardEditor: React.FC<AgentCardEditorProps> = ({
  cardId,
  onSave,
  onCancel,
  className,
}) => {
  const form = useAgentCardForm({ cardId, onSave });

  if (form.loading) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading agent card..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className={cn('space-y-6', className)}>
      {/* Header */}
      <Card>
        <CardHeader
          title={form.isEditMode ? 'Edit Agent Card' : 'Create Agent Card'}
          icon={<Bot className="h-5 w-5" />}
          action={
            <div className="flex items-center gap-2">
              <Button variant="outline" size="sm" onClick={onCancel}>
                <X className="h-4 w-4 mr-2" />
                Cancel
              </Button>
              <Button variant="outline" size="sm" onClick={form.handleValidate} disabled={form.validating}>
                <CheckCircle className="h-4 w-4 mr-2" />
                {form.validating ? 'Validating...' : 'Validate'}
              </Button>
              <Button variant="primary" size="sm" onClick={form.handleSave} disabled={form.saving}>
                <Save className="h-4 w-4 mr-2" />
                {form.saving ? 'Saving...' : 'Save'}
              </Button>
            </div>
          }
        />
      </Card>

      {form.error && <ErrorAlert message={form.error} />}

      <CardPreview validationResult={form.validationResult} />

      <CardBasicFields
        name={form.name}
        onNameChange={form.setName}
        description={form.description}
        onDescriptionChange={form.setDescription}
        visibility={form.visibility}
        onVisibilityChange={form.setVisibility}
        endpointUrl={form.endpointUrl}
        onEndpointUrlChange={form.setEndpointUrl}
        selectedAgentId={form.selectedAgentId}
        onAgentChange={form.setSelectedAgentId}
        agents={form.agents}
        isEditMode={form.isEditMode}
      />

      <SkillEditor
        skills={form.skills}
        onAddSkill={form.handleAddSkill}
        onRemoveSkill={form.handleRemoveSkill}
        onSkillChange={form.handleSkillChange}
      />

      <CardPreview
        streamingEnabled={form.streamingEnabled}
        onStreamingChange={form.setStreamingEnabled}
        pushNotificationsEnabled={form.pushNotificationsEnabled}
        onPushNotificationsChange={form.setPushNotificationsEnabled}
        authSchemes={form.authSchemes}
        onAuthSchemeToggle={form.handleAuthSchemeToggle}
      />
    </div>
  );
};

export default AgentCardEditor;
