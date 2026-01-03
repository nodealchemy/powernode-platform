import React, { useState, useEffect, useMemo } from 'react';
import {
  X,
  GitBranch,
  Zap,
  Plus,
  Trash2,
  ChevronDown,
  ChevronUp,
  AlertCircle,
  Check,
  Play,
  RefreshCw,
  Settings,
  ArrowRight,
  FileCode,
  Filter,
  Code,
  TestTube,
  Loader2,
  Info,
} from 'lucide-react';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import {
  GitWorkflowTriggerDetail,
  CreateGitWorkflowTriggerData,
  GitEventType,
  GitRepository,
  TestGitTriggerResult,
} from '@/features/git-providers/types';
import { useNotifications } from '@/shared/hooks/useNotifications';

// ================================
// TYPES
// ================================

interface WorkflowTriggerConfigProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  triggerId: string;
  gitTrigger?: GitWorkflowTriggerDetail | null;
  repositories: GitRepository[];
}

interface PayloadMapping {
  id: string;
  workflowVar: string;
  eventPath: string;
}

// ================================
// CONSTANTS
// ================================

const GIT_EVENT_TYPES: Array<{
  value: GitEventType;
  label: string;
  description: string;
  category: string;
}> = [
  // Code Events
  { value: 'push', label: 'Push', description: 'Code pushed to repository', category: 'Code' },
  { value: 'create', label: 'Create', description: 'Branch or tag created', category: 'Code' },
  { value: 'delete', label: 'Delete', description: 'Branch or tag deleted', category: 'Code' },
  { value: 'tag', label: 'Tag', description: 'Tag created or deleted', category: 'Code' },
  { value: 'fork', label: 'Fork', description: 'Repository forked', category: 'Code' },
  { value: 'release', label: 'Release', description: 'Release published', category: 'Code' },

  // Pull Request Events
  { value: 'pull_request', label: 'Pull Request', description: 'PR opened, closed, or updated', category: 'Pull Requests' },
  { value: 'pull_request_review', label: 'PR Review', description: 'Review submitted on PR', category: 'Pull Requests' },
  { value: 'pull_request_comment', label: 'PR Comment', description: 'Comment added to PR', category: 'Pull Requests' },
  { value: 'merge_group', label: 'Merge Group', description: 'Merge queue updated', category: 'Pull Requests' },

  // Issue Events
  { value: 'issue', label: 'Issue', description: 'Issue opened, closed, or updated', category: 'Issues' },
  { value: 'issue_comment', label: 'Issue Comment', description: 'Comment on issue', category: 'Issues' },
  { value: 'commit_comment', label: 'Commit Comment', description: 'Comment on commit', category: 'Issues' },

  // CI/CD Events
  { value: 'workflow_run', label: 'Workflow Run', description: 'CI workflow started or completed', category: 'CI/CD' },
  { value: 'check_run', label: 'Check Run', description: 'Check run created or updated', category: 'CI/CD' },
  { value: 'check_suite', label: 'Check Suite', description: 'Check suite completed', category: 'CI/CD' },
  { value: 'status', label: 'Status', description: 'Commit status updated', category: 'CI/CD' },

  // Deployment Events
  { value: 'deployment', label: 'Deployment', description: 'Deployment created', category: 'Deployment' },
  { value: 'deployment_status', label: 'Deployment Status', description: 'Deployment status changed', category: 'Deployment' },
];

const COMMON_BRANCH_PATTERNS = [
  { pattern: '*', label: 'All branches', description: 'Match any branch' },
  { pattern: 'main', label: 'main', description: 'Only main branch' },
  { pattern: 'master', label: 'master', description: 'Only master branch' },
  { pattern: 'develop', label: 'develop', description: 'Only develop branch' },
  { pattern: 'release/*', label: 'release/*', description: 'Release branches' },
  { pattern: 'feature/*', label: 'feature/*', description: 'Feature branches' },
  { pattern: 'hotfix/*', label: 'hotfix/*', description: 'Hotfix branches' },
  { pattern: 'bugfix/*', label: 'bugfix/*', description: 'Bugfix branches' },
];

