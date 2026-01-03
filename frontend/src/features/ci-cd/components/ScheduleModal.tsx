import React, { useState, useEffect, useMemo } from 'react';
import {
  X,
  Clock,
  Calendar,
  GitBranch,
  FileCode,
  Settings,
  Plus,
  Trash2,
  ChevronDown,
  ChevronUp,
  AlertCircle,
  Info,
  Check,
  Play,
  Pause,
  RefreshCw,
  Zap,
} from 'lucide-react';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import {
  GitPipelineScheduleDetail,
  GitRepository,
  CreateScheduleData,
} from '@/features/git-providers/types';

// ================================
// TYPES
// ================================

interface ScheduleModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  schedule?: GitPipelineScheduleDetail | null;
  repository?: {
    id: string;
    name: string;
    full_name: string;
  } | null;
  repositories: GitRepository[];
}

interface BlackoutWindow {
  id: string;
  startTime: string;
  endTime: string;
  days: number[];
}

interface InputParam {
  id: string;
  key: string;
  value: string;
}

type ScheduleMode = 'preset' | 'visual' | 'custom';
type ConcurrencyPolicy = 'skip' | 'queue' | 'replace';

// ================================
// CONSTANTS
// ================================

const SCHEDULE_PRESETS = [
  { id: 'every-15-min', label: 'Every 15 minutes', cron: '*/15 * * * *', description: 'Runs at :00, :15, :30, :45' },
  { id: 'every-hour', label: 'Every hour', cron: '0 * * * *', description: 'Runs at the top of every hour' },
  { id: 'every-2-hours', label: 'Every 2 hours', cron: '0 */2 * * *', description: 'Runs every 2 hours' },
  { id: 'every-6-hours', label: 'Every 6 hours', cron: '0 */6 * * *', description: 'Runs at midnight, 6am, noon, 6pm' },
  { id: 'nightly-2am', label: 'Nightly at 2 AM', cron: '0 2 * * *', description: 'Daily at 2:00 AM' },
  { id: 'nightly-midnight', label: 'Nightly at midnight', cron: '0 0 * * *', description: 'Daily at 12:00 AM' },
  { id: 'weekdays-9am', label: 'Weekdays at 9 AM', cron: '0 9 * * 1-5', description: 'Mon-Fri at 9:00 AM' },
  { id: 'weekdays-6pm', label: 'Weekdays at 6 PM', cron: '0 18 * * 1-5', description: 'Mon-Fri at 6:00 PM' },
  { id: 'weekly-sunday', label: 'Weekly on Sunday', cron: '0 0 * * 0', description: 'Every Sunday at midnight' },
  { id: 'weekly-monday', label: 'Weekly on Monday', cron: '0 9 * * 1', description: 'Every Monday at 9:00 AM' },
  { id: 'bi-weekly', label: 'Bi-weekly (1st & 15th)', cron: '0 0 1,15 * *', description: '1st and 15th of each month' },
  { id: 'monthly-first', label: 'Monthly (1st)', cron: '0 0 1 * *', description: 'First day of each month' },
  { id: 'monthly-last', label: 'Monthly (last weekday)', cron: '0 17 L * 1-5', description: 'Last weekday of month at 5 PM' },
  { id: 'quarterly', label: 'Quarterly', cron: '0 0 1 1,4,7,10 *', description: 'First day of each quarter' },
];

const TIMEZONES = [
  { value: 'UTC', label: 'UTC (Coordinated Universal Time)', offset: '+00:00' },
  { value: 'America/New_York', label: 'Eastern Time (US)', offset: '-05:00' },
  { value: 'America/Chicago', label: 'Central Time (US)', offset: '-06:00' },
  { value: 'America/Denver', label: 'Mountain Time (US)', offset: '-07:00' },
  { value: 'America/Los_Angeles', label: 'Pacific Time (US)', offset: '-08:00' },
  { value: 'America/Anchorage', label: 'Alaska Time', offset: '-09:00' },
  { value: 'Pacific/Honolulu', label: 'Hawaii Time', offset: '-10:00' },
  { value: 'America/Toronto', label: 'Eastern Time (Canada)', offset: '-05:00' },
  { value: 'America/Vancouver', label: 'Pacific Time (Canada)', offset: '-08:00' },
  { value: 'Europe/London', label: 'London (GMT/BST)', offset: '+00:00' },
  { value: 'Europe/Paris', label: 'Central European Time', offset: '+01:00' },
  { value: 'Europe/Berlin', label: 'Berlin (CET/CEST)', offset: '+01:00' },
  { value: 'Europe/Amsterdam', label: 'Amsterdam (CET/CEST)', offset: '+01:00' },
  { value: 'Europe/Moscow', label: 'Moscow Time', offset: '+03:00' },
  { value: 'Asia/Dubai', label: 'Dubai (GST)', offset: '+04:00' },
  { value: 'Asia/Kolkata', label: 'India Standard Time', offset: '+05:30' },
  { value: 'Asia/Singapore', label: 'Singapore Time', offset: '+08:00' },
  { value: 'Asia/Hong_Kong', label: 'Hong Kong Time', offset: '+08:00' },
  { value: 'Asia/Tokyo', label: 'Japan Standard Time', offset: '+09:00' },
  { value: 'Asia/Seoul', label: 'Korea Standard Time', offset: '+09:00' },
  { value: 'Australia/Sydney', label: 'Sydney (AEST/AEDT)', offset: '+10:00' },
  { value: 'Australia/Melbourne', label: 'Melbourne (AEST/AEDT)', offset: '+10:00' },
  { value: 'Pacific/Auckland', label: 'New Zealand Time', offset: '+12:00' },
];

