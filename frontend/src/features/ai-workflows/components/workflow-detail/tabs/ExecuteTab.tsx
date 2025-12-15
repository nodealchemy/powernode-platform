import React from 'react';
import { Play, Send, AlertCircle } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { AiWorkflow } from '@/shared/types/workflow';
import { suggestedPrompts } from '../utils/workflowDetailUtils';

interface ExecuteTabProps {
  workflow: AiWorkflow;
  chatInput: string;
  additionalParams: Record<string, unknown>;
  isExecuting: boolean;
  showAdvanced: boolean;
  onChatInputChange: (value: string) => void;
  onAdditionalParamsChange: (params: Record<string, unknown>) => void;
  onToggleAdvanced: () => void;
  onExecute: () => void;
}

export const ExecuteTab: React.FC<ExecuteTabProps> = ({
  workflow,
  chatInput,
  additionalParams,
  isExecuting,
  showAdvanced,
  onChatInputChange,
  onAdditionalParamsChange,
  onToggleAdvanced,
  onExecute
}) => {
  return (
    <Card>
      <CardContent className="space-y-4">
        {/* Main chat input */}
        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            What would you like to create?
          </label>
          <div className="relative">
            <Textarea
              value={chatInput}
              onChange={(e) => onChatInputChange(e.target.value)}
              placeholder="Describe what you want the workflow to do..."
              className="min-h-[100px] pr-12"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && e.ctrlKey) {
                  onExecute();
                }
              }}
            />
            <div className="absolute bottom-3 right-3">
              <Button
                size="sm"
                variant="ghost"
                onClick={onExecute}
                disabled={isExecuting || !chatInput.trim()}
                title="Execute (Ctrl+Enter)"
              >
                <Send className="h-4 w-4" />
              </Button>
            </div>
          </div>
          <div className="text-xs text-theme-text-secondary mt-1">
            Press Ctrl+Enter to execute
          </div>
        </div>

        {/* Suggested prompts */}
        {suggestedPrompts.length > 0 && !chatInput && (
          <div>
            <label className="block text-xs font-medium text-theme-text-secondary mb-1">
              Suggestions:
            </label>
            <div className="flex flex-wrap gap-2">
              {suggestedPrompts.map((prompt, index) => (
                <button
                  key={index}
                  onClick={() => onChatInputChange(prompt)}
                  className="px-3 py-1.5 text-xs bg-theme-surface-secondary rounded-lg
                           text-theme-text-secondary hover:text-theme-text-primary
                           hover:bg-theme-surface-elevated transition-colors"
                >
                  {prompt}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Advanced parameters */}
        <div>
          <button
            onClick={onToggleAdvanced}
            className="text-sm text-theme-primary hover:text-theme-primary-dark transition-colors"
          >
            {showAdvanced ? '− Hide' : '+ Show'} Advanced Options
          </button>

          {showAdvanced && (
            <div className="mt-2 p-3 bg-theme-surface-secondary rounded-lg space-y-2">
              <div className="text-sm text-theme-text-secondary mb-1">
                Add specific parameters for the workflow:
              </div>

              {workflow.input_schema && Object.keys(workflow.input_schema).length > 0 ? (
                Object.entries(workflow.input_schema).map(([key, _schema]: [string, unknown]) => (
                  <div key={key}>
                    <label className="block text-sm font-medium text-theme-text-primary mb-1">
                      {key.charAt(0).toUpperCase() + key.slice(1).replace(/_/g, ' ')}
                    </label>
                    <Input
                      value={(additionalParams[key] as string) || ''}
                      onChange={(e) => onAdditionalParamsChange({
                        ...additionalParams,
                        [key]: e.target.value
                      })}
                      placeholder={`Enter ${key}`}
                    />
                  </div>
                ))
              ) : (
                <>
                  <div>
                    <label className="block text-sm font-medium text-theme-text-primary mb-1">
                      Max Tokens
                    </label>
                    <Input
                      type="number"
                      value={(additionalParams.max_tokens as number) || ''}
                      onChange={(e) => onAdditionalParamsChange({
                        ...additionalParams,
                        max_tokens: parseInt(e.target.value) || undefined
                      })}
                      placeholder="1500"
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-text-primary mb-1">
                      Temperature
                    </label>
                    <Input
                      type="number"
                      step="0.1"
                      min="0"
                      max="2"
                      value={(additionalParams.temperature as number) || ''}
                      onChange={(e) => onAdditionalParamsChange({
                        ...additionalParams,
                        temperature: parseFloat(e.target.value) || undefined
                      })}
                      placeholder="0.7"
                    />
                  </div>
                </>
              )}
            </div>
          )}
        </div>

        {/* Workflow info */}
        <div className="p-3 bg-theme-info/10 rounded-lg flex items-start gap-2">
          <AlertCircle className="h-4 w-4 text-theme-info mt-0.5" />
          <div className="text-sm text-theme-text-secondary">
            This workflow will process your input through {workflow.stats?.nodes_count || workflow.nodes?.length || 0} nodes
            {workflow.execution_mode && ` in ${workflow.execution_mode} mode`}.
          </div>
        </div>

        {/* Action buttons */}
        <div className="flex justify-end gap-3">
          <Button
            variant="primary"
            onClick={onExecute}
            disabled={isExecuting || (!chatInput.trim() && Object.keys(additionalParams).length === 0)}
            className="transition-all duration-200 hover:scale-105 active:scale-95"
          >
            <div className="flex items-center">
              {isExecuting ? (
                <>
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2" />
                  <span className="animate-in fade-in duration-200">Executing...</span>
                </>
              ) : (
                <>
                  <Play className="h-4 w-4 mr-2 transition-transform duration-200 group-hover:scale-110" />
                  <span>Execute Workflow</span>
                </>
              )}
            </div>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};