const SAMPLE_PAYLOADS: Record<string, object> = {
  push: {
    ref: 'refs/heads/main',
    before: 'abc123',
    after: 'def456',
    repository: { full_name: 'owner/repo', default_branch: 'main' },
    pusher: { name: 'username', email: 'user@example.com' },
    commits: [{ id: 'def456', message: 'Add new feature', author: { name: 'User' } }],
    head_commit: { id: 'def456', message: 'Add new feature' },
    sender: { login: 'username', avatar_url: 'https://...' },
  },
  pull_request: {
    action: 'opened',
    number: 42,
    pull_request: {
      title: 'Add new feature',
      body: 'Description of changes',
      state: 'open',
      head: { ref: 'feature/new-feature', sha: 'abc123' },
      base: { ref: 'main', sha: 'def456' },
      user: { login: 'username' },
    },
    repository: { full_name: 'owner/repo' },
    sender: { login: 'username' },
  },
  workflow_run: {
    action: 'completed',
    workflow_run: {
      id: 12345,
      name: 'CI',
      head_branch: 'main',
      head_sha: 'abc123',
      status: 'completed',
      conclusion: 'success',
    },
    repository: { full_name: 'owner/repo' },
    sender: { login: 'github-actions[bot]' },
  },
};

// ================================
// COMPONENT
// ================================

