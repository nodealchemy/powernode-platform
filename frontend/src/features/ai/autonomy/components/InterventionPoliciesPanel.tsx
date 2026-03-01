import React, { useState } from 'react';
import {
  Settings, Shield, Trash2, ToggleLeft, ToggleRight, ChevronDown, Plus, Pencil, FlaskConical,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  useInterventionPolicies,
  useCreateInterventionPolicy,
  useUpdateInterventionPolicy,
  useDeleteInterventionPolicy,
  useResolveInterventionPolicy,
  useTrustScores,
} from '../api/autonomyApi';
import type { InterventionPolicy, InterventionPolicyAction, PolicyResolutionResult } from '../types/autonomy';

function getPolicyColor(policy: InterventionPolicyAction): string {
  switch (policy) {
    case 'auto_approve': return 'text-theme-success bg-theme-success/10';
    case 'notify_and_proceed': return 'text-theme-info bg-theme-info/10';
    case 'require_approval': return 'text-theme-warning bg-theme-warning/10';
    case 'block': return 'text-theme-error bg-theme-error/10';
    case 'silent': return 'text-theme-muted bg-theme-surface';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

const POLICY_TYPES: InterventionPolicyAction[] = ['auto_approve', 'notify_and_proceed', 'require_approval', 'silent', 'block'];
const SCOPES = ['global', 'agent', 'action_type'] as const;
const CHANNELS = ['email', 'slack', 'webhook', 'in_app'] as const;

interface PolicyFormData {
  scope: string;
  action_category: string;
  policy: InterventionPolicyAction;
  priority: number;
  preferred_channels: string[];
  conditions: Record<string, string>;
  agent_id?: string;
}

const emptyPolicyForm: PolicyFormData = {
  scope: 'global', action_category: '', policy: 'require_approval', priority: 50,
  preferred_channels: [], conditions: {},
};

const PolicyForm: React.FC<{
  initial?: PolicyFormData;
  agents: Array<{ id: string; name: string }>;
  onSubmit: (data: PolicyFormData) => void;
  onCancel: () => void;
  submitting: boolean;
  submitLabel: string;
}> = ({ initial = emptyPolicyForm, agents, onSubmit, onCancel, submitting, submitLabel }) => {
  const [form, setForm] = useState<PolicyFormData>(initial);
  const [condKey, setCondKey] = useState('');
  const [condVal, setCondVal] = useState('');

  const addCondition = () => {
    if (!condKey.trim()) return;
    setForm(prev => ({ ...prev, conditions: { ...prev.conditions, [condKey]: condVal } }));
    setCondKey(''); setCondVal('');
  };

  const removeCondition = (key: string) => {
    setForm(prev => {
      const next = { ...prev.conditions };
      delete next[key];
      return { ...prev, conditions: next };
    });
  };

  const toggleChannel = (ch: string) => {
    setForm(prev => ({
      ...prev,
      preferred_channels: prev.preferred_channels.includes(ch)
        ? prev.preferred_channels.filter(c => c !== ch)
        : [...prev.preferred_channels, ch],
    }));
  };

  return (
    <div className="space-y-3 p-4 bg-theme-background border border-theme rounded-lg">
      <div className="flex gap-3">
        <select
          value={form.scope}
          onChange={(e) => setForm(prev => ({ ...prev, scope: e.target.value }))}
          className="w-36 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          {SCOPES.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
        <input
          type="text"
          value={form.action_category}
          onChange={(e) => setForm(prev => ({ ...prev, action_category: e.target.value }))}
          placeholder="Action category"
          className="flex-1 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        />
        <select
          value={form.policy}
          onChange={(e) => setForm(prev => ({ ...prev, policy: e.target.value as InterventionPolicyAction }))}
          className="w-48 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          {POLICY_TYPES.map(p => <option key={p} value={p}>{p.replace(/_/g, ' ')}</option>)}
        </select>
      </div>
      <div className="flex gap-3 items-center">
        <label className="text-sm text-theme-muted">Priority:</label>
        <input
          type="number"
          value={form.priority}
          onChange={(e) => setForm(prev => ({ ...prev, priority: Number(e.target.value) }))}
          className="w-20 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
          min={0}
          max={100}
        />
        {form.scope === 'agent' && (
          <select
            value={form.agent_id ?? ''}
            onChange={(e) => setForm(prev => ({ ...prev, agent_id: e.target.value || undefined }))}
            className="flex-1 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
          >
            <option value="">Select agent...</option>
            {agents.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        )}
      </div>
      {/* Channels */}
      <div className="flex items-center gap-2">
        <span className="text-sm text-theme-muted">Channels:</span>
        {CHANNELS.map(ch => (
          <label key={ch} className="flex items-center gap-1 text-xs text-theme-secondary">
            <input
              type="checkbox"
              checked={form.preferred_channels.includes(ch)}
              onChange={() => toggleChannel(ch)}
              className="rounded border-theme"
            />
            {ch}
          </label>
        ))}
      </div>
      {/* Conditions builder */}
      <div>
        <span className="text-sm text-theme-muted">Conditions:</span>
        <div className="flex gap-2 mt-1">
          <input type="text" value={condKey} onChange={(e) => setCondKey(e.target.value)} placeholder="Key" className="w-32 px-2 py-1 text-xs rounded border border-theme bg-theme-surface text-theme-primary" />
          <input type="text" value={condVal} onChange={(e) => setCondVal(e.target.value)} placeholder="Value" className="flex-1 px-2 py-1 text-xs rounded border border-theme bg-theme-surface text-theme-primary" />
          <button onClick={addCondition} className="btn-theme btn-theme-secondary btn-theme-sm text-xs">Add</button>
        </div>
        {Object.keys(form.conditions).length > 0 && (
          <div className="flex flex-wrap gap-1 mt-2">
            {Object.entries(form.conditions).map(([k, v]) => (
              <span key={k} className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded bg-theme-surface border border-theme text-theme-secondary">
                {k}: {v} <button onClick={() => removeCondition(k)} className="text-theme-error">&times;</button>
              </span>
            ))}
          </div>
        )}
      </div>
      <div className="flex gap-2">
        <button
          onClick={() => onSubmit(form)}
          disabled={submitting || !form.action_category.trim()}
          className="btn-theme btn-theme-primary btn-theme-sm"
        >
          {submitting ? 'Saving...' : submitLabel}
        </button>
        <button onClick={onCancel} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
      </div>
    </div>
  );
};

const PolicyCard: React.FC<{
  policy: InterventionPolicy;
  isExpanded: boolean;
  onToggle: () => void;
  agents: Array<{ id: string; name: string }>;
}> = ({ policy, isExpanded, onToggle, agents }) => {
  const [editing, setEditing] = useState(false);
  const updatePolicy = useUpdateInterventionPolicy();
  const deletePolicy = useDeleteInterventionPolicy();
  const { addNotification } = useNotifications();

  const handleToggleActive = async () => {
    try {
      await updatePolicy.mutateAsync({ id: policy.id, is_active: !policy.is_active });
      addNotification({ type: 'success', message: `Policy ${policy.is_active ? 'disabled' : 'enabled'}` });
    } catch {
      addNotification({ type: 'error', message: 'Failed to update policy' });
    }
  };

  const handleEdit = async (data: PolicyFormData) => {
    try {
      await updatePolicy.mutateAsync({
        id: policy.id,
        scope: data.scope,
        action_category: data.action_category,
        policy: data.policy,
        priority: data.priority,
        preferred_channels: data.preferred_channels,
        conditions: data.conditions,
      } as Parameters<typeof updatePolicy.mutateAsync>[0]);
      addNotification({ type: 'success', message: 'Policy updated' });
      setEditing(false);
    } catch {
      addNotification({ type: 'error', message: 'Failed to update policy' });
    }
  };

  const handleDelete = async () => {
    if (!window.confirm('Delete this intervention policy?')) return;
    try {
      await deletePolicy.mutateAsync(policy.id);
      addNotification({ type: 'success', message: 'Policy deleted' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to delete policy' });
    }
  };

  return (
    <div className={`bg-theme-surface border border-theme rounded-lg overflow-hidden ${!policy.is_active ? 'opacity-60' : ''}`}>
      {/* Collapsed header */}
      <div
        onClick={onToggle}
        className="flex items-center gap-3 p-4 cursor-pointer hover:bg-theme-background/50 transition-colors"
      >
        <Shield className="h-4 w-4 text-theme-info shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className={`px-2 py-0.5 text-xs rounded font-medium ${getPolicyColor(policy.policy)}`}>
              {policy.policy.replace(/_/g, ' ')}
            </span>
            <span className="px-1.5 py-0.5 text-xs rounded bg-theme-surface text-theme-muted">{policy.scope}</span>
            <span className="text-xs text-theme-primary">{policy.action_category}</span>
            <span className="text-xs text-theme-muted">P{policy.priority}</span>
          </div>
          <div className="flex items-center gap-3 text-xs text-theme-muted mt-0.5">
            {policy.agent?.name && <span>Agent: {policy.agent.name}</span>}
          </div>
        </div>
        <button
          onClick={(e) => { e.stopPropagation(); handleToggleActive(); }}
          className="shrink-0"
          title={policy.is_active ? 'Disable' : 'Enable'}
        >
          {policy.is_active ? <ToggleRight className="h-5 w-5 text-theme-success" /> : <ToggleLeft className="h-5 w-5 text-theme-muted" />}
        </button>
        <ChevronDown className={`h-4 w-4 text-theme-muted shrink-0 transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
      </div>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="border-t border-theme p-4 space-y-4">
          {editing ? (
            <PolicyForm
              initial={{
                scope: policy.scope,
                action_category: policy.action_category,
                policy: policy.policy,
                priority: policy.priority,
                preferred_channels: [...policy.preferred_channels],
                conditions: { ...(policy.conditions as Record<string, string>) },
                agent_id: policy.agent?.id,
              }}
              agents={agents}
              onSubmit={handleEdit}
              onCancel={() => setEditing(false)}
              submitting={updatePolicy.isPending}
              submitLabel="Save Changes"
            />
          ) : (
            <>
              {/* Conditions */}
              {Object.keys(policy.conditions).length > 0 && (
                <div>
                  <h4 className="text-sm font-medium text-theme-primary mb-1">Conditions</h4>
                  <div className="text-xs bg-theme-background border border-theme rounded p-3 space-y-1">
                    {Object.entries(policy.conditions).map(([key, value]) => (
                      <p key={key} className="text-theme-secondary">
                        <span className="font-medium">{key}: </span>
                        {typeof value === 'string' ? value : JSON.stringify(value)}
                      </p>
                    ))}
                  </div>
                </div>
              )}

              {/* Channels */}
              {policy.preferred_channels.length > 0 && (
                <div>
                  <h4 className="text-sm font-medium text-theme-primary mb-1">Preferred Channels</h4>
                  <div className="flex gap-1">
                    {policy.preferred_channels.map(ch => (
                      <span key={ch} className="text-xs px-2 py-0.5 bg-theme-info/10 text-theme-info rounded">{ch}</span>
                    ))}
                  </div>
                </div>
              )}

              {/* Timestamps */}
              <div className="flex gap-4 text-xs text-theme-muted">
                <span>Created {new Date(policy.created_at).toLocaleString()}</span>
                <span>Updated {new Date(policy.updated_at).toLocaleString()}</span>
              </div>

              {/* Actions */}
              <div className="flex gap-2">
                <button
                  onClick={() => setEditing(true)}
                  className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
                >
                  <Pencil className="h-3 w-3" /> Edit
                </button>
                <button
                  onClick={handleDelete}
                  disabled={deletePolicy.isPending}
                  className="btn-theme btn-theme-danger btn-theme-sm flex items-center gap-1"
                >
                  <Trash2 className="h-3 w-3" /> Delete
                </button>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
};

const TestResolveForm: React.FC = () => {
  const [actionCategory, setActionCategory] = useState('');
  const [agentId, setAgentId] = useState('');
  const [result, setResult] = useState<PolicyResolutionResult | null>(null);
  const resolveMutation = useResolveInterventionPolicy();
  const { data: trustScores } = useTrustScores();
  const agents = (trustScores ?? []).map(ts => ({ id: ts.agent_id, name: ts.agent_name }));

  const handleTest = async () => {
    try {
      const res = await resolveMutation.mutateAsync({
        action_category: actionCategory,
        agent_id: agentId || undefined,
      });
      setResult(res);
    } catch {
      setResult(null);
    }
  };

  return (
    <div className="p-4 bg-theme-background border border-theme rounded-lg space-y-3">
      <h4 className="text-sm font-medium text-theme-primary flex items-center gap-1">
        <FlaskConical className="h-4 w-4" /> Test Policy Resolution
      </h4>
      <div className="flex gap-2">
        <input
          type="text"
          value={actionCategory}
          onChange={(e) => setActionCategory(e.target.value)}
          placeholder="Action category"
          className="flex-1 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        />
        <select
          value={agentId}
          onChange={(e) => setAgentId(e.target.value)}
          className="w-48 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          <option value="">Any agent</option>
          {agents.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
        <button
          onClick={handleTest}
          disabled={resolveMutation.isPending || !actionCategory.trim()}
          className="btn-theme btn-theme-primary btn-theme-sm"
        >
          {resolveMutation.isPending ? 'Testing...' : 'Test'}
        </button>
      </div>
      {result && (
        <div className="text-xs bg-theme-surface border border-theme rounded p-3 space-y-1">
          <p className="text-theme-secondary"><span className="font-medium">Resolved policy:</span> {result.policy}</p>
          <p className="text-theme-secondary"><span className="font-medium">Action category:</span> {result.action_category}</p>
          {result.matched_policy_id && <p className="text-theme-secondary"><span className="font-medium">Matched ID:</span> {result.matched_policy_id}</p>}
          <p className="text-theme-secondary"><span className="font-medium">Reason:</span> {result.reason}</p>
        </div>
      )}
    </div>
  );
};

export const InterventionPoliciesPanel: React.FC = () => {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [showTest, setShowTest] = useState(false);
  const { data: policies, isLoading } = useInterventionPolicies();
  const { data: trustScores } = useTrustScores();
  const createPolicy = useCreateInterventionPolicy();
  const { addNotification } = useNotifications();

  const agents = (trustScores ?? []).map(ts => ({ id: ts.agent_id, name: ts.agent_name }));

  const handleCreate = async (data: PolicyFormData) => {
    try {
      await createPolicy.mutateAsync({
        scope: data.scope,
        action_category: data.action_category,
        policy: data.policy,
        priority: data.priority,
        preferred_channels: data.preferred_channels,
        conditions: data.conditions,
        ...(data.agent_id ? { agent_id: data.agent_id } : {}),
      } as Parameters<typeof createPolicy.mutateAsync>[0]);
      addNotification({ type: 'success', message: 'Policy created' });
      setShowCreate(false);
    } catch {
      addNotification({ type: 'error', message: 'Failed to create policy' });
    }
  };

  if (isLoading) return <LoadingSpinner size="lg" className="py-12" message="Loading policies..." />;

  const safePolicies = policies ?? [];

  return (
    <div className="space-y-4">
      {/* Summary */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {POLICY_TYPES.map((policyType) => {
          const count = safePolicies.filter(p => p.policy === policyType).length;
          return (
            <Card key={policyType} className="p-3">
              <p className="text-xs text-theme-muted capitalize">{policyType.replace(/_/g, ' ')}</p>
              <p className="text-lg font-semibold text-theme-primary">{count}</p>
            </Card>
          );
        })}
      </div>

      {/* Controls */}
      <div className="flex items-center gap-2">
        <button
          onClick={() => { setShowCreate(prev => !prev); setShowTest(false); }}
          className="btn-theme btn-theme-primary btn-theme-sm flex items-center gap-1"
        >
          <Plus className="h-3.5 w-3.5" /> Create Policy
        </button>
        <button
          onClick={() => { setShowTest(prev => !prev); setShowCreate(false); }}
          className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
        >
          <FlaskConical className="h-3.5 w-3.5" /> Test Resolution
        </button>
      </div>

      {/* Create form */}
      {showCreate && (
        <PolicyForm
          agents={agents}
          onSubmit={handleCreate}
          onCancel={() => setShowCreate(false)}
          submitting={createPolicy.isPending}
          submitLabel="Create Policy"
        />
      )}

      {/* Test resolution */}
      {showTest && <TestResolveForm />}

      {/* Policy list */}
      {safePolicies.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <Settings className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No intervention policies configured. Default capability matrix rules apply.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {safePolicies.map((policy) => (
            <PolicyCard
              key={policy.id}
              policy={policy}
              isExpanded={expandedId === policy.id}
              onToggle={() => setExpandedId(prev => prev === policy.id ? null : policy.id)}
              agents={agents}
            />
          ))}
        </div>
      )}
    </div>
  );
};
