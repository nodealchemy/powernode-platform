import React, { useState } from 'react';
import {
  Target, ChevronDown, CheckCircle, XCircle, Pause, Clock, Plus, Pencil, Trash2, Play, RotateCcw,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useGoals, useCreateGoal, useUpdateGoal, useDeleteGoal } from '../api/autonomyApi';
import type { AgentGoal, GoalStatus, GoalType } from '../types/autonomy';

function getStatusIcon(status: GoalStatus) {
  switch (status) {
    case 'achieved': return <CheckCircle className="h-4 w-4 text-theme-success" />;
    case 'failed': case 'abandoned': return <XCircle className="h-4 w-4 text-theme-error" />;
    case 'paused': return <Pause className="h-4 w-4 text-theme-warning" />;
    case 'active': return <Target className="h-4 w-4 text-theme-info" />;
    default: return <Clock className="h-4 w-4 text-theme-muted" />;
  }
}

function getStatusBadgeClass(status: GoalStatus): string {
  switch (status) {
    case 'achieved': return 'text-theme-success bg-theme-success/10';
    case 'failed': case 'abandoned': return 'text-theme-error bg-theme-error/10';
    case 'paused': return 'text-theme-warning bg-theme-warning/10';
    case 'active': return 'text-theme-info bg-theme-info/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

function getPriorityLabel(priority: number): string {
  switch (priority) {
    case 1: return 'Critical';
    case 2: return 'High';
    case 3: return 'Medium';
    case 4: return 'Low';
    case 5: return 'Lowest';
    default: return `P${priority}`;
  }
}

const GOAL_TYPES: GoalType[] = ['maintenance', 'improvement', 'creation', 'monitoring', 'feature_suggestion', 'reaction'];

interface GoalFormData {
  title: string;
  description: string;
  goal_type: GoalType;
  priority: number;
  deadline: string;
}

const emptyForm: GoalFormData = { title: '', description: '', goal_type: 'improvement', priority: 3, deadline: '' };

const GoalForm: React.FC<{
  initial?: GoalFormData;
  onSubmit: (data: GoalFormData) => void;
  onCancel: () => void;
  submitting: boolean;
  submitLabel: string;
}> = ({ initial = emptyForm, onSubmit, onCancel, submitting, submitLabel }) => {
  const [form, setForm] = useState<GoalFormData>(initial);

  return (
    <div className="space-y-3 p-4 bg-theme-background border border-theme rounded-lg">
      <input
        type="text"
        value={form.title}
        onChange={(e) => setForm(prev => ({ ...prev, title: e.target.value }))}
        placeholder="Goal title"
        className="w-full px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
      />
      <textarea
        value={form.description}
        onChange={(e) => setForm(prev => ({ ...prev, description: e.target.value }))}
        placeholder="Description"
        rows={2}
        className="w-full px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
      />
      <div className="flex gap-3">
        <select
          value={form.goal_type}
          onChange={(e) => setForm(prev => ({ ...prev, goal_type: e.target.value as GoalType }))}
          className="flex-1 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          {GOAL_TYPES.map(t => <option key={t} value={t}>{t.replace('_', ' ')}</option>)}
        </select>
        <select
          value={form.priority}
          onChange={(e) => setForm(prev => ({ ...prev, priority: Number(e.target.value) }))}
          className="w-32 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          {[1, 2, 3, 4, 5].map(p => <option key={p} value={p}>{getPriorityLabel(p)}</option>)}
        </select>
        <input
          type="date"
          value={form.deadline}
          onChange={(e) => setForm(prev => ({ ...prev, deadline: e.target.value }))}
          className="w-40 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        />
      </div>
      <div className="flex gap-2">
        <button
          onClick={() => onSubmit(form)}
          disabled={submitting || !form.title.trim()}
          className="btn-theme btn-theme-primary btn-theme-sm"
        >
          {submitting ? 'Saving...' : submitLabel}
        </button>
        <button onClick={onCancel} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
      </div>
    </div>
  );
};

const GoalCard: React.FC<{
  goal: AgentGoal;
  isExpanded: boolean;
  onToggle: () => void;
}> = ({ goal, isExpanded, onToggle }) => {
  const [editing, setEditing] = useState(false);
  const updateGoal = useUpdateGoal();
  const deleteGoal = useDeleteGoal();
  const { addNotification } = useNotifications();

  const handleStatusChange = async (status: string) => {
    try {
      await updateGoal.mutateAsync({ id: goal.id, status } as Parameters<typeof updateGoal.mutateAsync>[0]);
      addNotification({ type: 'success', message: `Goal ${status}` });
    } catch {
      addNotification({ type: 'error', message: 'Failed to update goal' });
    }
  };

  const handleEdit = async (data: GoalFormData) => {
    try {
      await updateGoal.mutateAsync({
        id: goal.id,
        title: data.title,
        description: data.description,
        goal_type: data.goal_type,
        priority: data.priority,
        deadline: data.deadline || undefined,
      } as Parameters<typeof updateGoal.mutateAsync>[0]);
      addNotification({ type: 'success', message: 'Goal updated' });
      setEditing(false);
    } catch {
      addNotification({ type: 'error', message: 'Failed to update goal' });
    }
  };

  const handleDelete = async () => {
    if (!window.confirm(`Delete goal "${goal.title}"?`)) return;
    try {
      await deleteGoal.mutateAsync(goal.id);
      addNotification({ type: 'success', message: 'Goal deleted' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to delete goal' });
    }
  };

  const statusActions: Record<string, Array<{ label: string; status?: string; icon: React.ReactNode; variant: string; action?: () => void }>> = {
    pending: [
      { label: 'Activate', status: 'active', icon: <Play className="h-3 w-3" />, variant: 'btn-theme-primary' },
    ],
    active: [
      { label: 'Pause', status: 'paused', icon: <Pause className="h-3 w-3" />, variant: 'btn-theme-warning' },
      { label: 'Mark Achieved', status: 'achieved', icon: <CheckCircle className="h-3 w-3" />, variant: 'btn-theme-success' },
      { label: 'Abandon', status: 'abandoned', icon: <XCircle className="h-3 w-3" />, variant: 'btn-theme-danger' },
    ],
    paused: [
      { label: 'Resume', status: 'active', icon: <Play className="h-3 w-3" />, variant: 'btn-theme-primary' },
      { label: 'Abandon', status: 'abandoned', icon: <XCircle className="h-3 w-3" />, variant: 'btn-theme-danger' },
    ],
    achieved: [
      { label: 'Reopen', status: 'active', icon: <RotateCcw className="h-3 w-3" />, variant: 'btn-theme-primary' },
    ],
    abandoned: [
      { label: 'Reactivate', status: 'active', icon: <RotateCcw className="h-3 w-3" />, variant: 'btn-theme-primary' },
    ],
    failed: [
      { label: 'Retry', status: 'active', icon: <RotateCcw className="h-3 w-3" />, variant: 'btn-theme-primary' },
    ],
  };

  const actions = statusActions[goal.status] ?? [];

  return (
    <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
      {/* Collapsed header */}
      <div
        onClick={onToggle}
        className="flex items-center gap-3 p-4 cursor-pointer hover:bg-theme-background/50 transition-colors"
      >
        {getStatusIcon(goal.status)}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h4 className="font-medium text-theme-primary truncate">{goal.title}</h4>
            <span className={`px-2 py-0.5 text-xs rounded ${getStatusBadgeClass(goal.status)}`}>{goal.status}</span>
            <span className="px-1.5 py-0.5 text-xs rounded bg-theme-surface text-theme-muted">{goal.goal_type.replace('_', ' ')}</span>
            <span className="text-xs text-theme-muted">{getPriorityLabel(goal.priority)}</span>
          </div>
          <div className="flex items-center gap-3 text-xs text-theme-muted mt-0.5">
            {goal.agent?.name && <span>{goal.agent.name}</span>}
            {goal.deadline && <span>Due {new Date(goal.deadline).toLocaleDateString()}</span>}
          </div>
        </div>
        {/* Compact progress bar for active goals */}
        {goal.status === 'active' && (
          <div className="w-20 flex items-center gap-1.5 shrink-0">
            <div className="flex-1 h-1.5 bg-theme-secondary/20 rounded-full overflow-hidden">
              <div className="h-full bg-theme-info rounded-full" style={{ width: `${Math.round(goal.progress * 100)}%` }} />
            </div>
            <span className="text-xs text-theme-muted">{Math.round(goal.progress * 100)}%</span>
          </div>
        )}
        <ChevronDown className={`h-4 w-4 text-theme-muted shrink-0 transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
      </div>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="border-t border-theme p-4 space-y-4">
          {editing ? (
            <GoalForm
              initial={{
                title: goal.title,
                description: goal.description ?? '',
                goal_type: goal.goal_type,
                priority: goal.priority,
                deadline: goal.deadline ? goal.deadline.substring(0, 10) : '',
              }}
              onSubmit={handleEdit}
              onCancel={() => setEditing(false)}
              submitting={updateGoal.isPending}
              submitLabel="Save Changes"
            />
          ) : (
            <>
              {goal.description && (
                <p className="text-sm text-theme-secondary">{goal.description}</p>
              )}

              {/* Progress */}
              <div>
                <div className="flex items-center justify-between text-sm text-theme-muted mb-1">
                  <span>Progress</span>
                  <span>{Math.round(goal.progress * 100)}%</span>
                </div>
                <div className="h-2 bg-theme-secondary/20 rounded-full overflow-hidden">
                  <div className="h-full bg-theme-info rounded-full" style={{ width: `${Math.round(goal.progress * 100)}%` }} />
                </div>
              </div>

              {/* Success criteria */}
              {Object.keys(goal.success_criteria).length > 0 && (
                <div>
                  <h4 className="text-sm font-medium text-theme-primary mb-1">Success Criteria</h4>
                  <pre className="text-xs bg-theme-background border border-theme rounded p-3 overflow-auto text-theme-secondary">
                    {JSON.stringify(goal.success_criteria, null, 2)}
                  </pre>
                </div>
              )}

              {/* Timestamps */}
              <div className="flex gap-4 text-xs text-theme-muted">
                <span>Created {new Date(goal.created_at).toLocaleString()}</span>
                <span>Updated {new Date(goal.updated_at).toLocaleString()}</span>
                {goal.deadline && <span>Deadline {new Date(goal.deadline).toLocaleDateString()}</span>}
              </div>

              {/* Actions */}
              <div className="flex flex-wrap gap-2">
                {actions.map(({ label, status, icon, variant }) => (
                  <button
                    key={label}
                    onClick={() => status && handleStatusChange(status)}
                    disabled={updateGoal.isPending}
                    className={`btn-theme ${variant} btn-theme-sm flex items-center gap-1`}
                  >
                    {icon} {label}
                  </button>
                ))}
                <button
                  onClick={() => setEditing(true)}
                  className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
                >
                  <Pencil className="h-3 w-3" /> Edit
                </button>
                <button
                  onClick={handleDelete}
                  disabled={deleteGoal.isPending}
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

export const GoalsPanel: React.FC = () => {
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const { data: goals, isLoading } = useGoals(statusFilter ? { status: statusFilter } : undefined);
  const createGoal = useCreateGoal();
  const { addNotification } = useNotifications();

  const handleCreate = async (data: GoalFormData) => {
    try {
      await createGoal.mutateAsync({
        title: data.title,
        description: data.description,
        goal_type: data.goal_type,
        priority: data.priority,
        deadline: data.deadline || undefined,
      });
      addNotification({ type: 'success', message: 'Goal created' });
      setShowCreate(false);
    } catch {
      addNotification({ type: 'error', message: 'Failed to create goal' });
    }
  };

  if (isLoading) return <LoadingSpinner size="lg" className="py-12" message="Loading goals..." />;

  const safeGoals = goals ?? [];

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
          >
            <option value="">All statuses</option>
            <option value="active">Active</option>
            <option value="pending">Pending</option>
            <option value="paused">Paused</option>
            <option value="achieved">Achieved</option>
            <option value="failed">Failed</option>
            <option value="abandoned">Abandoned</option>
          </select>
          <span className="text-sm text-theme-muted">{safeGoals.length} goal{safeGoals.length !== 1 ? 's' : ''}</span>
        </div>
        <button
          onClick={() => setShowCreate(prev => !prev)}
          className="btn-theme btn-theme-primary btn-theme-sm flex items-center gap-1"
        >
          <Plus className="h-3.5 w-3.5" /> Create Goal
        </button>
      </div>

      {/* Create form */}
      {showCreate && (
        <GoalForm
          onSubmit={handleCreate}
          onCancel={() => setShowCreate(false)}
          submitting={createGoal.isPending}
          submitLabel="Create Goal"
        />
      )}

      {/* Goal list */}
      {safeGoals.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <Target className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No goals found. Create one or wait for agents to set goals during duty cycles.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {safeGoals.map((goal) => (
            <GoalCard
              key={goal.id}
              goal={goal}
              isExpanded={expandedId === goal.id}
              onToggle={() => setExpandedId(prev => prev === goal.id ? null : goal.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
};
