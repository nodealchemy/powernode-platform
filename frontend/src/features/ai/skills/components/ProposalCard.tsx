import { FileText, Bot, User, Clock } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import type { SkillProposal, ProposalStatus } from '../types/lifecycle';

interface ProposalCardProps {
  proposal: SkillProposal;
  selected?: boolean;
  onSelect?: (id: string) => void;
  onClick: (id: string) => void;
}

const STATUS_VARIANTS: Record<ProposalStatus, 'default' | 'info' | 'warning' | 'success' | 'danger'> = {
  draft: 'default',
  proposed: 'info',
  approved: 'success',
  created: 'success',
  rejected: 'danger',
};

const STATUS_LABELS: Record<ProposalStatus, string> = {
  draft: 'Draft',
  proposed: 'Pending Review',
  approved: 'Approved',
  created: 'Created',
  rejected: 'Rejected',
};

export function ProposalCard({ proposal, selected, onSelect, onClick }: ProposalCardProps) {
  const proposedBy = proposal.proposed_by_agent?.name || proposal.proposed_by_user?.name || 'Unknown';
  const isAgent = !!proposal.proposed_by_agent;

  return (
    <Card
      variant="outlined"
      padding="sm"
      hoverable
      clickable
      selected={selected}
      className="cursor-pointer"
      onClick={() => onClick(proposal.id)}
      data-testid={`proposal-card-${proposal.id}`}
    >
      <div className="flex items-start gap-3">
        {onSelect && (
          <input
            type="checkbox"
            checked={selected}
            onChange={(e) => {
              e.stopPropagation();
              onSelect(proposal.id);
            }}
            className="mt-1 rounded border-theme"
            onClick={(e) => e.stopPropagation()}
          />
        )}

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <FileText className="w-4 h-4 text-theme-secondary flex-shrink-0" />
            <span className="font-medium text-theme-primary truncate">{proposal.name}</span>
            <Badge variant={STATUS_VARIANTS[proposal.status]} size="xs">
              {STATUS_LABELS[proposal.status]}
            </Badge>
            {proposal.auto_approved && (
              <Badge variant="warning" size="xs">Auto</Badge>
            )}
          </div>

          {proposal.description && (
            <p className="text-sm text-theme-secondary line-clamp-2 mb-2">{proposal.description}</p>
          )}

          <div className="flex items-center gap-4 text-xs text-theme-tertiary">
            <span className="flex items-center gap-1">
              {isAgent ? <Bot className="w-3 h-3" /> : <User className="w-3 h-3" />}
              {proposedBy}
            </span>
            {proposal.category && (
              <span className="capitalize">{proposal.category.replace(/_/g, ' ')}</span>
            )}
            {proposal.confidence_score > 0 && (
              <span>{Math.round(proposal.confidence_score * 100)}% confidence</span>
            )}
            <span className="flex items-center gap-1">
              <Clock className="w-3 h-3" />
              {new Date(proposal.created_at).toLocaleDateString()}
            </span>
          </div>
        </div>
      </div>
    </Card>
  );
}