export const WorkflowTriggerConfig: React.FC<WorkflowTriggerConfigProps> = ({
  isOpen,
  onClose,
  onSuccess,
  triggerId,
  gitTrigger,
  repositories,
}) => {
  const { showNotification } = useNotifications();
  const isEditing = !!gitTrigger;

  // Form state
  const [eventType, setEventType] = useState<GitEventType>('push');
  const [branchPattern, setBranchPattern] = useState('*');
  const [pathPattern, setPathPattern] = useState('');
  const [repositoryId, setRepositoryId] = useState<string>('');
  const [isActive, setIsActive] = useState(true);
  const [payloadMappings, setPayloadMappings] = useState<PayloadMapping[]>([]);
  const [eventFilters, setEventFilters] = useState<Record<string, string>>({});

  // UI state
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [showTest, setShowTest] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isTesting, setIsTesting] = useState(false);
  const [testResult, setTestResult] = useState<TestGitTriggerResult | null>(null);
  const [testPayload, setTestPayload] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});

  // Group events by category
  const eventsByCategory = useMemo(() => {
    const grouped: Record<string, typeof GIT_EVENT_TYPES> = {};
    GIT_EVENT_TYPES.forEach(event => {
      if (!grouped[event.category]) {
        grouped[event.category] = [];
      }
      grouped[event.category].push(event);
    });
    return grouped;
  }, []);

  // Initialize form when editing
  useEffect(() => {
    if (gitTrigger) {
      setEventType(gitTrigger.event_type);
      setBranchPattern(gitTrigger.branch_pattern);
      setPathPattern(gitTrigger.path_pattern || '');
      setRepositoryId(gitTrigger.git_repository_id || '');
      setIsActive(gitTrigger.is_active);

      // Convert payload mapping to array format
      const mappings = Object.entries(gitTrigger.payload_mapping || {}).map(
        ([workflowVar, eventPath], index) => ({
          id: `mapping-${index}`,
          workflowVar,
          eventPath: eventPath as string,
        })
      );
      setPayloadMappings(mappings);

      // Convert event filters to string format
      const filters: Record<string, string> = {};
      Object.entries(gitTrigger.event_filters || {}).forEach(([key, value]) => {
        filters[key] = typeof value === 'string' ? value : JSON.stringify(value);
      });
      setEventFilters(filters);

      setShowAdvanced(mappings.length > 0 || Object.keys(filters).length > 0);
    } else {
      // Reset form for new trigger
      setEventType('push');
      setBranchPattern('*');
      setPathPattern('');
      setRepositoryId('');
      setIsActive(true);
      setPayloadMappings([]);
      setEventFilters({});
      setShowAdvanced(false);
    }

    setTestResult(null);
    setTestPayload(JSON.stringify(SAMPLE_PAYLOADS.push, null, 2));
  }, [gitTrigger, isOpen]);

  // Update test payload when event type changes
  useEffect(() => {
    const sample = SAMPLE_PAYLOADS[eventType] || SAMPLE_PAYLOADS.push;
    setTestPayload(JSON.stringify(sample, null, 2));
  }, [eventType]);

  // Validation
  const validate = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!eventType) {
      newErrors.eventType = 'Event type is required';
    }

    if (!branchPattern.trim()) {
      newErrors.branchPattern = 'Branch pattern is required';
    }

    // Validate payload mappings
    payloadMappings.forEach((mapping, index) => {
      if (mapping.workflowVar && !mapping.eventPath) {
        newErrors[`mapping-${index}-path`] = 'Event path is required';
      }
      if (mapping.eventPath && !mapping.workflowVar) {
        newErrors[`mapping-${index}-var`] = 'Variable name is required';
      }
    });

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handlers
  const handleAddMapping = () => {
    setPayloadMappings([
      ...payloadMappings,
      { id: `mapping-${Date.now()}`, workflowVar: '', eventPath: '' },
    ]);
  };

  const handleRemoveMapping = (id: string) => {
    setPayloadMappings(payloadMappings.filter(m => m.id !== id));
  };

  const handleUpdateMapping = (id: string, field: 'workflowVar' | 'eventPath', value: string) => {
    setPayloadMappings(
      payloadMappings.map(m => (m.id === id ? { ...m, [field]: value } : m))
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate()) return;

    setIsSubmitting(true);
    try {
      // Build payload mapping object
      const mappingObj: Record<string, string> = {};
      payloadMappings.forEach(m => {
        if (m.workflowVar && m.eventPath) {
          mappingObj[m.workflowVar] = m.eventPath;
        }
      });

      // Build event filters object
      const filtersObj: Record<string, unknown> = {};
      Object.entries(eventFilters).forEach(([key, value]) => {
        if (key && value) {
          try {
            filtersObj[key] = JSON.parse(value);
          } catch {
            filtersObj[key] = value;
          }
        }
      });

      const data: CreateGitWorkflowTriggerData = {
        event_type: eventType,
        branch_pattern: branchPattern.trim(),
        path_pattern: pathPattern.trim() || undefined,
        git_repository_id: repositoryId || undefined,
        payload_mapping: mappingObj,
        event_filters: filtersObj,
        is_active: isActive,
      };

      if (isEditing && gitTrigger) {
        await gitProvidersApi.updateGitTrigger(triggerId, gitTrigger.id, data);
        showNotification('Git trigger updated successfully', 'success');
      } else {
        await gitProvidersApi.createGitTrigger(triggerId, data);
        showNotification('Git trigger created successfully', 'success');
      }

      onSuccess();
      onClose();
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to save git trigger', 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleTest = async () => {
    if (!gitTrigger) return;

    setIsTesting(true);
    setTestResult(null);

    try {
      const payload = JSON.parse(testPayload);
      const result = await gitProvidersApi.testGitTrigger(triggerId, gitTrigger.id, payload);
      setTestResult(result);
    } catch (err) {
      if (err instanceof SyntaxError) {
        showNotification('Invalid JSON in test payload', 'error');
      } else {
        showNotification(err instanceof Error ? err.message : 'Failed to test trigger', 'error');
      }
    } finally {
      setIsTesting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="relative bg-theme-surface border border-theme rounded-lg shadow-xl w-full max-w-3xl max-h-[90vh] overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-interactive-primary/10">
              <Zap className="h-5 w-5 text-theme-interactive-primary" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditing ? 'Edit Git Trigger' : 'Create Git Trigger'}
              </h2>
              <p className="text-sm text-theme-secondary">
                Configure when git events should trigger this workflow
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-theme-surface-hover transition-colors"
          >
            <X className="h-5 w-5 text-theme-secondary" />
          </button>
        </div>

        {/* Content */}
        <form onSubmit={handleSubmit} className="overflow-y-auto max-h-[calc(90vh-140px)]">
          <div className="p-6 space-y-6">
            {/* Event Type Selection */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Event Type
              </label>
              <div className="space-y-3">
                {Object.entries(eventsByCategory).map(([category, events]) => (
                  <div key={category}>
                    <p className="text-xs font-medium text-theme-muted uppercase tracking-wide mb-2">
                      {category}
                    </p>
                    <div className="flex flex-wrap gap-2">
                      {events.map(event => (
                        <button
                          key={event.value}
                          type="button"
                          onClick={() => setEventType(event.value)}
                          className={`
                            px-3 py-1.5 rounded-lg text-sm font-medium transition-all
                            ${eventType === event.value
                              ? 'bg-theme-interactive-primary text-white'
                              : 'bg-theme-surface-alt text-theme-secondary hover:bg-theme-surface-hover'
                            }
                          `}
                          title={event.description}
                        >
                          {event.label}
                        </button>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
              {errors.eventType && (
                <p className="mt-1 text-sm text-theme-danger">{errors.eventType}</p>
              )}
            </div>

            {/* Branch Pattern */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                <GitBranch className="h-4 w-4 inline mr-1" />
                Branch Pattern
              </label>
              <div className="flex flex-wrap gap-2 mb-2">
                {COMMON_BRANCH_PATTERNS.map(preset => (
                  <button
                    key={preset.pattern}
                    type="button"
                    onClick={() => setBranchPattern(preset.pattern)}
                    className={`
                      px-2 py-1 rounded text-xs font-medium transition-all
                      ${branchPattern === preset.pattern
                        ? 'bg-theme-interactive-primary text-white'
                        : 'bg-theme-surface-alt text-theme-secondary hover:bg-theme-surface-hover'
                      }
                    `}
                    title={preset.description}
                  >
                    {preset.label}
                  </button>
                ))}
              </div>
              <input
                type="text"
                value={branchPattern}
                onChange={e => setBranchPattern(e.target.value)}
                placeholder="e.g., main, feature/*, release-*"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder-theme-muted focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              />
              <p className="mt-1 text-xs text-theme-muted">
                Use * as wildcard (e.g., feature/* matches feature/login, feature/signup)
              </p>
              {errors.branchPattern && (
                <p className="mt-1 text-sm text-theme-danger">{errors.branchPattern}</p>
              )}
            </div>

            {/* Repository Filter (Optional) */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Repository (Optional)
              </label>
              <select
                value={repositoryId}
                onChange={e => setRepositoryId(e.target.value)}
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              >
                <option value="">All repositories</option>
                {repositories.map(repo => (
                  <option key={repo.id} value={repo.id}>
                    {repo.full_name}
                  </option>
                ))}
              </select>
              <p className="mt-1 text-xs text-theme-muted">
                Leave empty to match events from any connected repository
              </p>
            </div>

            {/* Active Toggle */}
            <div className="flex items-center justify-between p-4 rounded-lg bg-theme-surface-alt">
              <div>
                <p className="font-medium text-theme-primary">Active</p>
                <p className="text-sm text-theme-secondary">
                  Enable or disable this trigger
                </p>
              </div>
              <button
                type="button"
                onClick={() => setIsActive(!isActive)}
                className={`
                  relative w-12 h-6 rounded-full transition-colors
                  ${isActive ? 'bg-theme-success' : 'bg-theme-muted'}
                `}
              >
                <div
                  className={`
                    absolute top-1 w-4 h-4 rounded-full bg-white transition-transform
                    ${isActive ? 'left-7' : 'left-1'}
                  `}
                />
              </button>
            </div>

            {/* Advanced Settings Toggle */}
            <button
              type="button"
              onClick={() => setShowAdvanced(!showAdvanced)}
              className="flex items-center gap-2 text-sm font-medium text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
            >
              <Settings className="h-4 w-4" />
              Advanced Settings
              {showAdvanced ? (
                <ChevronUp className="h-4 w-4" />
              ) : (
                <ChevronDown className="h-4 w-4" />
              )}
            </button>

            {showAdvanced && (
              <div className="space-y-6 pl-4 border-l-2 border-theme">
                {/* Path Pattern */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    <FileCode className="h-4 w-4 inline mr-1" />
                    Path Pattern (Optional)
                  </label>
                  <input
                    type="text"
                    value={pathPattern}
                    onChange={e => setPathPattern(e.target.value)}
                    placeholder="e.g., src/**, *.js, docs/*"
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder-theme-muted focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                  />
                  <p className="mt-1 text-xs text-theme-muted">
                    Only trigger when changes affect files matching this pattern
                  </p>
                </div>

                {/* Payload Variable Mapping */}
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <label className="block text-sm font-medium text-theme-primary">
                      <Code className="h-4 w-4 inline mr-1" />
                      Payload Variable Mapping
                    </label>
                    <button
                      type="button"
                      onClick={handleAddMapping}
                      className="flex items-center gap-1 text-xs font-medium text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
                    >
                      <Plus className="h-3 w-3" />
                      Add Mapping
                    </button>
                  </div>
                  <p className="text-xs text-theme-muted mb-3">
                    Map git event payload fields to workflow input variables
                  </p>

                  {payloadMappings.length === 0 ? (
                    <div className="p-4 rounded-lg bg-theme-surface-alt text-center text-sm text-theme-muted">
                      <Info className="h-4 w-4 inline mr-1" />
                      No variable mappings configured. Standard git context variables will be available.
                    </div>
                  ) : (
                    <div className="space-y-2">
                      {payloadMappings.map((mapping) => (
                        <div key={mapping.id} className="flex items-center gap-2">
                          <input
                            type="text"
                            value={mapping.workflowVar}
                            onChange={e => handleUpdateMapping(mapping.id, 'workflowVar', e.target.value)}
                            placeholder="workflow_variable"
                            className="flex-1 px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder-theme-muted text-sm focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                          />
                          <ArrowRight className="h-4 w-4 text-theme-muted flex-shrink-0" />
                          <input
                            type="text"
                            value={mapping.eventPath}
                            onChange={e => handleUpdateMapping(mapping.id, 'eventPath', e.target.value)}
                            placeholder="payload.path.to.value"
                            className="flex-1 px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder-theme-muted text-sm font-mono focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                          />
                          <button
                            type="button"
                            onClick={() => handleRemoveMapping(mapping.id)}
                            className="p-2 rounded-lg hover:bg-theme-danger/10 text-theme-danger"
                          >
                            <Trash2 className="h-4 w-4" />
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* Event Filters */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    <Filter className="h-4 w-4 inline mr-1" />
                    Event Filters (Optional)
                  </label>
                  <p className="text-xs text-theme-muted mb-3">
                    Add conditions to filter which events trigger the workflow (e.g., action: opened)
                  </p>
                  <div className="space-y-2">
                    {Object.entries(eventFilters).map(([key]) => (
                      <div key={key} className="flex items-center gap-2">
                        <input
                          type="text"
                          value={key}
                          onChange={e => {
                            const newFilters = { ...eventFilters };
                            const value = newFilters[key];
                            delete newFilters[key];
                            newFilters[e.target.value] = value;
                            setEventFilters(newFilters);
                          }}
                          placeholder="Field path"
                          className="flex-1 px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder-theme-muted text-sm font-mono focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        />
                        <span className="text-theme-muted">=</span>
                        <input
                          type="text"
                          value={eventFilters[key]}
                          onChange={e => setEventFilters({ ...eventFilters, [key]: e.target.value })}
                          placeholder="Expected value"
                          className="flex-1 px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder-theme-muted text-sm focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        />
                        <button
                          type="button"
                          onClick={() => {
                            const newFilters = { ...eventFilters };
                            delete newFilters[key];
                            setEventFilters(newFilters);
                          }}
                          className="p-2 rounded-lg hover:bg-theme-danger/10 text-theme-danger"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </div>
                    ))}
                    <button
                      type="button"
                      onClick={() => setEventFilters({ ...eventFilters, '': '' })}
                      className="flex items-center gap-1 text-xs font-medium text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
                    >
                      <Plus className="h-3 w-3" />
                      Add Filter
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* Test Section (only for existing triggers) */}
            {isEditing && (
              <>
                <button
                  type="button"
                  onClick={() => setShowTest(!showTest)}
                  className="flex items-center gap-2 text-sm font-medium text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
                >
                  <TestTube className="h-4 w-4" />
                  Test Trigger
                  {showTest ? (
                    <ChevronUp className="h-4 w-4" />
                  ) : (
                    <ChevronDown className="h-4 w-4" />
                  )}
                </button>

                {showTest && (
                  <div className="space-y-4 p-4 rounded-lg bg-theme-surface-alt">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Sample Payload (JSON)
                      </label>
                      <textarea
                        value={testPayload}
                        onChange={e => setTestPayload(e.target.value)}
                        rows={8}
                        className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary font-mono text-sm focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                      />
                    </div>

                    <button
                      type="button"
                      onClick={handleTest}
                      disabled={isTesting}
                      className="flex items-center gap-2 px-4 py-2 rounded-lg bg-theme-info text-white font-medium hover:bg-theme-info/90 disabled:opacity-50"
                    >
                      {isTesting ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        <Play className="h-4 w-4" />
                      )}
                      Test Match
                    </button>

                    {testResult && (
                      <div className={`p-4 rounded-lg ${testResult.matched ? 'bg-theme-success/10 border border-theme-success' : 'bg-theme-warning/10 border border-theme-warning'}`}>
                        <div className="flex items-center gap-2 mb-3">
                          {testResult.matched ? (
                            <Check className="h-5 w-5 text-theme-success" />
                          ) : (
                            <AlertCircle className="h-5 w-5 text-theme-warning" />
                          )}
                          <span className={`font-medium ${testResult.matched ? 'text-theme-success' : 'text-theme-warning'}`}>
                            {testResult.matched ? 'Trigger would fire!' : 'No match'}
                          </span>
                        </div>

                        <div className="space-y-2 text-sm">
                          <p className={testResult.match_details.event_type_match ? 'text-theme-success' : 'text-theme-muted'}>
                            {testResult.match_details.event_type_match ? '✓' : '✗'} Event type match
                          </p>
                          <p className={testResult.match_details.branch_match ? 'text-theme-success' : 'text-theme-muted'}>
                            {testResult.match_details.branch_match ? '✓' : '✗'} Branch pattern match
                          </p>
                          <p className={testResult.match_details.path_match ? 'text-theme-success' : 'text-theme-muted'}>
                            {testResult.match_details.path_match ? '✓' : '✗'} Path pattern match
                          </p>
                          <p className={testResult.match_details.filters_match ? 'text-theme-success' : 'text-theme-muted'}>
                            {testResult.match_details.filters_match ? '✓' : '✗'} Event filters match
                          </p>
                        </div>

                        {testResult.matched && Object.keys(testResult.extracted_variables).length > 0 && (
                          <div className="mt-4">
                            <p className="font-medium text-theme-primary mb-2">Extracted Variables:</p>
                            <pre className="p-2 rounded bg-theme-background text-xs font-mono overflow-x-auto">
                              {JSON.stringify(testResult.extracted_variables, null, 2)}
                            </pre>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </>
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between px-6 py-4 border-t border-theme bg-theme-background">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-lg border border-theme text-theme-secondary hover:bg-theme-surface-hover transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="flex items-center gap-2 px-6 py-2 rounded-lg bg-theme-interactive-primary text-white font-medium hover:bg-theme-interactive-primary-hover disabled:opacity-50 transition-colors"
            >
              {isSubmitting ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : isEditing ? (
                <RefreshCw className="h-4 w-4" />
              ) : (
                <Plus className="h-4 w-4" />
              )}
              {isEditing ? 'Update Trigger' : 'Create Trigger'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
