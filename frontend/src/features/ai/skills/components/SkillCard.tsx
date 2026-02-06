import { skillsApi } from '../services/skillsApi';
import type { AiSkillSummary } from '../types';

interface SkillCardProps {
  skill: AiSkillSummary;
  onToggle: (id: string, enabled: boolean) => void;
  onClick: (id: string) => void;
}

export function SkillCard({ skill, onToggle, onClick }: SkillCardProps) {
  const icon = skillsApi.getCategoryIcon(skill.category);
  const categoryLabel = skillsApi.getCategoryLabel(skill.category);

  return (
    <div
      className="bg-theme-surface border border-theme rounded-lg p-5 hover:border-theme-primary transition-colors cursor-pointer"
      onClick={() => onClick(skill.id)}
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-3">
          <span className="text-2xl">{icon}</span>
          <div>
            <h3 className="text-sm font-semibold text-theme-primary">{skill.name}</h3>
            <span className="inline-block mt-1 px-2 py-0.5 text-xs rounded-full bg-theme-surface-secondary text-theme-secondary">
              {categoryLabel}
            </span>
          </div>
        </div>
        <button
          onClick={(e) => {
            e.stopPropagation();
            onToggle(skill.id, !skill.is_enabled);
          }}
          className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
            skill.is_enabled ? 'bg-theme-success' : 'bg-theme-surface-secondary'
          }`}
          aria-label={skill.is_enabled ? 'Disable skill' : 'Enable skill'}
        >
          <span
            className={`inline-block h-3.5 w-3.5 transform rounded-full bg-theme-surface transition-transform ${
              skill.is_enabled ? 'translate-x-4' : 'translate-x-1'
            }`}
          />
        </button>
      </div>

      <p className="text-xs text-theme-secondary line-clamp-2 mb-3">
        {skill.description}
      </p>

      <div className="flex items-center gap-4 text-xs text-theme-tertiary">
        <span>{skill.command_count} commands</span>
        <span>{skill.connector_count} connectors</span>
        {skill.has_knowledge_base && <span>KB linked</span>}
      </div>

      {skill.tags.length > 0 && (
        <div className="flex flex-wrap gap-1 mt-3">
          {skill.tags.slice(0, 3).map((tag) => (
            <span
              key={tag}
              className="px-1.5 py-0.5 text-xs rounded bg-theme-surface-secondary text-theme-tertiary"
            >
              {tag}
            </span>
          ))}
        </div>
      )}

      {skill.is_system && (
        <div className="mt-3 text-xs text-theme-tertiary italic">System skill</div>
      )}
    </div>
  );
}
