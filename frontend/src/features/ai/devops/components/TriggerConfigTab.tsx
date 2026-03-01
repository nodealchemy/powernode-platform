import React from 'react';
import { X } from 'lucide-react';

interface TriggerConfig {
  type: string;
  events: string[];
  cron: string;
  description: string;
  filters: Record<string, unknown>;
}

const TRIGGER_TYPES = [
  { value: 'manual', label: 'Manual' },
  { value: 'webhook', label: 'Webhook' },
  { value: 'schedule', label: 'Schedule (Cron)' },
];

const selectClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';
const inputClass = selectClass;
const labelClass = 'block text-sm font-medium text-theme-primary mb-1';

function safeJsonStringify(obj: unknown): string {
  try {
    return JSON.stringify(obj, null, 2);
  } catch {
    return '{}';
  }
}

function safeJsonParse(str: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(str);
    if (typeof parsed === 'object' && parsed !== null) return parsed as Record<string, unknown>;
    return null;
  } catch {
    return null;
  }
}

interface TriggerConfigTabProps {
  triggerConfig: TriggerConfig;
  onUpdateTrigger: (updates: Partial<TriggerConfig>) => void;
}

export const TriggerConfigTab: React.FC<TriggerConfigTabProps> = ({
  triggerConfig,
  onUpdateTrigger,
}) => {
  return (
    <div className="space-y-4">
      <div>
        <label className={labelClass}>Trigger Type</label>
        <select value={triggerConfig.type} onChange={(e) => onUpdateTrigger({ type: e.target.value })} className={selectClass}>
          {TRIGGER_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
      </div>
      <div>
        <label className={labelClass}>Description</label>
        <input
          type="text"
          value={triggerConfig.description}
          onChange={(e) => onUpdateTrigger({ description: e.target.value })}
          placeholder="e.g. Triggered on pull request events"
          className={inputClass}
        />
      </div>
      {triggerConfig.type === 'schedule' && (
        <div>
          <label className={labelClass}>Cron Expression</label>
          <input
            type="text"
            value={triggerConfig.cron}
            onChange={(e) => onUpdateTrigger({ cron: e.target.value })}
            placeholder="0 2 * * 1 (Every Monday at 2 AM)"
            className={inputClass}
          />
          <p className="text-xs text-theme-secondary mt-1">Standard cron format: minute hour day-of-month month day-of-week</p>
        </div>
      )}
      {triggerConfig.type === 'webhook' && (
        <div>
          <label className={labelClass}>Webhook Events</label>
          <div className="flex flex-wrap gap-1.5 mb-2">
            {triggerConfig.events.map((evt, i) => (
              <span key={i} className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded bg-theme-info/10 text-theme-info">
                {evt}
                <button onClick={() => onUpdateTrigger({ events: triggerConfig.events.filter((_, idx) => idx !== i) })} className="hover:text-theme-danger">
                  <X size={10} />
                </button>
              </span>
            ))}
          </div>
          <div className="flex gap-2">
            <input
              type="text"
              placeholder="e.g. pull_request.opened"
              className={inputClass}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  const val = (e.target as HTMLInputElement).value.trim();
                  if (val && !triggerConfig.events.includes(val)) {
                    onUpdateTrigger({ events: [...triggerConfig.events, val] });
                    (e.target as HTMLInputElement).value = '';
                  }
                }
              }}
            />
          </div>
          <p className="text-xs text-theme-secondary mt-1">Press Enter to add each event</p>
        </div>
      )}
      <div>
        <label className={labelClass}>Trigger Filters (JSON)</label>
        <textarea
          value={safeJsonStringify(triggerConfig.filters)}
          onChange={(e) => {
            const parsed = safeJsonParse(e.target.value);
            if (parsed) onUpdateTrigger({ filters: parsed });
          }}
          rows={4}
          className={`${inputClass} font-mono text-xs`}
          placeholder='{"base_branch": ["main", "develop"]}'
        />
      </div>
    </div>
  );
};
