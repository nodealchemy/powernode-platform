import { useState, useEffect } from 'react';
import { skillsApi } from '../services/skillsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiSkill, McpServerInfo } from '../types';

interface AgentSummary {
  id: string;
  name: string;
  agent_type: string;
  status: string;
}

function AgentsList({ skillId }: { skillId: string }) {
  const [agents, setAgents] = useState<AgentSummary[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const res = await skillsApi.getSkillAgents(skillId);
      if (res.success && res.data?.agents) {
        setAgents(res.data.agents);
      } else {
        setAgents([]);
      }
      setLoading(false);
    };
    load();
  }, [skillId]);

  if (loading) return null;
  if (agents.length === 0) return null;

  return (
    <div>
      <h3 className="text-sm font-medium text-theme-primary mb-2">Agents with this skill</h3>
      <div className="flex flex-wrap gap-2">
        {agents.map((agent) => (
          <Badge key={agent.id} variant={agent.status === 'active' ? 'success' : 'secondary'} size="sm">
            {agent.name}
          </Badge>
        ))}
      </div>
    </div>
  );
}

function getServerStatusColor(status: string): string {
  switch (status) {
    case 'connected':
    case 'running':
      return 'bg-theme-success';
    case 'connecting':
    case 'deploying':
    case 'building':
    case 'provisioning':
      return 'bg-theme-warning';
    case 'error':
    case 'failed':
      return 'bg-theme-error';
    default:
      return 'bg-theme-surface-secondary';
  }
}

function getServerStatusText(status: string): string {
  switch (status) {
    case 'connected':
    case 'running':
      return 'text-theme-success';
    case 'connecting':
    case 'deploying':
    case 'building':
    case 'provisioning':
      return 'text-theme-warning';
    case 'error':
    case 'failed':
      return 'text-theme-error';
    default:
      return 'text-theme-tertiary';
  }
}

function McpServerCard({ server }: { server: McpServerInfo }) {
  const hasHosting = server.hosting?.container_backed;

  return (
    <div className="bg-theme-surface-secondary rounded-lg p-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${getServerStatusColor(server.status)}`} />
          <span className="text-sm font-medium text-theme-primary">{server.name}</span>
        </div>
        <span className={`text-xs ${getServerStatusText(server.status)}`}>
          {server.status}
        </span>
      </div>
      {hasHosting && server.hosting && (
        <div className="mt-2 flex items-center gap-2">
          <span className="text-xs px-1.5 py-0.5 rounded bg-theme-info bg-opacity-10 text-theme-info">
            Containerized
          </span>
          {server.hosting.runtime && (
            <span className="text-xs text-theme-tertiary">
              {server.hosting.runtime}
            </span>
          )}
          {server.hosting.memory_mb && (
            <span className="text-xs text-theme-tertiary">
              {server.hosting.memory_mb}MB
            </span>
          )}
          {server.hosting.container_status && (
            <span className={`text-xs ${getServerStatusText(server.hosting.container_status)}`}>
              {server.hosting.container_status}
            </span>
          )}
        </div>
      )}
    </div>
  );
}

interface SkillDetailPanelProps {
  skillId: string;
  onClose: () => void;
  onUpdated: () => void;
}

