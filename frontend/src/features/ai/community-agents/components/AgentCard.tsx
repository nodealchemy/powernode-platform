import React from 'react';
import {
  Star,
  Users,
  Activity,
  CheckCircle,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import type { CommunityAgentSummary, PricingModel } from '@/shared/services/ai';

interface AgentCardProps {
  agent: CommunityAgentSummary;
  onSelect?: (agent: CommunityAgentSummary) => void;
  onInvoke?: (agent: CommunityAgentSummary) => void;
  className?: string;
}

const pricingLabels: Record<PricingModel, string> = {
  free: 'Free',
  per_task: 'Pay per task',
  subscription: 'Subscription',
  negotiated: 'Contact for pricing',
};

export const AgentCard: React.FC<AgentCardProps> = ({
  agent,
  onSelect,
  onInvoke,
  className,
}) => {
  const formatRating = (rating?: number) => {
    if (!rating) return 'No ratings';
    return rating.toFixed(1);
  };

  const formatPrice = (model: PricingModel, price?: number) => {
    if (model === 'free') return 'Free';
    if (model === 'per_task' && price) return `$${price.toFixed(2)}/task`;
    return pricingLabels[model];
  };

  return (
    <Card
      className={cn(
        'cursor-pointer transition-all hover:shadow-md',
        'border-theme-border-primary',
        className
      )}
      onClick={() => onSelect?.(agent)}
    >
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between mb-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-medium text-theme-text-primary truncate">{agent.name}</h3>
              {agent.verified && (
                <CheckCircle className="w-4 h-4 text-theme-status-success flex-shrink-0" />
              )}
            </div>
            {agent.category && (
              <Badge variant="outline" size="sm" className="mt-1">
                {agent.category}
              </Badge>
            )}
          </div>
          <div className="flex items-center gap-1 text-theme-text-secondary">
            <Star className="w-4 h-4 text-theme-warning fill-current" />
            <span className="text-sm font-medium">{formatRating(agent.avg_rating)}</span>
            <span className="text-xs">({agent.rating_count})</span>
          </div>
        </div>

        {/* Description */}
        <p className="text-sm text-theme-text-secondary line-clamp-2 mb-3">
          {agent.description}
        </p>

        {/* Skills */}
        {agent.skills.length > 0 && (
          <div className="flex flex-wrap gap-1 mb-3">
            {agent.skills.slice(0, 3).map((skill) => (
              <Badge key={skill} variant="secondary" size="sm">
                {skill}
              </Badge>
            ))}
            {agent.skills.length > 3 && (
              <Badge variant="outline" size="sm">
                +{agent.skills.length - 3}
              </Badge>
            )}
          </div>
        )}

        {/* Stats */}
        <div className="flex items-center gap-4 text-sm text-theme-text-secondary mb-3">
          <div className="flex items-center gap-1">
            <Activity className="w-4 h-4" />
            <span>{agent.task_count} tasks</span>
          </div>
          <div className="flex items-center gap-1">
            <Users className="w-4 h-4" />
            <span>{agent.reputation_score.toFixed(0)} reputation</span>
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between pt-3 border-t border-theme-border-primary">
          <span className="text-sm font-medium text-theme-text-primary">
            {formatPrice(agent.pricing_model, agent.price_per_task)}
          </span>
          <Button
            variant="primary"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              onInvoke?.(agent);
            }}
          >
            Invoke
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default AgentCard;