const DAYS_OF_WEEK = [
  { value: 0, label: 'Sun', full: 'Sunday' },
  { value: 1, label: 'Mon', full: 'Monday' },
  { value: 2, label: 'Tue', full: 'Tuesday' },
  { value: 3, label: 'Wed', full: 'Wednesday' },
  { value: 4, label: 'Thu', full: 'Thursday' },
  { value: 5, label: 'Fri', full: 'Friday' },
  { value: 6, label: 'Sat', full: 'Saturday' },
];

const MONTHS = [
  { value: 1, label: 'Jan' },
  { value: 2, label: 'Feb' },
  { value: 3, label: 'Mar' },
  { value: 4, label: 'Apr' },
  { value: 5, label: 'May' },
  { value: 6, label: 'Jun' },
  { value: 7, label: 'Jul' },
  { value: 8, label: 'Aug' },
  { value: 9, label: 'Sep' },
  { value: 10, label: 'Oct' },
  { value: 11, label: 'Nov' },
  { value: 12, label: 'Dec' },
];

// ================================
// CRON UTILITIES
// ================================

const parseCronExpression = (cron: string): { minute: string; hour: string; dayOfMonth: string; month: string; dayOfWeek: string } => {
  const parts = cron.trim().split(/\s+/);
  return {
    minute: parts[0] || '*',
    hour: parts[1] || '*',
    dayOfMonth: parts[2] || '*',
    month: parts[3] || '*',
    dayOfWeek: parts[4] || '*',
  };
};

const buildCronExpression = (parts: { minute: string; hour: string; dayOfMonth: string; month: string; dayOfWeek: string }): string => {
  return `${parts.minute} ${parts.hour} ${parts.dayOfMonth} ${parts.month} ${parts.dayOfWeek}`;
};

const describeCronExpression = (cron: string): string => {
  const parts = parseCronExpression(cron);
  const segments: string[] = [];

  // Handle minute
  if (parts.minute === '*') {
    segments.push('Every minute');
  } else if (parts.minute.startsWith('*/')) {
    segments.push(`Every ${parts.minute.slice(2)} minutes`);
  } else if (parts.minute.includes(',')) {
    segments.push(`At minutes ${parts.minute}`);
  } else {
    segments.push(`At minute ${parts.minute}`);
  }

  // Handle hour
  if (parts.hour !== '*') {
    if (parts.hour.startsWith('*/')) {
      segments.push(`every ${parts.hour.slice(2)} hours`);
    } else if (parts.hour.includes(',')) {
      segments.push(`at hours ${parts.hour}`);
    } else if (parts.hour.includes('-')) {
      segments.push(`between hours ${parts.hour}`);
    } else {
      const hour = parseInt(parts.hour, 10);
      const ampm = hour >= 12 ? 'PM' : 'AM';
      const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
      segments[0] = `At ${displayHour}:${parts.minute.padStart(2, '0')} ${ampm}`;
    }
  }

  // Handle day of month
  if (parts.dayOfMonth !== '*') {
    if (parts.dayOfMonth === 'L') {
      segments.push('on the last day of the month');
    } else if (parts.dayOfMonth.includes(',')) {
      segments.push(`on days ${parts.dayOfMonth}`);
    } else {
      segments.push(`on day ${parts.dayOfMonth}`);
    }
  }

  // Handle month
  if (parts.month !== '*') {
    if (parts.month.includes(',')) {
      const monthNames = parts.month.split(',').map(m => MONTHS[parseInt(m, 10) - 1]?.label || m);
      segments.push(`in ${monthNames.join(', ')}`);
    } else {
      segments.push(`in ${MONTHS[parseInt(parts.month, 10) - 1]?.label || parts.month}`);
    }
  }

  // Handle day of week
  if (parts.dayOfWeek !== '*') {
    if (parts.dayOfWeek === '1-5') {
      segments.push('on weekdays');
    } else if (parts.dayOfWeek === '0,6') {
      segments.push('on weekends');
    } else if (parts.dayOfWeek.includes(',')) {
      const dayNames = parts.dayOfWeek.split(',').map(d => DAYS_OF_WEEK[parseInt(d, 10)]?.full || d);
      segments.push(`on ${dayNames.join(', ')}`);
    } else if (parts.dayOfWeek.includes('-')) {
      const [start, end] = parts.dayOfWeek.split('-');
      segments.push(`${DAYS_OF_WEEK[parseInt(start, 10)]?.full} through ${DAYS_OF_WEEK[parseInt(end, 10)]?.full}`);
    } else {
      segments.push(`on ${DAYS_OF_WEEK[parseInt(parts.dayOfWeek, 10)]?.full || parts.dayOfWeek}`);
    }
  }

  return segments.join(' ');
};

