import React from 'react';
import { Plus, X, Loader2 } from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { RalphCapabilityMatchStrategy } from '@/shared/services/ai/types/ralph-types';

const matchStrategyOptions = [
  { value: 'all', label: 'Match All', description: 'Executor must have all capabilities' },
  { value: 'any', label: 'Match Any', description: 'Executor must have at least one capability' },
  { value: 'weighted', label: 'Weighted', description: 'Score executors by capability overlap' },
];

interface ExecutorSkillTabProps {
  capabilities: string[];
  matchStrategy: RalphCapabilityMatchStrategy;
  newCapability: string;
  availableSkillsByCategory: Record<string, Array<{ slug: string; name: string }>>;
  loadingSkills: boolean;
  onCapabilitiesChange: (caps: string[]) => void;
  onMatchStrategyChange: (strategy: RalphCapabilityMatchStrategy) => void;
  onNewCapabilityChange: (value: string) => void;
  onAddCapability: () => void;
  onRemoveCapability: (cap: string) => void;
}

export const ExecutorSkillTab: React.FC<ExecutorSkillTabProps> = ({
  capabilities,
  matchStrategy,
  newCapability,
  availableSkillsByCategory,
  loadingSkills,
  onCapabilitiesChange,
  onMatchStrategyChange,
  onNewCapabilityChange,
  onAddCapability,
  onRemoveCapability,
}) => {
  return (
    <div className="space-y-4">
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-2">
          Required Skills
        </label>

        {/* Selected skills display */}
        {capabilities.length > 0 && (
          <div className="flex flex-wrap gap-2 mb-3">
            {capabilities.map((cap) => (
              <Badge key={cap} variant="info" size="sm" className="flex items-center gap-1">
                {cap}
                <button
                  type="button"
                  onClick={() => onRemoveCapability(cap)}
                  aria-label={`Remove ${cap} skill`}
                  className="ml-1 hover:text-theme-status-error"
                >
                  <X className="w-3 h-3" />
                </button>
              </Badge>
            ))}
          </div>
        )}

        {/* Skill selection by category */}
        {loadingSkills ? (
          <div className="flex items-center justify-center gap-2 py-8 border border-theme-interactive-primary rounded-lg bg-theme-surface">
            <Loader2 className="w-4 h-4 animate-spin text-theme-secondary" />
            <span className="text-sm text-theme-secondary">Loading skills...</span>
          </div>
        ) : Object.keys(availableSkillsByCategory).length > 0 ? (
          <div className="max-h-64 overflow-y-auto border border-theme-interactive-primary rounded-lg bg-theme-surface">
            {Object.entries(availableSkillsByCategory).map(([category, skills]) => (
              <div key={category} className="border-b border-theme-interactive-primary last:border-b-0">
                <div className="px-3 py-2 bg-theme-background-secondary text-xs font-semibold text-theme-secondary uppercase tracking-wider">
                  {category.replace(/_/g, ' ')}
                </div>
                <div className="grid grid-cols-2 gap-1 p-2">
                  {skills.map((skill) => (
                    <label
                      key={skill.slug}
                      className="flex items-center gap-2 cursor-pointer hover:bg-theme-background-secondary p-1.5 rounded text-sm"
                    >
                      <input
                        type="checkbox"
                        checked={capabilities.includes(skill.slug)}
                        onChange={(e) => {
                          if (e.target.checked) onCapabilitiesChange([...capabilities, skill.slug]);
                          else onCapabilitiesChange(capabilities.filter(c => c !== skill.slug));
                        }}
                        className="w-4 h-4 rounded border-theme-interactive-primary text-theme-interactive-primary focus:ring-theme-interactive-primary"
                      />
                      <span className="text-theme-primary truncate" title={skill.name}>
                        {skill.name}
                      </span>
                    </label>
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="py-4 px-3 border border-theme-interactive-primary rounded-lg bg-theme-surface text-center">
            <p className="text-sm text-theme-secondary">
              No skills found. Add custom skill slugs below.
            </p>
          </div>
        )}

        {/* Custom skill slug input */}
        <div className="flex gap-2 mt-3">
          <Input
            type="text"
            placeholder="Add custom skill slug..."
            value={newCapability}
            onChange={(e) => onNewCapabilityChange(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), onAddCapability())}
            className="flex-1"
          />
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onAddCapability}
            disabled={!newCapability.trim()}
          >
            <Plus className="w-4 h-4" />
          </Button>
        </div>
        <p className="mt-1 text-xs text-theme-secondary">
          {Object.keys(availableSkillsByCategory).length > 0
            ? 'Select skills from the list above or add custom slugs'
            : 'Enter custom skill slugs'}
        </p>
      </div>

      {/* Capability Match Strategy */}
      {capabilities.length > 0 && (
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Match Strategy
          </label>
          <Select
            value={matchStrategy}
            onChange={(value) => onMatchStrategyChange(value as RalphCapabilityMatchStrategy)}
          >
            {matchStrategyOptions.map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </Select>
          <p className="mt-1 text-xs text-theme-secondary">
            {matchStrategyOptions.find(o => o.value === matchStrategy)?.description}
          </p>
        </div>
      )}
    </div>
  );
};
