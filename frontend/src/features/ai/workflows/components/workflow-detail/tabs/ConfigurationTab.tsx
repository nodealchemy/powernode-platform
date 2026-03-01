import React from 'react';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Select } from '@/shared/components/ui/Select';
import { AiWorkflow } from '@/shared/types/workflow';
import { LoopPreventionConfig, LoopPreventionSettings } from '@/shared/components/workflow/config/LoopPreventionConfig';

interface ConfigurationTabProps {
  workflow: AiWorkflow;
  isEditMode: boolean;
  editedWorkflow: Partial<AiWorkflow>;
  onEditChange: (updates: Partial<AiWorkflow>) => void;
}

export const ConfigurationTab: React.FC<ConfigurationTabProps> = ({
  workflow,
  isEditMode,
  editedWorkflow,
  onEditChange
}) => {
  return (
    <Card>
      <CardTitle>Workflow Configuration</CardTitle>
      <CardContent className="space-y-4">
        <div>
          <label className="text-sm font-medium text-theme-muted block mb-2">Execution Mode</label>
          {isEditMode ? (
            <Select
              value={editedWorkflow.execution_mode || workflow.execution_mode || 'sequential'}
              onChange={(value) => onEditChange({ execution_mode: value as AiWorkflow['execution_mode'] })}
            >
              <option value="sequential">Sequential</option>
              <option value="parallel">Parallel</option>
              <option value="conditional">Conditional</option>
            </Select>
          ) : (
            <p className="text-theme-primary capitalize">
              {workflow.execution_mode || 'sequential'}
            </p>
          )}
        </div>

        <div>
          <label className="text-sm font-medium text-theme-muted block mb-2">Timeout (seconds)</label>
          {isEditMode ? (
            <Input
              type="number"
              value={editedWorkflow.timeout_seconds || workflow.timeout_seconds || ''}
              onChange={(e) => onEditChange({ timeout_seconds: parseInt(e.target.value) || undefined })}
              placeholder="3600"
              min="1"
            />
          ) : (
            <p className="text-theme-primary">
              {workflow.timeout_seconds ? `${workflow.timeout_seconds} seconds` : 'Not set'}
            </p>
          )}
        </div>

        {/* Loop Prevention Settings */}
        <LoopPreventionConfig
          settings={(editedWorkflow.configuration?.loop_prevention || workflow.configuration?.loop_prevention || {}) as LoopPreventionSettings}
          onChange={(loopPreventionSettings) => {
            const currentConfig = editedWorkflow.configuration || workflow.configuration || {};
            onEditChange({
              configuration: {
                ...currentConfig,
                loop_prevention: loopPreventionSettings
              }
            });
          }}
          isEditMode={isEditMode}
        />

        <div>
          <label className="text-sm font-medium text-theme-muted block mb-2">
            Advanced Configuration (JSON)
          </label>
          {isEditMode ? (
            <Textarea
              value={editedWorkflow.configuration ? JSON.stringify(editedWorkflow.configuration, null, 2) : JSON.stringify(workflow.configuration || {}, null, 2)}
              onChange={(e) => {
                try {
                  const parsed = JSON.parse(e.target.value);
                  onEditChange({ configuration: parsed });
                } catch (_error) {
                  onEditChange({ configuration: e.target.value as unknown as Record<string, unknown> });
                }
              }}
              rows={10}
              className="font-mono text-xs"
              placeholder="{}"
            />
          ) : (
            <pre className="text-xs bg-theme-surface p-3 rounded border border-theme text-theme-primary overflow-x-auto">
              {JSON.stringify(workflow.configuration || {}, null, 2)}
            </pre>
          )}
          {isEditMode && (
            <p className="text-xs text-theme-muted mt-1">
              Enter valid JSON configuration. This is optional.
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