const calculateNextRuns = (cron: string, _timezone: string, count = 5): Date[] => {
  // Simple next run calculation - in production, use a library like cronstrue or cron-parser
  const now = new Date();
  const runs: Date[] = [];
  const parts = parseCronExpression(cron);

  // For demo purposes, calculate approximate next runs
  let currentDate = new Date(now);

  for (let i = 0; i < count && runs.length < count; i++) {
    currentDate = new Date(currentDate.getTime() + 60000); // Advance by 1 minute

    // Simple matching logic (production would use proper cron parsing)
    const minute = currentDate.getMinutes();
    const hour = currentDate.getHours();

    const matchesMinute = parts.minute === '*' ||
      parts.minute === String(minute) ||
      (parts.minute.startsWith('*/') && minute % parseInt(parts.minute.slice(2), 10) === 0);

    const matchesHour = parts.hour === '*' ||
      parts.hour === String(hour) ||
      (parts.hour.startsWith('*/') && hour % parseInt(parts.hour.slice(2), 10) === 0);

    if (matchesMinute && matchesHour) {
      runs.push(new Date(currentDate));
      // Skip to next hour to avoid duplicates
      currentDate.setMinutes(0);
      currentDate.setHours(currentDate.getHours() + 1);
    }

    // Prevent infinite loop
    if (i > 1000) break;
  }

  return runs.slice(0, count);
};

const validateCronExpression = (cron: string): { valid: boolean; error?: string } => {
  const parts = cron.trim().split(/\s+/);
  if (parts.length !== 5) {
    return { valid: false, error: 'Cron expression must have exactly 5 parts (minute hour day month weekday)' };
  }

  const validators = [
    { name: 'Minute', min: 0, max: 59 },
    { name: 'Hour', min: 0, max: 23 },
    { name: 'Day of month', min: 1, max: 31 },
    { name: 'Month', min: 1, max: 12 },
    { name: 'Day of week', min: 0, max: 6 },
  ];

  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    const { name } = validators[i];

    if (part === '*' || part === 'L') continue;
    if (part.startsWith('*/')) {
      const step = parseInt(part.slice(2), 10);
      if (isNaN(step) || step < 1) {
        return { valid: false, error: `${name}: Invalid step value "${part}"` };
      }
      continue;
    }

    // Check for ranges and lists
    const values = part.split(',');
    for (const val of values) {
      if (val.includes('-')) {
        const [start, end] = val.split('-').map(v => parseInt(v, 10));
        if (isNaN(start) || isNaN(end)) {
          return { valid: false, error: `${name}: Invalid range "${val}"` };
        }
      } else {
        const num = parseInt(val, 10);
        if (isNaN(num)) {
          return { valid: false, error: `${name}: Invalid value "${val}"` };
        }
      }
    }
  }

  return { valid: true };
};

// ================================
// COMPONENT
// ================================

