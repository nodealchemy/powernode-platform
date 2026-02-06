import { useState, useEffect } from 'react';
import { skillsApi } from '../services/skillsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiSkill } from '../types';

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
            <div className="text-xs text-theme-tertiary">Connectors</div>
          </div>
          <div className="bg-theme-surface-secondary rounded-lg p-3 text-center">
            <div className="text-lg font-semibold text-theme-primary">{skill.usage_count}</div>
            <div className="text-xs text-theme-tertiary">Uses</div>
          </div>
        </div>

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

        {/* Connectors */}
        {skill.connectors && skill.connectors.length > 0 && (
          <div>
            <h3 className="text-sm font-medium text-theme-primary mb-2">MCP Connectors</h3>
            <div className="flex flex-wrap gap-2">
              {skill.connectors.map((conn) => (
                <span
                  key={conn.id}
                  className={`inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full border border-theme ${
                    conn.status === 'connected'
                      ? 'text-theme-success'
                      : 'text-theme-tertiary'
                  }`}
                >
                  <span className={`w-1.5 h-1.5 rounded-full ${
                    conn.status === 'connected' ? 'bg-theme-success' : 'bg-theme-surface-secondary'
                  }`} />
                  {conn.name}
                </span>
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
