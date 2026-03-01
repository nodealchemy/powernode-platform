import React from 'react';
import { Shield } from 'lucide-react';

export interface AutonomyConfig {
  allow_agent_creation: boolean;
  allow_cross_team_operations: boolean;
  require_human_approval: boolean;
  max_agents_per_team: number;
  autonomy_level: 'supervised' | 'semi_autonomous' | 'autonomous';
  resource_limits: Record<string, string>;
}

interface TeamAutonomyConfigProps {
  config: AutonomyConfig;
  onUpdate: (config: AutonomyConfig) => void;
}

export const TeamAutonomyConfig: React.FC<TeamAutonomyConfigProps> = ({ config, onUpdate }) => {
  const handleToggle = (field: keyof AutonomyConfig) => {
    onUpdate({ ...config, [field]: !config[field] });
  };

  const handleSlider = (value: number) => {
    onUpdate({ ...config, max_agents_per_team: value });
  };

  const handleAutonomyLevel = (level: AutonomyConfig['autonomy_level']) => {
    onUpdate({ ...config, autonomy_level: level });
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-4">
      <div className="flex items-center gap-2 mb-2">
        <Shield className="h-4 w-4 text-theme-primary" />
        <h4 className="text-sm font-semibold text-theme-primary">Team Autonomy Settings</h4>
      </div>

      {/* Toggles */}
      <div className="space-y-3">
        <label className="flex items-center justify-between cursor-pointer">
          <span className="text-sm text-theme-primary">Allow Agent Creation</span>
          <button
            type="button"
            role="switch"
            aria-checked={config.allow_agent_creation}
            onClick={() => handleToggle('allow_agent_creation')}
            className={`relative w-10 h-5 rounded-full border transition-colors ${
              config.allow_agent_creation ? 'bg-theme-primary border-theme-primary' : 'bg-theme-bg-secondary border-theme'
            }`}
          >
            <span className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-theme-surface shadow-sm ring-1 ring-theme-border transition-transform ${
              config.allow_agent_creation ? 'translate-x-5' : ''
            }`} />
          </button>
        </label>

        <label className="flex items-center justify-between cursor-pointer">
          <span className="text-sm text-theme-primary">Allow Cross-Team Operations</span>
          <button
            type="button"
            role="switch"
            aria-checked={config.allow_cross_team_operations}
            onClick={() => handleToggle('allow_cross_team_operations')}
            className={`relative w-10 h-5 rounded-full border transition-colors ${
              config.allow_cross_team_operations ? 'bg-theme-primary border-theme-primary' : 'bg-theme-bg-secondary border-theme'
            }`}
          >
            <span className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-theme-surface shadow-sm ring-1 ring-theme-border transition-transform ${
              config.allow_cross_team_operations ? 'translate-x-5' : ''
            }`} />
          </button>
        </label>

        <label className="flex items-center justify-between cursor-pointer">
          <span className="text-sm text-theme-primary">Require Human Approval</span>
          <button
            type="button"
            role="switch"
            aria-checked={config.require_human_approval}
            onClick={() => handleToggle('require_human_approval')}
            className={`relative w-10 h-5 rounded-full border transition-colors ${
              config.require_human_approval ? 'bg-theme-primary border-theme-primary' : 'bg-theme-bg-secondary border-theme'
            }`}
          >
            <span className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-theme-surface shadow-sm ring-1 ring-theme-border transition-transform ${
              config.require_human_approval ? 'translate-x-5' : ''
            }`} />
          </button>
        </label>
      </div>

      {/* Max Agents Slider */}
      <div>
        <div className="flex items-center justify-between mb-1">
          <span className="text-sm text-theme-primary">Max Agents Per Team</span>
          <span className="text-sm font-medium text-theme-primary">{config.max_agents_per_team}</span>
        </div>
        <input
          type="range"
          min={1}
          max={50}
          value={config.max_agents_per_team}
          onChange={(e) => handleSlider(parseInt(e.target.value, 10))}
          className="w-full accent-theme-primary"
        />
        <div className="flex justify-between text-xs text-theme-secondary">
          <span>1</span>
          <span>50</span>
        </div>
      </div>

      {/* Autonomy Level */}
      <div>
        <span className="text-sm text-theme-primary block mb-2">Autonomy Level</span>
        <div className="flex gap-2">
          {(['supervised', 'semi_autonomous', 'autonomous'] as const).map(level => (
            <button
              key={level}
              type="button"
              onClick={() => handleAutonomyLevel(level)}
              className={`flex-1 px-3 py-2 text-xs font-medium rounded-md border transition-colors ${
                config.autonomy_level === level
                  ? 'border-theme-primary bg-theme-primary/10 text-theme-primary'
                  : 'border-theme bg-theme-surface text-theme-secondary hover:bg-theme-surface-hover'
              }`}
            >
              {level.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