export const ScheduleModal: React.FC<ScheduleModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  schedule,
  repository,
  repositories,
}) => {
  // Basic form state
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [selectedRepoId, setSelectedRepoId] = useState<string>('');
  const [ref, setRef] = useState('main');
  const [workflowFile, setWorkflowFile] = useState('');
  const [isActive, setIsActive] = useState(true);

  // Schedule configuration
  const [scheduleMode, setScheduleMode] = useState<ScheduleMode>('preset');
  const [selectedPreset, setSelectedPreset] = useState<string>('nightly-2am');
  const [cronExpression, setCronExpression] = useState('0 2 * * *');
  const [timezone, setTimezone] = useState('UTC');

  // Visual builder state
  const [cronParts, setCronParts] = useState({
    minute: '0',
    hour: '2',
    dayOfMonth: '*',
    month: '*',
    dayOfWeek: '*',
  });

  // Advanced options
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [startDate, setStartDate] = useState<string>('');
  const [endDate, setEndDate] = useState<string>('');
  const [concurrencyPolicy, setConcurrencyPolicy] = useState<ConcurrencyPolicy>('skip');
  const [maxRetries, setMaxRetries] = useState(3);
  const [blackoutWindows, setBlackoutWindows] = useState<BlackoutWindow[]>([]);

  // Input parameters
  const [inputParams, setInputParams] = useState<InputParam[]>([]);

  // UI state
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize form with schedule data or defaults
  useEffect(() => {
    if (schedule) {
      setName(schedule.name);
      setDescription(schedule.description || '');
      setSelectedRepoId(schedule.repository?.id || '');
      setRef(schedule.ref);
      setWorkflowFile(schedule.workflow_file || '');
      setIsActive(schedule.is_active);
      setCronExpression(schedule.cron_expression);
      setTimezone(schedule.timezone || 'UTC');
      setCronParts(parseCronExpression(schedule.cron_expression));
      setScheduleMode('custom');

      // Convert inputs to array
      if (schedule.inputs) {
        setInputParams(
          Object.entries(schedule.inputs).map(([key, value], index) => ({
            id: `param-${index}`,
            key,
            value,
          }))
        );
      }
    } else if (repository) {
      setSelectedRepoId(repository.id);
      // Reset to defaults
      setName('');
      setDescription('');
      setRef('main');
      setWorkflowFile('');
      setIsActive(true);
      setSelectedPreset('nightly-2am');
      setCronExpression('0 2 * * *');
      setTimezone('UTC');
      setCronParts({ minute: '0', hour: '2', dayOfMonth: '*', month: '*', dayOfWeek: '*' });
      setInputParams([]);
    }
  }, [schedule, repository, isOpen]);

  // Update cron expression when preset changes
  useEffect(() => {
    if (scheduleMode === 'preset') {
      const preset = SCHEDULE_PRESETS.find(p => p.id === selectedPreset);
      if (preset) {
        setCronExpression(preset.cron);
        setCronParts(parseCronExpression(preset.cron));
      }
    }
  }, [selectedPreset, scheduleMode]);

  // Update cron expression when visual builder changes
  useEffect(() => {
    if (scheduleMode === 'visual') {
      setCronExpression(buildCronExpression(cronParts));
    }
  }, [cronParts, scheduleMode]);

  // Validation
  const validation = useMemo(() => {
    const errors: string[] = [];

    if (!name.trim()) errors.push('Name is required');
    if (!selectedRepoId && !repository?.id) errors.push('Repository is required');
    if (!ref.trim()) errors.push('Branch/ref is required');

    const cronValidation = validateCronExpression(cronExpression);
    if (!cronValidation.valid) {
      errors.push(cronValidation.error || 'Invalid cron expression');
    }

    // Validate input params
    const paramKeys = inputParams.map(p => p.key).filter(k => k.trim());
    const uniqueKeys = new Set(paramKeys);
    if (paramKeys.length !== uniqueKeys.size) {
      errors.push('Duplicate input parameter keys');
    }

    return { valid: errors.length === 0, errors };
  }, [name, selectedRepoId, repository, ref, cronExpression, inputParams]);

  // Next runs preview
  const nextRuns = useMemo(() => {
    if (!validateCronExpression(cronExpression).valid) return [];
    return calculateNextRuns(cronExpression, timezone, 5);
  }, [cronExpression, timezone]);

  // Handlers
  const handleAddInputParam = () => {
    setInputParams([
      ...inputParams,
      { id: `param-${Date.now()}`, key: '', value: '' },
    ]);
  };

  const handleRemoveInputParam = (id: string) => {
    setInputParams(inputParams.filter(p => p.id !== id));
  };

  const handleUpdateInputParam = (id: string, field: 'key' | 'value', value: string) => {
    setInputParams(
      inputParams.map(p => (p.id === id ? { ...p, [field]: value } : p))
    );
  };

  const handleAddBlackoutWindow = () => {
    setBlackoutWindows([
      ...blackoutWindows,
      { id: `blackout-${Date.now()}`, startTime: '00:00', endTime: '06:00', days: [0, 6] },
    ]);
  };

  const handleRemoveBlackoutWindow = (id: string) => {
    setBlackoutWindows(blackoutWindows.filter(b => b.id !== id));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validation.valid) {
      setError(validation.errors[0]);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const inputs: Record<string, string> = {};
      inputParams.forEach(p => {
        if (p.key.trim()) {
          inputs[p.key.trim()] = p.value;
        }
      });

      const data: CreateScheduleData = {
        name: name.trim(),
        description: description.trim() || undefined,
        cron_expression: cronExpression,
        timezone,
        ref: ref.trim(),
        workflow_file: workflowFile.trim() || undefined,
        inputs: Object.keys(inputs).length > 0 ? inputs : undefined,
        is_active: isActive,
      };

      const repoId = selectedRepoId || repository?.id;
      if (!repoId) {
        throw new Error('Repository is required');
      }

      if (schedule) {
        await gitProvidersApi.updateSchedule(schedule.id, data);
      } else {
        await gitProvidersApi.createSchedule(repoId, data);
      }

      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save schedule');
    } finally {
      setLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-theme-surface border border-theme rounded-lg shadow-xl w-full max-w-3xl max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-primary/10 rounded-lg">
              <Clock className="w-5 h-5 text-theme-primary" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">
                {schedule ? 'Edit Schedule' : 'Create Schedule'}
              </h2>
              <p className="text-sm text-theme-secondary">
                Configure automated pipeline execution
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 hover:bg-theme-bg rounded-lg text-theme-secondary hover:text-theme-primary"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto">
          <div className="p-6 space-y-6">
            {/* Error Display */}
            {error && (
              <div className="flex items-center gap-2 p-3 bg-theme-danger/10 border border-theme-danger/20 rounded-lg text-theme-danger">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span className="text-sm">{error}</span>
              </div>
            )}

            {/* Basic Info Section */}
            <section className="space-y-4">
              <h3 className="text-sm font-medium text-theme-secondary uppercase tracking-wide">
                Basic Information
              </h3>

              <div className="grid grid-cols-2 gap-4">
                <div className="col-span-2">
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Schedule Name *
                  </label>
                  <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="e.g., Nightly Build, Weekly Deploy"
                    className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary placeholder:text-theme-secondary/50"
                  />
                </div>

                <div className="col-span-2">
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Description
                  </label>
                  <textarea
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    placeholder="Describe what this schedule does..."
                    rows={2}
                    className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary placeholder:text-theme-secondary/50 resize-none"
                  />
                </div>

                {!repository && (
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      Repository *
                    </label>
                    <select
                      value={selectedRepoId}
                      onChange={(e) => setSelectedRepoId(e.target.value)}
                      className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
                    >
                      <option value="">Select repository...</option>
                      {repositories.map((repo) => (
                        <option key={repo.id} value={repo.id}>
                          {repo.full_name}
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    <GitBranch className="w-4 h-4 inline mr-1" />
                    Branch / Ref *
                  </label>
                  <input
                    type="text"
                    value={ref}
                    onChange={(e) => setRef(e.target.value)}
                    placeholder="main, develop, v1.0.0"
                    className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    <FileCode className="w-4 h-4 inline mr-1" />
                    Workflow File
                  </label>
                  <input
                    type="text"
                    value={workflowFile}
                    onChange={(e) => setWorkflowFile(e.target.value)}
                    placeholder=".github/workflows/build.yml"
                    className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
                  />
                </div>
              </div>
            </section>

            {/* Schedule Configuration Section */}
            <section className="space-y-4">
              <h3 className="text-sm font-medium text-theme-secondary uppercase tracking-wide">
                Schedule Configuration
              </h3>

              {/* Mode Selector */}
              <div className="flex gap-2 p-1 bg-theme-bg rounded-lg">
                {[
                  { id: 'preset', label: 'Presets', icon: Zap },
                  { id: 'visual', label: 'Visual Builder', icon: Calendar },
                  { id: 'custom', label: 'Custom Cron', icon: Settings },
                ].map(({ id, label, icon: Icon }) => (
                  <button
                    key={id}
                    type="button"
                    onClick={() => setScheduleMode(id as ScheduleMode)}
                    className={`flex-1 flex items-center justify-center gap-2 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                      scheduleMode === id
                        ? 'bg-theme-primary text-white'
                        : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface'
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                    {label}
                  </button>
                ))}
              </div>

              {/* Preset Mode */}
              {scheduleMode === 'preset' && (
                <div className="grid grid-cols-2 gap-2">
                  {SCHEDULE_PRESETS.map((preset) => (
                    <button
                      key={preset.id}
                      type="button"
                      onClick={() => setSelectedPreset(preset.id)}
                      className={`p-3 text-left border rounded-lg transition-colors ${
                        selectedPreset === preset.id
                          ? 'border-theme-primary bg-theme-primary/10'
                          : 'border-theme hover:border-theme-primary/50'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-theme-primary">{preset.label}</span>
                        {selectedPreset === preset.id && (
                          <Check className="w-4 h-4 text-theme-primary" />
                        )}
                      </div>
                      <p className="text-xs text-theme-secondary mt-1">{preset.description}</p>
                      <code className="text-xs text-theme-secondary/70 mt-1 block">
                        {preset.cron}
                      </code>
                    </button>
                  ))}
                </div>
              )}

              {/* Visual Builder Mode */}
              {scheduleMode === 'visual' && (
                <div className="space-y-4 p-4 bg-theme-bg rounded-lg">
                  <div className="grid grid-cols-5 gap-4">
                    {/* Minute */}
                    <div>
                      <label className="block text-xs font-medium text-theme-secondary mb-1">
                        Minute
                      </label>
                      <select
                        value={cronParts.minute}
                        onChange={(e) => setCronParts({ ...cronParts, minute: e.target.value })}
                        className="w-full bg-theme-surface border border-theme rounded px-2 py-1.5 text-sm text-theme-primary"
                      >
                        <option value="*">Every minute</option>
                        <option value="*/5">Every 5 min</option>
                        <option value="*/10">Every 10 min</option>
                        <option value="*/15">Every 15 min</option>
                        <option value="*/30">Every 30 min</option>
                        <option value="0">:00</option>
                        <option value="15">:15</option>
                        <option value="30">:30</option>
                        <option value="45">:45</option>
                      </select>
                    </div>

                    {/* Hour */}
                    <div>
                      <label className="block text-xs font-medium text-theme-secondary mb-1">
                        Hour
                      </label>
                      <select
                        value={cronParts.hour}
                        onChange={(e) => setCronParts({ ...cronParts, hour: e.target.value })}
                        className="w-full bg-theme-surface border border-theme rounded px-2 py-1.5 text-sm text-theme-primary"
                      >
                        <option value="*">Every hour</option>
                        <option value="*/2">Every 2 hours</option>
                        <option value="*/4">Every 4 hours</option>
                        <option value="*/6">Every 6 hours</option>
                        <option value="*/12">Every 12 hours</option>
                        {Array.from({ length: 24 }, (_, i) => (
                          <option key={i} value={String(i)}>
                            {i === 0 ? '12 AM' : i < 12 ? `${i} AM` : i === 12 ? '12 PM' : `${i - 12} PM`}
                          </option>
                        ))}
                      </select>
                    </div>

                    {/* Day of Month */}
                    <div>
                      <label className="block text-xs font-medium text-theme-secondary mb-1">
                        Day (month)
                      </label>
                      <select
                        value={cronParts.dayOfMonth}
                        onChange={(e) => setCronParts({ ...cronParts, dayOfMonth: e.target.value })}
                        className="w-full bg-theme-surface border border-theme rounded px-2 py-1.5 text-sm text-theme-primary"
                      >
                        <option value="*">Every day</option>
                        <option value="1">1st</option>
                        <option value="15">15th</option>
                        <option value="1,15">1st & 15th</option>
                        <option value="L">Last day</option>
                        {Array.from({ length: 31 }, (_, i) => (
                          <option key={i + 1} value={String(i + 1)}>
                            {i + 1}
                          </option>
                        ))}
                      </select>
                    </div>

                    {/* Month */}
                    <div>
                      <label className="block text-xs font-medium text-theme-secondary mb-1">
                        Month
                      </label>
                      <select
                        value={cronParts.month}
                        onChange={(e) => setCronParts({ ...cronParts, month: e.target.value })}
                        className="w-full bg-theme-surface border border-theme rounded px-2 py-1.5 text-sm text-theme-primary"
                      >
                        <option value="*">Every month</option>
                        <option value="1,4,7,10">Quarterly</option>
                        {MONTHS.map((m) => (
                          <option key={m.value} value={String(m.value)}>
                            {m.label}
                          </option>
                        ))}
                      </select>
                    </div>

                    {/* Day of Week */}
                    <div>
                      <label className="block text-xs font-medium text-theme-secondary mb-1">
                        Day (week)
                      </label>
                      <select
                        value={cronParts.dayOfWeek}
                        onChange={(e) => setCronParts({ ...cronParts, dayOfWeek: e.target.value })}
                        className="w-full bg-theme-surface border border-theme rounded px-2 py-1.5 text-sm text-theme-primary"
                      >
                        <option value="*">Every day</option>
                        <option value="1-5">Weekdays</option>
                        <option value="0,6">Weekends</option>
                        {DAYS_OF_WEEK.map((d) => (
                          <option key={d.value} value={String(d.value)}>
                            {d.full}
                          </option>
                        ))}
                      </select>
                    </div>
                  </div>

                  {/* Quick Day Selection */}
                  <div>
                    <label className="block text-xs font-medium text-theme-secondary mb-2">
                      Quick Day Selection
                    </label>
                    <div className="flex gap-1">
                      {DAYS_OF_WEEK.map((day) => {
                        const isSelected =
                          cronParts.dayOfWeek === '*' ||
                          cronParts.dayOfWeek === String(day.value) ||
                          cronParts.dayOfWeek.split(',').includes(String(day.value)) ||
                          (cronParts.dayOfWeek === '1-5' && day.value >= 1 && day.value <= 5) ||
                          (cronParts.dayOfWeek === '0,6' && (day.value === 0 || day.value === 6));

                        return (
                          <button
                            key={day.value}
                            type="button"
                            onClick={() => {
                              if (cronParts.dayOfWeek === '*') {
                                setCronParts({ ...cronParts, dayOfWeek: String(day.value) });
                              } else if (cronParts.dayOfWeek === String(day.value)) {
                                setCronParts({ ...cronParts, dayOfWeek: '*' });
                              } else {
                                const current = cronParts.dayOfWeek.split(',').filter(d => d !== '*');
                                if (current.includes(String(day.value))) {
                                  const newDays = current.filter(d => d !== String(day.value));
                                  setCronParts({ ...cronParts, dayOfWeek: newDays.length > 0 ? newDays.join(',') : '*' });
                                } else {
                                  setCronParts({ ...cronParts, dayOfWeek: [...current, String(day.value)].sort().join(',') });
                                }
                              }
                            }}
                            className={`flex-1 py-2 text-xs font-medium rounded transition-colors ${
                              isSelected
                                ? 'bg-theme-primary text-white'
                                : 'bg-theme-surface border border-theme text-theme-secondary hover:border-theme-primary'
                            }`}
                          >
                            {day.label}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                </div>
              )}

              {/* Custom Cron Mode */}
              {scheduleMode === 'custom' && (
                <div className="space-y-3">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      Cron Expression
                    </label>
                    <input
                      type="text"
                      value={cronExpression}
                      onChange={(e) => {
                        setCronExpression(e.target.value);
                        setCronParts(parseCronExpression(e.target.value));
                      }}
                      placeholder="* * * * *"
                      className={`w-full bg-theme-bg border rounded-lg px-3 py-2 text-theme-primary font-mono ${
                        validateCronExpression(cronExpression).valid
                          ? 'border-theme'
                          : 'border-theme-danger'
                      }`}
                    />
                  </div>

                  <div className="flex items-start gap-2 p-3 bg-theme-bg rounded-lg">
                    <Info className="w-4 h-4 text-theme-secondary mt-0.5 shrink-0" />
                    <div className="text-sm text-theme-secondary">
                      <p className="font-medium mb-1">Cron Format: minute hour day month weekday</p>
                      <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                        <span><code>*</code> - every</span>
                        <span><code>*/n</code> - every n</span>
                        <span><code>n</code> - at n</span>
                        <span><code>n,m</code> - at n and m</span>
                        <span><code>n-m</code> - from n to m</span>
                        <span><code>L</code> - last (day only)</span>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* Human Readable Description */}
              {validateCronExpression(cronExpression).valid && (
                <div className="flex items-center gap-2 p-3 bg-theme-primary/5 border border-theme-primary/20 rounded-lg">
                  <Clock className="w-4 h-4 text-theme-primary shrink-0" />
                  <span className="text-sm text-theme-primary">
                    {describeCronExpression(cronExpression)}
                  </span>
                </div>
              )}

              {/* Timezone Selector */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Timezone
                </label>
                <select
                  value={timezone}
                  onChange={(e) => setTimezone(e.target.value)}
                  className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
                >
                  {TIMEZONES.map((tz) => (
                    <option key={tz.value} value={tz.value}>
                      {tz.label} ({tz.offset})
                    </option>
                  ))}
                </select>
              </div>

              {/* Next Runs Preview */}
              {nextRuns.length > 0 && (
                <div className="space-y-2">
                  <h4 className="text-sm font-medium text-theme-secondary">
                    Next {nextRuns.length} Scheduled Runs
                  </h4>
                  <div className="flex flex-wrap gap-2">
                    {nextRuns.map((run, index) => (
                      <span
                        key={index}
                        className="px-2 py-1 bg-theme-bg rounded text-xs text-theme-secondary"
                      >
                        {run.toLocaleString(undefined, {
                          month: 'short',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit',
                        })}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </section>

            {/* Input Parameters Section */}
            <section className="space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-medium text-theme-secondary uppercase tracking-wide">
                  Workflow Input Parameters
                </h3>
                <button
                  type="button"
                  onClick={handleAddInputParam}
                  className="flex items-center gap-1 text-sm text-theme-primary hover:underline"
                >
                  <Plus className="w-4 h-4" />
                  Add Parameter
                </button>
              </div>

              {inputParams.length > 0 ? (
                <div className="space-y-2">
                  {inputParams.map((param) => (
                    <div key={param.id} className="flex items-center gap-2">
                      <input
                        type="text"
                        value={param.key}
                        onChange={(e) => handleUpdateInputParam(param.id, 'key', e.target.value)}
                        placeholder="Parameter name"
                        className="flex-1 bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary text-sm"
                      />
                      <input
                        type="text"
                        value={param.value}
                        onChange={(e) => handleUpdateInputParam(param.id, 'value', e.target.value)}
                        placeholder="Value"
                        className="flex-1 bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary text-sm"
                      />
                      <button
                        type="button"
                        onClick={() => handleRemoveInputParam(param.id)}
                        className="p-2 text-theme-secondary hover:text-theme-danger"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-theme-secondary">
                  No input parameters. Add parameters to pass to the workflow.
                </p>
              )}
            </section>

            {/* Advanced Options Section */}
            <section className="space-y-4">
              <button
                type="button"
                onClick={() => setShowAdvanced(!showAdvanced)}
                className="flex items-center gap-2 text-sm font-medium text-theme-secondary hover:text-theme-primary"
              >
                {showAdvanced ? (
                  <ChevronUp className="w-4 h-4" />
                ) : (
                  <ChevronDown className="w-4 h-4" />
                )}
                Advanced Options
              </button>

              {showAdvanced && (
                <div className="space-y-4 p-4 bg-theme-bg rounded-lg">
                  {/* Date Range */}
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-1">
                        Start Date (Optional)
                      </label>
                      <input
                        type="date"
                        value={startDate}
                        onChange={(e) => setStartDate(e.target.value)}
                        className="w-full bg-theme-surface border border-theme rounded-lg px-3 py-2 text-theme-primary"
                      />
                      <p className="text-xs text-theme-secondary mt-1">
                        Schedule becomes active on this date
                      </p>
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-1">
                        End Date (Optional)
                      </label>
                      <input
                        type="date"
                        value={endDate}
                        onChange={(e) => setEndDate(e.target.value)}
                        className="w-full bg-theme-surface border border-theme rounded-lg px-3 py-2 text-theme-primary"
                      />
                      <p className="text-xs text-theme-secondary mt-1">
                        Schedule automatically pauses after this date
                      </p>
                    </div>
                  </div>

                  {/* Concurrency Policy */}
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Concurrency Policy
                    </label>
                    <div className="grid grid-cols-3 gap-2">
                      {[
                        { id: 'skip', label: 'Skip', description: 'Skip if previous run is still active' },
                        { id: 'queue', label: 'Queue', description: 'Wait for previous run to complete' },
                        { id: 'replace', label: 'Replace', description: 'Cancel previous run and start new' },
                      ].map((policy) => (
                        <button
                          key={policy.id}
                          type="button"
                          onClick={() => setConcurrencyPolicy(policy.id as ConcurrencyPolicy)}
                          className={`p-3 text-left border rounded-lg transition-colors ${
                            concurrencyPolicy === policy.id
                              ? 'border-theme-primary bg-theme-primary/10'
                              : 'border-theme hover:border-theme-primary/50'
                          }`}
                        >
                          <span className="font-medium text-theme-primary text-sm">{policy.label}</span>
                          <p className="text-xs text-theme-secondary mt-1">{policy.description}</p>
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Max Retries */}
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      Max Retries on Failure
                    </label>
                    <div className="flex items-center gap-3">
                      <input
                        type="range"
                        min="0"
                        max="5"
                        value={maxRetries}
                        onChange={(e) => setMaxRetries(parseInt(e.target.value, 10))}
                        className="flex-1"
                      />
                      <span className="text-sm text-theme-primary w-8 text-center">{maxRetries}</span>
                    </div>
                  </div>

                  {/* Blackout Windows */}
                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <label className="block text-sm font-medium text-theme-primary">
                        Blackout Windows
                      </label>
                      <button
                        type="button"
                        onClick={handleAddBlackoutWindow}
                        className="text-xs text-theme-primary hover:underline"
                      >
                        + Add Window
                      </button>
                    </div>

                    {blackoutWindows.length > 0 ? (
                      <div className="space-y-2">
                        {blackoutWindows.map((window) => (
                          <div
                            key={window.id}
                            className="flex items-center gap-2 p-2 bg-theme-surface border border-theme rounded-lg"
                          >
                            <input
                              type="time"
                              value={window.startTime}
                              onChange={(e) => {
                                setBlackoutWindows(
                                  blackoutWindows.map((w) =>
                                    w.id === window.id ? { ...w, startTime: e.target.value } : w
                                  )
                                );
                              }}
                              className="bg-theme-bg border border-theme rounded px-2 py-1 text-sm text-theme-primary"
                            />
                            <span className="text-theme-secondary">to</span>
                            <input
                              type="time"
                              value={window.endTime}
                              onChange={(e) => {
                                setBlackoutWindows(
                                  blackoutWindows.map((w) =>
                                    w.id === window.id ? { ...w, endTime: e.target.value } : w
                                  )
                                );
                              }}
                              className="bg-theme-bg border border-theme rounded px-2 py-1 text-sm text-theme-primary"
                            />
                            <div className="flex-1 flex gap-1">
                              {DAYS_OF_WEEK.map((day) => (
                                <button
                                  key={day.value}
                                  type="button"
                                  onClick={() => {
                                    setBlackoutWindows(
                                      blackoutWindows.map((w) => {
                                        if (w.id !== window.id) return w;
                                        const days = w.days.includes(day.value)
                                          ? w.days.filter((d) => d !== day.value)
                                          : [...w.days, day.value];
                                        return { ...w, days };
                                      })
                                    );
                                  }}
                                  className={`px-1.5 py-0.5 text-xs rounded ${
                                    window.days.includes(day.value)
                                      ? 'bg-theme-danger/20 text-theme-danger'
                                      : 'bg-theme-bg text-theme-secondary'
                                  }`}
                                >
                                  {day.label}
                                </button>
                              ))}
                            </div>
                            <button
                              type="button"
                              onClick={() => handleRemoveBlackoutWindow(window.id)}
                              className="p-1 text-theme-secondary hover:text-theme-danger"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <p className="text-sm text-theme-secondary">
                        No blackout windows. Runs will execute at all scheduled times.
                      </p>
                    )}
                  </div>
                </div>
              )}
            </section>

            {/* Active Toggle */}
            <div className="flex items-center justify-between p-4 bg-theme-bg rounded-lg">
              <div>
                <label className="text-sm font-medium text-theme-primary">
                  Schedule Status
                </label>
                <p className="text-xs text-theme-secondary mt-1">
                  {isActive
                    ? 'Schedule will run at configured times'
                    : 'Schedule is paused and will not run'}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setIsActive(!isActive)}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-colors ${
                  isActive
                    ? 'bg-theme-success/10 text-theme-success hover:bg-theme-success/20'
                    : 'bg-theme-surface text-theme-secondary hover:text-theme-primary'
                }`}
              >
                {isActive ? (
                  <>
                    <Play className="w-4 h-4" />
                    Active
                  </>
                ) : (
                  <>
                    <Pause className="w-4 h-4" />
                    Paused
                  </>
                )}
              </button>
            </div>
          </div>
        </form>

        {/* Footer */}
        <div className="flex items-center justify-between p-4 border-t border-theme bg-theme-bg">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-theme-secondary hover:text-theme-primary"
          >
            Cancel
          </button>
          <div className="flex items-center gap-3">
            {!validation.valid && (
              <span className="text-sm text-theme-danger">{validation.errors[0]}</span>
            )}
            <button
              type="submit"
              onClick={handleSubmit}
              disabled={loading || !validation.valid}
              className="flex items-center gap-2 px-4 py-2 bg-theme-primary text-white rounded-lg font-medium hover:bg-theme-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? (
                <>
                  <RefreshCw className="w-4 h-4 animate-spin" />
                  Saving...
                </>
              ) : (
                <>
                  <Check className="w-4 h-4" />
                  {schedule ? 'Update Schedule' : 'Create Schedule'}
                </>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ScheduleModal;
