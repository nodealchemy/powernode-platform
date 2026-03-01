import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import type { AiAgent } from '@/shared/types/ai';

interface CardBasicFieldsProps {
  name: string;
  description: string;
  visibility: 'private' | 'internal' | 'public';
  endpointUrl: string;
  selectedAgentId: string;
  agents: AiAgent[];
  isEditMode: boolean;
  onNameChange: (value: string) => void;
  onDescriptionChange: (value: string) => void;
  onVisibilityChange: (value: 'private' | 'internal' | 'public') => void;
  onEndpointUrlChange: (value: string) => void;
  onAgentChange: (value: string) => void;
}

export const CardBasicFields: React.FC<CardBasicFieldsProps> = ({
  name,
  description,
  visibility,
  endpointUrl,
  selectedAgentId,
  agents,
  isEditMode,
  onNameChange,
  onDescriptionChange,
  onVisibilityChange,
  onEndpointUrlChange,
  onAgentChange,
}) => (
  <Card>
    <CardHeader title="Basic Information" />
    <CardContent className="space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Name <span className="text-theme-danger">*</span>
          </label>
          <Input
            value={name}
            onChange={(e) => onNameChange(e.target.value)}
            placeholder="My Agent Card"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Visibility
          </label>
          <Select
            value={visibility}
            onChange={(value) => onVisibilityChange(value as 'private' | 'internal' | 'public')}
          >
            <option value="private">Private - Only you</option>
            <option value="internal">Internal - Your organization</option>
            <option value="public">Public - Anyone</option>
          </Select>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-secondary mb-1">
          Description
        </label>
        <textarea
          value={description}
          onChange={(e) => onDescriptionChange(e.target.value)}
          placeholder="What does this agent do?"
          className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          rows={3}
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {!isEditMode && (
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Link to Agent
            </label>
            <Select
              value={selectedAgentId}
              onChange={(value) => onAgentChange(value)}
            >
              <option value="">No linked agent</option>
              {agents.map((agent) => (
                <option key={agent.id} value={agent.id}>
                  {agent.name}
                </option>
              ))}
            </Select>
          </div>
        )}
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            External Endpoint URL
          </label>
          <Input
            value={endpointUrl}
            onChange={(e) => onEndpointUrlChange(e.target.value)}
            placeholder="https://example.com/.well-known/agent.json"
          />
        </div>
      </div>
    </CardContent>
  </Card>
);
