import React from 'react';
import { Bot, Crown, Loader2, X } from 'lucide-react';
import { TeamMember } from '../services/agentTeamsApi';

interface MembersListProps {
  members: TeamMember[];
  removingMemberId: string | null;
  onRemoveMember: (memberId: string) => void;
}

export const MembersList: React.FC<MembersListProps> = ({
  members,
  removingMemberId,
  onRemoveMember,
}) => {
  return (
    <div className="bg-theme-background border border-theme rounded-lg p-4">
      <h4 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
        <Bot size={16} />
        Members ({members.length})
      </h4>
      {members.length === 0 ? (
        <div className="text-sm text-theme-secondary py-6 text-center">No members assigned</div>
      ) : (
        <div className="space-y-2">
          {members.map((member) => (
            <div
              key={member.id}
              className="flex items-center gap-3 p-3 rounded-md bg-theme-surface border border-theme"
            >
              <Bot className="h-5 w-5 text-theme-info flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-theme-primary truncate">
                    {member.agent_name}
                  </span>
                  {member.is_lead && (
                    <Crown className="h-3.5 w-3.5 text-theme-warning flex-shrink-0" />
                  )}
                </div>
                <div className="flex items-center gap-2 mt-0.5">
                  <span className="text-xs font-medium text-theme-interactive-primary bg-theme-interactive-primary/10 px-1.5 py-0.5 rounded">
                    {member.role}
                  </span>
                  {member.capabilities.length > 0 && (
                    <span className="text-xs text-theme-secondary truncate">
                      {member.capabilities.join(', ')}
                    </span>
                  )}
                </div>
              </div>
              <span className="text-xs text-theme-secondary flex-shrink-0 tabular-nums">
                #{member.priority_order}
              </span>
              <button
                onClick={() => onRemoveMember(member.id)}
                disabled={removingMemberId === member.id}
                className="flex-shrink-0 p-1 rounded hover:bg-theme-error/10 text-theme-secondary hover:text-theme-danger transition-colors disabled:opacity-50"
                title="Remove member"
              >
                {removingMemberId === member.id ? (
                  <Loader2 size={14} className="animate-spin" />
                ) : (
                  <X size={14} />
                )}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
