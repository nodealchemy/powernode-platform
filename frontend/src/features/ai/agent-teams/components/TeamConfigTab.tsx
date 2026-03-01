import React, { useState } from 'react';
import { ChevronDown, ChevronRight, UserCog, Hash, Copy } from 'lucide-react';
import type { TeamRole, TeamChannel, TeamTemplate } from '@/shared/services/ai/TeamsApiService';

interface TeamConfigTabProps {
  roles: TeamRole[];
  channels: TeamChannel[];
  templates: TeamTemplate[];
  onPublishTemplate: (templateId: string) => void;
}

interface CollapsibleSectionProps {
  title: string;
  icon: React.ReactNode;
  count: number;
  defaultOpen?: boolean;
  children: React.ReactNode;
}

const CollapsibleSection: React.FC<CollapsibleSectionProps> = ({
  title, icon, count, defaultOpen = true, children,
}) => {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className="border border-theme rounded-lg overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between px-4 py-3 bg-theme-surface hover:bg-theme-surface-hover transition-colors"
      >
        <div className="flex items-center gap-2">
          {open ? <ChevronDown size={16} className="text-theme-secondary" /> : <ChevronRight size={16} className="text-theme-secondary" />}
          {icon}
          <span className="text-sm font-medium text-theme-primary">{title}</span>
          <span className="text-xs text-theme-secondary bg-theme-bg px-1.5 py-0.5 rounded">{count}</span>
        </div>
      </button>
      {open && <div className="border-t border-theme">{children}</div>}
    </div>
  );
};

export const TeamConfigTab: React.FC<TeamConfigTabProps> = ({
  roles,
  channels,
  templates,
  onPublishTemplate,
}) => {
  return (
    <div className="space-y-4">
      {/* Roles Section */}
      <CollapsibleSection
        title="Roles"
        icon={<UserCog size={16} className="text-theme-accent" />}
        count={roles.length}
      >
        {roles.length === 0 ? (
          <div className="text-center py-8 px-4">
            <UserCog size={32} className="mx-auto text-theme-secondary mb-2" />
            <p className="text-sm text-theme-secondary">No roles defined</p>
          </div>
        ) : (
          <div className="divide-y divide-theme">
            {roles.map(role => (
              <div key={role.id} className="px-4 py-3">
                <div className="flex items-center justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-theme-primary">{role.role_name}</span>
                    <span className="px-1.5 py-0.5 text-[10px] bg-theme-accent/10 text-theme-accent rounded">{role.role_type}</span>
                    <span className="text-xs text-theme-secondary">Priority: {role.priority_order}</span>
                  </div>
                  <div className="flex gap-1.5 text-[10px]">
                    {role.can_delegate && <span className="px-1.5 py-0.5 bg-theme-info/10 text-theme-info rounded">Delegate</span>}
                    {role.can_escalate && <span className="px-1.5 py-0.5 bg-theme-warning/10 text-theme-warning rounded">Escalate</span>}
                  </div>
                </div>
                {role.role_description && <p className="text-xs text-theme-secondary mb-1">{role.role_description}</p>}
                <div className="flex gap-3 text-[11px] text-theme-secondary">
                  <span>Agent: {role.agent_name || 'Unassigned'}</span>
                  <span>Max tasks: {role.max_concurrent_tasks}</span>
                  {role.capabilities.length > 0 && <span>{role.capabilities.length} capabilities</span>}
                  {role.tools_allowed.length > 0 && <span>{role.tools_allowed.length} tools</span>}
                </div>
              </div>
            ))}
          </div>
        )}
      </CollapsibleSection>

      {/* Channels Section */}
      <CollapsibleSection
        title="Channels"
        icon={<Hash size={16} className="text-theme-accent" />}
        count={channels.length}
      >
        {channels.length === 0 ? (
          <div className="text-center py-8 px-4">
            <Hash size={32} className="mx-auto text-theme-secondary mb-2" />
            <p className="text-sm text-theme-secondary">No channels configured</p>
          </div>
        ) : (
          <div className="divide-y divide-theme">
            {channels.map(channel => (
              <div key={channel.id} className="px-4 py-3">
                <div className="flex items-center justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <Hash size={14} className="text-theme-accent" />
                    <span className="text-sm font-medium text-theme-primary">{channel.name}</span>
                    <span className="px-1.5 py-0.5 text-[10px] bg-theme-accent/10 text-theme-accent rounded">{channel.channel_type}</span>
                    {channel.is_persistent && <span className="px-1.5 py-0.5 text-[10px] bg-theme-info/10 text-theme-info rounded">Persistent</span>}
                  </div>
                  <span className="text-xs text-theme-secondary">{channel.message_count} msgs</span>
                </div>
                {channel.description && <p className="text-xs text-theme-secondary mb-1">{channel.description}</p>}
                <div className="flex gap-3 text-[11px] text-theme-secondary">
                  <span>{channel.participant_roles.length} participants</span>
                  {channel.message_retention_hours && <span>Retention: {channel.message_retention_hours}h</span>}
                </div>
              </div>
            ))}
          </div>
        )}
      </CollapsibleSection>

      {/* Templates Section */}
      <CollapsibleSection
        title="Templates"
        icon={<Copy size={16} className="text-theme-accent" />}
        count={templates.length}
        defaultOpen={false}
      >
        {templates.length === 0 ? (
          <div className="text-center py-8 px-4">
            <Copy size={32} className="mx-auto text-theme-secondary mb-2" />
            <p className="text-sm text-theme-secondary">No templates available</p>
          </div>
        ) : (
          <div className="divide-y divide-theme">
            {templates.map(template => (
              <div key={template.id} className="px-4 py-3">
                <div className="flex items-center justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-theme-primary">{template.name}</span>
                    {template.is_public && <span className="px-1.5 py-0.5 text-[10px] text-theme-success bg-theme-success/10 rounded">Published</span>}
                    {template.is_system && <span className="px-1.5 py-0.5 text-[10px] text-theme-info bg-theme-info/10 rounded">System</span>}
                  </div>
                  {!template.published_at && (
                    <button onClick={() => onPublishTemplate(template.id)} className="btn-theme btn-theme-success btn-theme-sm text-xs">
                      Publish
                    </button>
                  )}
                </div>
                <p className="text-xs text-theme-secondary">{template.description || 'No description'}</p>
                <div className="flex gap-3 text-[11px] text-theme-secondary mt-1">
                  <span>{template.team_topology}</span>
                  <span>{template.usage_count} uses</span>
                  {template.tags.length > 0 && <span>{template.tags.join(', ')}</span>}
                </div>
              </div>
            ))}
          </div>
        )}
      </CollapsibleSection>
    </div>
  );
};
