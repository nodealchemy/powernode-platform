import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { AlertTriangle, RefreshCw, Layers, Repeat, Timer, Shield } from 'lucide-react';

export interface LoopPreventionSettings {
  max_node_visits?: number;
  max_validation_failures?: number;
  max_sub_workflow_depth?: number;
  max_requeues_per_node?: number;
  max_total_node_executions?: number;
  warn_on_approach?: boolean;
}

interface LoopPreventionConfigProps {
  settings: LoopPreventionSettings;
  onChange: (settings: LoopPreventionSettings) => void;
  isEditMode: boolean;
}

const DEFAULT_SETTINGS: Required<LoopPreventionSettings> = {
  max_node_visits: 10,
  max_validation_failures: 5,
  max_sub_workflow_depth: 5,
  max_requeues_per_node: 100,
  max_total_node_executions: 1000,
  warn_on_approach: true,
};

export const LoopPreventionConfig: React.FC<LoopPreventionConfigProps> = ({
  settings,
  onChange,
  isEditMode
}) => {
  const mergedSettings = { ...DEFAULT_SETTINGS, ...settings };

  const handleChange = (key: keyof LoopPreventionSettings, value: number | boolean) => {
    onChange({ ...settings, [key]: value });
  };

  const configItems = [
    {
      key: 'max_node_visits' as const,
      label: 'Max Node Visits',
      description: 'Maximum times any single node can be executed in one workflow run. Prevents feedback loops that revisit nodes indefinitely.',
      icon: RefreshCw,
      min: 1,
      max: 100,
      type: 'number' as const,
    },
    {
      key: 'max_validation_failures' as const,
      label: 'Max Validation Failures',
      description: 'Maximum consecutive validation/quality check failures before aborting. Prevents retry loops where validation never passes.',
      icon: AlertTriangle,
      min: 1,
      max: 50,
      type: 'number' as const,
    },
    {
      key: 'max_sub_workflow_depth' as const,
      label: 'Max Sub-Workflow Depth',
      description: 'Maximum depth for nested sub-workflow calls. Prevents workflow A → B → A recursive loops.',
      icon: Layers,
      min: 1,
      max: 20,
      type: 'number' as const,
    },
    {
      key: 'max_requeues_per_node' as const,
      label: 'Max Requeues Per Node',
      description: 'Maximum times a node can be requeued waiting for prerequisites. Prevents deadlock scenarios.',
      icon: Timer,
      min: 10,
      max: 1000,
      type: 'number' as const,
    },
    {
      key: 'max_total_node_executions' as const,
      label: 'Max Total Executions',
      description: 'Maximum total node executions across entire workflow run. Ultimate safeguard against runaway workflows.',
      icon: Repeat,
      min: 10,
      max: 10000,
      type: 'number' as const,
    },
  ];

  return (
    <Card className="mt-4">
      <CardTitle className="flex items-center gap-2">
        <Shield className="w-5 h-5" />
        Loop Prevention Settings
      </CardTitle>
      <CardContent className="space-y-4">
        <p className="text-sm text-theme-muted">
          Configure limits to prevent endless loops in workflow execution. These safeguards protect against
          runaway workflows that could consume resources indefinitely.
        </p>

        <div className="grid gap-4">
          {configItems.map((item) => {
            const Icon = item.icon;
            const value = mergedSettings[item.key] as number;

            return (
              <div key={item.key} className="border border-theme rounded-lg p-3">
                <div className="flex items-start gap-3">
                  <Icon className="w-5 h-5 text-theme-muted mt-0.5 flex-shrink-0" />
                  <div className="flex-1">
                    <label className="text-sm font-medium text-theme-primary block">
                      {item.label}
                    </label>
                    <p className="text-xs text-theme-muted mt-0.5 mb-2">
                      {item.description}
                    </p>
                    {isEditMode ? (
                      <Input
                        type="number"
                        value={value}
                        onChange={(e) => handleChange(item.key, parseInt(e.target.value) || item.min)}
                        min={item.min}
                        max={item.max}
                        className="w-32"
                      />
                    ) : (
                      <span className="text-sm font-medium text-theme-primary">
                        {value.toLocaleString()}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            );
          })}

          {/* Warn on Approach Toggle */}
          <div className="border border-theme rounded-lg p-3">
            <div className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-theme-muted mt-0.5 flex-shrink-0" />
              <div className="flex-1">
                <label className="text-sm font-medium text-theme-primary block">
                  Warn on Approach
                </label>
                <p className="text-xs text-theme-muted mt-0.5 mb-2">
                  Issue warnings when execution approaches 80% of any limit. Helps identify potential issues before they cause failures.
                </p>
                {isEditMode ? (
                  <Checkbox
                    checked={mergedSettings.warn_on_approach}
                    onCheckedChange={(checked: boolean) => handleChange('warn_on_approach', checked)}
                  />
                ) : (
                  <span className="text-sm font-medium text-theme-primary">
                    {mergedSettings.warn_on_approach ? 'Enabled' : 'Disabled'}
                  </span>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Summary/Tips */}
        <div className="bg-theme-surface-secondary rounded-lg p-3 mt-4">
          <h4 className="text-sm font-medium text-theme-primary mb-2">Common Scenarios Protected Against:</h4>
          <ul className="text-xs text-theme-muted space-y-1">
            <li>• <strong>Feedback Loops:</strong> Node A → Node B → Node A (limited by Max Node Visits)</li>
            <li>• <strong>Quality Check Retries:</strong> Validation fails, retry, fails again... (limited by Max Validation Failures)</li>
            <li>• <strong>Recursive Sub-Workflows:</strong> Workflow A calls Workflow B which calls A (limited by Max Sub-Workflow Depth)</li>
            <li>• <strong>Deadlocks:</strong> Nodes waiting for prerequisites that never complete (limited by Max Requeues)</li>
            <li>• <strong>Runaway Execution:</strong> Workflows that keep executing nodes indefinitely (limited by Max Total Executions)</li>
          </ul>
        </div>
      </CardContent>
    </Card>
  );
};

export default LoopPreventionConfig;
