import React from 'react';
import { X } from 'lucide-react';
import type { MemberDetailPanel } from './executionDiagramTypes';

interface MemberDetailSidebarProps {
  member: MemberDetailPanel;
  onClose: () => void;
}

export const MemberDetailSidebar: React.FC<MemberDetailSidebarProps> = ({ member, onClose }) => (
  <div className="absolute top-3 right-3 w-56 bg-theme-surface border border-theme rounded-lg shadow-xl p-3 z-10">
    <div className="flex items-center justify-between mb-2">
      <span className="text-sm font-semibold text-theme-primary">{member.memberName}</span>
      <button
        type="button"
        onClick={onClose}
        className="text-theme-secondary hover:text-theme-primary"
      >
        <X size={14} />
      </button>
    </div>
    <div className="space-y-1.5 text-xs">
      <div className="flex justify-between">
        <span className="text-theme-secondary">Role</span>
        <span className="text-theme-primary font-medium">{member.role}</span>
      </div>
      {member.isLead && (
        <div className="flex justify-between">
          <span className="text-theme-secondary">Lead</span>
          <span className="text-theme-warning font-medium">Yes</span>
        </div>
      )}
      <div className="flex justify-between">
        <span className="text-theme-secondary">Status</span>
        <span className={`font-medium ${
          member.status === 'completed' ? 'text-theme-success' :
          member.status === 'failed' ? 'text-theme-danger' :
          member.status === 'running' ? 'text-theme-info' :
          'text-theme-secondary'
        }`}>
          {member.status}
        </span>
      </div>
      {member.durationMs !== undefined && (
        <div className="flex justify-between">
          <span className="text-theme-secondary">Duration</span>
          <span className="text-theme-primary">
            {member.durationMs < 1000
              ? `${member.durationMs}ms`
              : `${(member.durationMs / 1000).toFixed(1)}s`}
          </span>
        </div>
      )}
      {member.capabilities.length > 0 && (
        <div>
          <span className="text-theme-secondary">Capabilities</span>
          <div className="flex flex-wrap gap-1 mt-1">
            {member.capabilities.map((cap) => (
              <span key={cap} className="px-1.5 py-0.5 text-[10px] rounded bg-theme-accent text-theme-secondary">
                {cap}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  </div>
);
