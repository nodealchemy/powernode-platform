import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';
import type { AgentSkill } from '@/shared/services/ai/types/a2a-types';

interface CapabilityBadgeProps {
  skill: AgentSkill;
  size?: 'sm' | 'md';
  showDescription?: boolean;
  className?: string;
}

const categoryColors: Record<string, { bg: string; text: string }> = {
  analysis: { bg: 'bg-theme-info/10', text: 'text-theme-info' },
  generation: { bg: 'bg-theme-success/10', text: 'text-theme-success' },
  transformation: { bg: 'bg-theme-warning/10', text: 'text-theme-warning' },
  communication: { bg: 'bg-theme-primary/10', text: 'text-theme-primary' },
  integration: { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary' },
  default: { bg: 'bg-theme-muted/10', text: 'text-theme-muted' },
};

export const CapabilityBadge: React.FC<CapabilityBadgeProps> = ({
  skill,
  size = 'sm',
  showDescription = false,
  className,
}) => {
  // Determine category from skill id (simplified - no tags in AgentSkill)
  const colors = categoryColors.default;

  return (
    <div className={cn('inline-flex items-center gap-2', className)}>
      <Badge
        variant="outline"
        size={size}
        className={cn(colors.bg, colors.text, 'border-0')}
      >
        {skill.name || skill.id || 'Unnamed Skill'}
      </Badge>
      {showDescription && skill.description && (
        <span className="text-xs text-theme-muted truncate max-w-48">
          {skill.description}
        </span>
      )}
    </div>
  );
};

interface CapabilityListProps {
  skills: (AgentSkill | string)[];
  maxVisible?: number;
  showAll?: boolean;
  className?: string;
}

export const CapabilityList: React.FC<CapabilityListProps> = ({
  skills,
  maxVisible = 3,
  showAll = false,
  className,
}) => {
  // Normalize skills - they can be strings or objects from the backend
  const normalizedSkills: AgentSkill[] = skills.map((skill, index) => {
    if (typeof skill === 'string') {
      return { id: skill, name: skill };
    }
    // Ensure skill has an id, use index as fallback
    return {
      ...skill,
      id: skill.id || `skill-${index}`,
    };
  });

  const displaySkills = showAll ? normalizedSkills : normalizedSkills.slice(0, maxVisible);
  const hiddenCount = normalizedSkills.length - maxVisible;

  return (
    <div className={cn('flex flex-wrap gap-1.5', className)}>
      {displaySkills.map((skill) => (
        <CapabilityBadge key={skill.id} skill={skill} />
      ))}
      {!showAll && hiddenCount > 0 && (
        <Badge variant="outline" size="sm" className="text-theme-muted">
          +{hiddenCount} more
        </Badge>
      )}
    </div>
  );
};

export default CapabilityBadge;
