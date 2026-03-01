import React, { useEffect, useState } from 'react';
import { Rocket, FileText, Settings, Puzzle } from 'lucide-react';
import { missionsApi } from '../../api/missionsApi';
import type { MissionTemplate, MissionType } from '../../types/mission';
import { logger } from '@/shared/utils/logger';

interface StepTemplateProps {
  selectedTemplateId: string | null;
  onTemplateSelect: (template: MissionTemplate | null) => void;
  missionType: MissionType;
}

const TYPE_ICONS: Record<string, React.ElementType> = {
  development: Rocket,
  research: FileText,
  operations: Settings,
  custom: Puzzle,
};

export const StepTemplate: React.FC<StepTemplateProps> = ({
  selectedTemplateId,
  onTemplateSelect,
  missionType,
}) => {
  const [templates, setTemplates] = useState<MissionTemplate[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchTemplates = async () => {
      setLoading(true);
      try {
        const response = await missionsApi.getMissionTemplates({ mission_type: missionType });
        setTemplates(response.data.templates);
      } catch (err) {
        logger.error('Failed to fetch templates', err);
      } finally {
        setLoading(false);
      }
    };
    fetchTemplates();
  }, [missionType]);

  if (loading) {
    return <div className="text-sm text-theme-secondary text-center py-4">Loading templates...</div>;
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-theme-secondary">Choose a template or use custom phases</p>
      <div className="grid grid-cols-1 gap-2">
        {templates.map(template => {
          const Icon = TYPE_ICONS[template.mission_type] || Puzzle;
          const isSelected = selectedTemplateId === template.id;

          return (
            <button
              key={template.id}
              onClick={() => onTemplateSelect(isSelected ? null : template)}
              className={`w-full text-left p-3 rounded-lg border transition-colors ${
                isSelected
                  ? 'border-theme-accent bg-theme-accent/5'
                  : 'border-theme-border hover:border-theme-border-hover bg-theme-surface'
              }`}
            >
              <div className="flex items-center gap-3">
                <Icon className={`w-5 h-5 flex-shrink-0 ${isSelected ? 'text-theme-accent' : 'text-theme-tertiary'}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-theme-primary">{template.name}</span>
                    {template.template_type === 'system' && (
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-theme-accent/10 text-theme-accent">System</span>
                    )}
                  </div>
                  {template.description && (
                    <p className="text-xs text-theme-secondary mt-0.5 line-clamp-2">{template.description}</p>
                  )}
                  <p className="text-[10px] text-theme-tertiary mt-1">
                    {template.phase_count} phases
                    {template.approval_gates.length > 0 && ` \u00b7 ${template.approval_gates.length} approval gates`}
                  </p>
                </div>
              </div>
            </button>
          );
        })}

        {/* Custom option */}
        <button
          onClick={() => onTemplateSelect(null)}
          className={`w-full text-left p-3 rounded-lg border transition-colors ${
            selectedTemplateId === null && templates.length > 0
              ? 'border-theme-accent bg-theme-accent/5'
              : 'border-theme-border hover:border-theme-border-hover bg-theme-surface'
          }`}
        >
          <div className="flex items-center gap-3">
            <Puzzle className="w-5 h-5 flex-shrink-0 text-theme-tertiary" />
            <div>
              <span className="text-sm font-medium text-theme-primary">No template</span>
              <p className="text-xs text-theme-secondary mt-0.5">Create without a template — phases must be defined via custom configuration</p>
            </div>
          </div>
        </button>
      </div>
    </div>
  );
};
