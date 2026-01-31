import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';
import type { A2aSkill } from '@/shared/services/ai/types/a2a-types';

interface CapabilityBadgeProps {
  skill: A2aSkill;
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
  // Determine category from skill tags or id
  const category = skill.tags?.[0] || 'default';
  const colors = categoryColors[category] || categoryColors.default;

  return (
    <div className={cn('inline-flex items-center gap-2', className)}>
      <Badge
        variant="outline"
        size={size}
        className={cn(colors.bg, colors.text, 'border-0')}
      >
        {skill.name || skill.id}
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
  skills: A2aSkill[];
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
  const displaySkills = showAll ? skills : skills.slice(0, maxVisible);
  const hiddenCount = skills.length - maxVisible;

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
