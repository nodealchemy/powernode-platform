import React, { useState, useCallback, useMemo } from 'react';
import {
  Calendar,
  Clock,
  RefreshCw,
  Webhook,
  AlertCircle,
  Play,
  Settings,
  Check,
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { cn } from '@/shared/utils/cn';
import type {
  RalphSchedulingMode,
  RalphScheduleConfig,
} from '@/shared/services/ai/types/ralph-types';

interface RalphLoopScheduleConfigProps {
  schedulingMode: RalphSchedulingMode;
  scheduleConfig?: RalphScheduleConfig;
  onChange: (mode: RalphSchedulingMode, config: RalphScheduleConfig) => void;
  onCancel?: () => void;
  className?: string;
}

const schedulingModeConfig: Record<RalphSchedulingMode, {
  label: string;
  description: string;
  icon: React.FC<{ className?: string }>;
}> = {
  manual: {
    label: 'Manual',
    description: 'Start and run iterations manually',
    icon: Play,
  },
  scheduled: {
    label: 'Scheduled',
    description: 'Run on a cron-based schedule',
    icon: Calendar,
  },
  continuous: {
    label: 'Continuous',
    description: 'Run at fixed intervals',
    icon: RefreshCw,
  },
  event_triggered: {
    label: 'Event Triggered',
    description: 'Trigger via webhook',
    icon: Webhook,
  },
  autonomous: {
    label: 'Autonomous',
    description: 'Self-directed duty cycle with configurable frequency',
    icon: RefreshCw,
  },
};

const timezoneOptions = [
  'UTC',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Asia/Singapore',
  'Australia/Sydney',
];

const cronPresets = [
  { label: 'Every hour', value: '0 * * * *' },
  { label: 'Every 6 hours', value: '0 */6 * * *' },
  { label: 'Daily at 9am', value: '0 9 * * *' },
  { label: 'Weekdays at 9am', value: '0 9 * * 1-5' },
  { label: 'Weekly (Monday 9am)', value: '0 9 * * 1' },
  { label: 'Custom', value: 'custom' },
];

export const RalphLoopScheduleConfig: React.FC<RalphLoopScheduleConfigProps> = ({
  schedulingMode: initialMode,
  scheduleConfig: initialConfig = {},
  onChange,
  onCancel,
  className,
}) => {
  const [mode, setMode] = useState<RalphSchedulingMode>(initialMode);
  const [config, setConfig] = useState<RalphScheduleConfig>(initialConfig);
  const [cronPreset, setCronPreset] = useState<string>(
    cronPresets.find(p => p.value === initialConfig.cron_expression)?.value || 'custom'
  );

  const updateConfig = useCallback((updates: Partial<RalphScheduleConfig>) => {
    setConfig(prev => ({ ...prev, ...updates }));
  }, []);

  const handleCronPresetChange = useCallback((preset: string) => {
    setCronPreset(preset);
    if (preset !== 'custom') {
      updateConfig({ cron_expression: preset });
    }
  }, [updateConfig]);

  const handleSave = useCallback(() => {
    onChange(mode, config);
  }, [mode, config, onChange]);

  // Parse cron expression to human-readable format
  const cronDescription = useMemo(() => {
    const expr = config.cron_expression;
    if (!expr) return null;

    const preset = cronPresets.find(p => p.value === expr);
    if (preset && preset.value !== 'custom') {
      return preset.label;
    }

    try {
      const parts = expr.split(' ');
      if (parts.length !== 5) return 'Invalid cron expression';
      return `At minute ${parts[0]} of hour ${parts[1]}, day ${parts[2]}, month ${parts[3]}, weekday ${parts[4]}`;
    } catch (_error) {
      return 'Invalid cron expression';
    }
  }, [config.cron_expression]);

  return (
    <Card className={cn('border-theme-border-primary', className)}>
      <CardHeader
        title="Schedule Configuration"
        icon={<Settings className="w-4 h-4 text-theme-text-secondary" />}
        className="pb-3"
      />
      <CardContent className="space-y-4">
        {/* Scheduling Mode Selection */}
        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-2">
            Scheduling Mode
          </label>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            {(Object.keys(schedulingModeConfig) as RalphSchedulingMode[]).map((modeKey) => {
              const modeConfig = schedulingModeConfig[modeKey];
              const Icon = modeConfig.icon;
              const isSelected = mode === modeKey;

              return (
                <button
                  key={modeKey}
                  type="button"
                  onClick={() => setMode(modeKey)}
                  className={cn(
                    'relative flex flex-col items-center p-3 rounded-lg border-2 transition-all',
                    'hover:border-theme-brand-primary/50',
                    isSelected
                      ? 'border-theme-brand-primary bg-theme-brand-primary/20 ring-2 ring-theme-brand-primary/30'
                      : 'border-theme-border-primary bg-theme-bg-primary'
                  )}
                >
                  {isSelected && (
                    <div className="absolute top-1 right-1 w-4 h-4 rounded-full bg-theme-brand-primary flex items-center justify-center">
                      <Check className="w-2.5 h-2.5 text-white" />
                    </div>
                  )}
                  <Icon className={cn(
                    'w-5 h-5 mb-1',
                    isSelected ? 'text-theme-brand-primary' : 'text-theme-text-secondary'
                  )} />
                  <span className={cn(
                    'text-xs font-medium',
                    isSelected ? 'text-theme-brand-primary' : 'text-theme-text-primary'
                  )}>
                    {modeConfig.label}
                  </span>
                </button>
              );
            })}
          </div>
          <p className="mt-2 text-xs text-theme-text-secondary">
            {schedulingModeConfig[mode].description}
          </p>
        </div>

        {/* Scheduled Mode Options */}
        {mode === 'scheduled' && (
          <div className="space-y-3 pt-3 border-t border-theme-border-primary">
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Schedule Preset
              </label>
              <Select
                value={cronPreset}
                onChange={(value) => handleCronPresetChange(value)}
              >
                {cronPresets.map((preset) => (
                  <option key={preset.value} value={preset.value}>
                    {preset.label}
                  </option>
                ))}
              </Select>
            </div>

            {cronPreset === 'custom' && (
              <div>
                <label className="block text-sm font-medium text-theme-text-primary mb-1">
                  Cron Expression
                </label>
                <Input
                  type="text"
                  placeholder="0 9 * * 1-5"
                  value={config.cron_expression || ''}
                  onChange={(e) => updateConfig({ cron_expression: e.target.value })}
                />
                <p className="mt-1 text-xs text-theme-text-secondary">
                  Format: minute hour day month weekday (e.g., 0 9 * * 1-5 = 9am weekdays)
                </p>
              </div>
            )}

            {cronDescription && (
              <div className="flex items-center gap-2 p-2 rounded-lg bg-theme-bg-secondary">
                <Clock className="w-4 h-4 text-theme-text-secondary" />
                <span className="text-sm text-theme-text-primary">{cronDescription}</span>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Timezone
              </label>
              <Select
                value={config.timezone || 'UTC'}
                onChange={(value) => updateConfig({ timezone: value })}
              >
                {timezoneOptions.map((tz) => (
                  <option key={tz} value={tz}>{tz}</option>
                ))}
              </Select>
            </div>
          </div>
        )}

        {/* Continuous Mode Options */}
        {mode === 'continuous' && (
          <div className="space-y-3 pt-3 border-t border-theme-border-primary">
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Interval (seconds)
              </label>
              <Input
                type="number"
                min={60}
                max={86400}
                placeholder="300"
                value={config.iteration_interval_seconds || ''}
                onChange={(e) => updateConfig({
                  iteration_interval_seconds: parseInt(e.target.value) || undefined,
                })}
              />
              <p className="mt-1 text-xs text-theme-text-secondary">
                Minimum 60 seconds. Recommended: 300 (5 minutes) or more.
              </p>
            </div>
          </div>
        )}

        {/* Event Triggered Mode Info */}
        {mode === 'event_triggered' && (
          <div className="p-3 rounded-lg bg-theme-bg-secondary border border-theme-border-primary">
            <div className="flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-theme-status-info mt-0.5" />
              <div>
                <p className="text-sm text-theme-text-primary font-medium">
                  Webhook URL will be generated
                </p>
                <p className="text-xs text-theme-text-secondary mt-1">
                  After saving, a unique webhook URL will be created. Use this URL to trigger
                  iterations from external systems like Git hooks or CI/CD pipelines.
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Common Options (for non-manual modes) */}
        {mode !== 'manual' && (
          <div className="space-y-3 pt-3 border-t border-theme-border-primary">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-sm font-medium text-theme-text-primary mb-1">
                  Start Date (Optional)
                </label>
                <Input
                  type="datetime-local"
                  value={config.start_at?.slice(0, 16) || ''}
                  onChange={(e) => updateConfig({
                    start_at: e.target.value ? new Date(e.target.value).toISOString() : undefined,
                  })}
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-text-primary mb-1">
                  End Date (Optional)
                </label>
                <Input
                  type="datetime-local"
                  value={config.end_at?.slice(0, 16) || ''}
                  onChange={(e) => updateConfig({
                    end_at: e.target.value ? new Date(e.target.value).toISOString() : undefined,
                  })}
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Max Iterations Per Day
              </label>
              <Input
                type="number"
                min={1}
                max={10000}
                placeholder="No limit"
                value={config.max_iterations_per_day || ''}
                onChange={(e) => updateConfig({
                  max_iterations_per_day: parseInt(e.target.value) || undefined,
                })}
              />
            </div>

            <div className="space-y-2">
              <label className="block text-sm font-medium text-theme-text-primary">
                Failure Handling
              </label>
              <div className="space-y-2">
                <Checkbox
                  checked={config.pause_on_failure ?? true}
                  onCheckedChange={(checked) => updateConfig({
                    pause_on_failure: checked as boolean,
                  })}
                  label="Pause schedule on failure"
                />
                <Checkbox
                  checked={config.retry_on_failure ?? false}
                  onCheckedChange={(checked) => updateConfig({
                    retry_on_failure: checked as boolean,
                  })}
                  label="Retry on failure"
                />
              </div>
            </div>

            {config.retry_on_failure && (
              <div>
                <label className="block text-sm font-medium text-theme-text-primary mb-1">
                  Retry Delay (seconds)
                </label>
                <Input
                  type="number"
                  min={10}
                  max={3600}
                  placeholder="60"
                  value={config.retry_delay_seconds || ''}
                  onChange={(e) => updateConfig({
                    retry_delay_seconds: parseInt(e.target.value) || undefined,
                  })}
                />
              </div>
            )}

            <Checkbox
              checked={config.skip_if_running ?? true}
              onCheckedChange={(checked) => updateConfig({
                skip_if_running: checked as boolean,
              })}
              label="Skip execution if loop is already running"
            />
          </div>
        )}

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-4 border-t border-theme-border-primary">
          {onCancel && (
            <Button variant="outline" size="sm" onClick={onCancel}>
              Cancel
            </Button>
          )}
          <Button variant="primary" size="sm" onClick={handleSave}>
            Save Schedule
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default RalphLoopScheduleConfig;