export function SkillDetailPanel({ skillId, onClose, onUpdated }: SkillDetailPanelProps) {
  const { showNotification } = useNotifications();
  const [skill, setSkill] = useState<AiSkill | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadSkill();
  }, [skillId]);

  const loadSkill = async () => {
    setLoading(true);
    const response = await skillsApi.getSkill(skillId);
    if (response.success && response.data) {
      setSkill(response.data.skill);
    } else {
      showNotification(response.error || 'Failed to load skill', 'error');
    }
    setLoading(false);
  };

  const handleToggle = async () => {
    if (!skill) return;
    const response = skill.is_enabled
      ? await skillsApi.deactivateSkill(skill.id)
      : await skillsApi.activateSkill(skill.id);

    if (response.success) {
      showNotification(`Skill ${skill.is_enabled ? 'deactivated' : 'activated'}`, 'success');
      loadSkill();
      onUpdated();
    } else {
      showNotification(response.error || 'Failed to toggle skill', 'error');
    }
  };

  const handleDelete = async () => {
    if (!skill || skill.is_system) return;
    const response = await skillsApi.deleteSkill(skill.id);
    if (response.success) {
      showNotification('Skill deleted', 'success');
      onClose();
      onUpdated();
    } else {
      showNotification(response.error || 'Failed to delete skill', 'error');
    }
  };

  if (loading) {
    return (
      <div className="fixed inset-y-0 right-0 w-full max-w-lg bg-theme-surface border-l border-theme shadow-xl z-50 p-6">
        <div className="animate-pulse space-y-4">
          <div className="h-6 bg-theme-surface-secondary rounded w-3/4" />
          <div className="h-4 bg-theme-surface-secondary rounded w-1/2" />
          <div className="h-32 bg-theme-surface-secondary rounded" />
        </div>
      </div>
    );
  }

  if (!skill) return null;

  const icon = skillsApi.getCategoryIcon(skill.category);
  const categoryLabel = skillsApi.getCategoryLabel(skill.category);
  const containerBackedCount = skill.connectors.filter(c => c.hosting?.container_backed).length;

  return (
    <div className="fixed inset-y-0 right-0 w-full max-w-lg bg-theme-surface border-l border-theme shadow-xl z-50 overflow-y-auto">
      <div className="p-6 space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <span className="text-3xl">{icon}</span>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">{skill.name}</h2>
              <div className="flex items-center gap-2 mt-1">
                <span className="px-2 py-0.5 text-xs rounded-full bg-theme-surface-secondary text-theme-secondary">
                  {categoryLabel}
                </span>
                <span className={`px-2 py-0.5 text-xs rounded-full ${
                  skill.is_enabled
                    ? 'bg-theme-success bg-opacity-10 text-theme-success'
                    : 'bg-theme-surface-secondary text-theme-tertiary'
                }`}>
                  {skill.is_enabled ? 'Enabled' : 'Disabled'}
                </span>
                {skill.is_system && (
                  <span className="px-2 py-0.5 text-xs rounded-full bg-theme-info bg-opacity-10 text-theme-info">
                    System
                  </span>
                )}
              </div>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-theme-tertiary hover:text-theme-primary text-xl"
            aria-label="Close"
          >
            &times;
          </button>
        </div>

        {/* Description */}
        <div>
          <h3 className="text-sm font-medium text-theme-primary mb-1">Description</h3>
          <p className="text-sm text-theme-secondary">{skill.description}</p>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-theme-surface-secondary rounded-lg p-3 text-center">
            <div className="text-lg font-semibold text-theme-primary">{skill.command_count}</div>
            <div className="text-xs text-theme-tertiary">Commands</div>
          </div>
          <div className="bg-theme-surface-secondary rounded-lg p-3 text-center">
            <div className="text-lg font-semibold text-theme-primary">{skill.connector_count}</div>
            <div className="text-xs text-theme-tertiary">MCP Servers</div>
          </div>
          <div className="bg-theme-surface-secondary rounded-lg p-3 text-center">
            <div className="text-lg font-semibold text-theme-primary">{skill.usage_count}</div>
            <div className="text-xs text-theme-tertiary">Uses</div>
          </div>
        </div>

        {/* Container Info Banner */}
        {containerBackedCount > 0 && (
          <div className="bg-theme-info bg-opacity-5 border border-theme-info border-opacity-20 rounded-lg p-3">
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium text-theme-info">
                {containerBackedCount} containerized MCP server{containerBackedCount > 1 ? 's' : ''}
              </span>
            </div>
            <p className="text-xs text-theme-secondary mt-1">
              Sandboxed containers with read-only root, dropped capabilities, and resource limits.
            </p>
          </div>
        )}

        {/* Commands */}
        {skill.commands && skill.commands.length > 0 && (
          <div>
            <h3 className="text-sm font-medium text-theme-primary mb-2">Commands</h3>
            <div className="space-y-2">
              {skill.commands.map((cmd, idx) => (
                <div key={idx} className="bg-theme-surface-secondary rounded-lg p-3">
                  <div className="flex items-center gap-2">
                    <code className="text-xs font-mono bg-theme-surface px-1.5 py-0.5 rounded text-theme-info">
                      /{cmd.name}
                    </code>
                    {cmd.argument_hint && (
                      <span className="text-xs text-theme-tertiary">{cmd.argument_hint}</span>
                    )}
                  </div>
                  <p className="text-xs text-theme-secondary mt-1">{cmd.description}</p>
                  {cmd.workflow_steps && cmd.workflow_steps.length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-1">
                      {cmd.workflow_steps.map((step, sIdx) => (
                        <span key={sIdx} className="text-xs px-1.5 py-0.5 rounded bg-theme-surface text-theme-tertiary">
                          {sIdx + 1}. {step}
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* MCP Servers */}
        {skill.connectors && skill.connectors.length > 0 && (
          <div>
            <h3 className="text-sm font-medium text-theme-primary mb-2">MCP Servers</h3>
            <div className="space-y-2">
              {skill.connectors.map((server) => (
                <McpServerCard key={server.id} server={server} />
              ))}
            </div>
          </div>
        )}

        {/* Knowledge Base */}
        {skill.knowledge_base && (
          <div>
            <h3 className="text-sm font-medium text-theme-primary mb-1">Knowledge Base</h3>
            <div className="bg-theme-surface-secondary rounded-lg p-3 text-sm text-theme-secondary">
              {skill.knowledge_base.name}
            </div>
          </div>
        )}

        {/* Tags */}
        {skill.tags.length > 0 && (
          <div>
            <h3 className="text-sm font-medium text-theme-primary mb-2">Tags</h3>
            <div className="flex flex-wrap gap-1">
              {skill.tags.map((tag) => (
                <span key={tag} className="px-2 py-0.5 text-xs rounded bg-theme-surface-secondary text-theme-tertiary">
                  {tag}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* System Prompt Preview */}
        {skill.system_prompt && (
          <div>
            <h3 className="text-sm font-medium text-theme-primary mb-1">System Prompt</h3>
            <pre className="bg-theme-surface-secondary rounded-lg p-3 text-xs text-theme-secondary whitespace-pre-wrap max-h-48 overflow-y-auto">
              {skill.system_prompt}
            </pre>
          </div>
        )}

        {/* Agents with this skill */}
        <AgentsList skillId={skillId} />

        {/* Actions */}
        <div className="flex gap-3 pt-4 border-t border-theme">
          <Button variant="secondary" onClick={handleToggle}>
            {skill.is_enabled ? 'Disable' : 'Enable'}
          </Button>
          {!skill.is_system && (
            <Button
              variant="secondary"
              onClick={handleDelete}
              className="text-theme-error hover:text-theme-error"
            >
              Delete
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
