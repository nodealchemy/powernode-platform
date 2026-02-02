import React, { useState, useMemo } from 'react';
import { Search, Eye, EyeOff, Copy, Check, Database, Lock } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Input } from '@/shared/components/ui/Input';

export interface WorkflowVariable {
  name: string;
  value: unknown;
  type: string;
  source: 'input' | 'output' | 'computed' | 'system';
  nodeId?: string;
  nodeName?: string;
  isSecret?: boolean;
  description?: string;
  lastUpdated?: string;
}

export interface VariableInspectorPanelProps {
  variables: WorkflowVariable[];
  executionState?: Record<string, unknown>;
  onVariableClick?: (variable: WorkflowVariable) => void;
  onClose: () => void;
  className?: string;
}

export const VariableInspectorPanel: React.FC<VariableInspectorPanelProps> = ({
  variables,
  onVariableClick,
  onClose,
  className = ''
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [showSecrets, setShowSecrets] = useState(false);
  const [copiedVariable, setCopiedVariable] = useState<string | null>(null);
  const [filterSource, setFilterSource] = useState<string>('all');

  // Filter and search variables
  const filteredVariables = useMemo(() => {
    return variables.filter(variable => {
      // Search filter
      const matchesSearch = searchQuery === '' ||
        variable.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        variable.description?.toLowerCase().includes(searchQuery.toLowerCase());

      // Source filter
      const matchesSource = filterSource === 'all' || variable.source === filterSource;

      return matchesSearch && matchesSource;
    });
  }, [variables, searchQuery, filterSource]);

  // Group variables by source
  const groupedVariables = useMemo(() => {
    const groups: Record<string, WorkflowVariable[]> = {
      input: [],
      output: [],
      computed: [],
      system: []
    };

    filteredVariables.forEach(variable => {
      groups[variable.source].push(variable);
    });

    return groups;
  }, [filteredVariables]);

  const handleCopyValue = async (variable: WorkflowVariable) => {
    try {
      const value = typeof variable.value === 'object'
        ? JSON.stringify(variable.value, null, 2)
        : String(variable.value);

      await navigator.clipboard.writeText(value);
      setCopiedVariable(variable.name);
      setTimeout(() => setCopiedVariable(null), 2000);
    } catch {
      console.error('Failed to copy:', error);
    }
  };

  const formatValue = (value: unknown, isSecret: boolean) => {
    if (isSecret && !showSecrets) {
      return '••••••••';
    }

    if (value === null) return 'null';
    if (value === undefined) return 'undefined';
    if (typeof value === 'object') {
      return JSON.stringify(value, null, 2);
    }
    return String(value);
  };

  const getTypeColor = (type: string) => {
    switch (type.toLowerCase()) {
      case 'string':
        return 'text-theme-success';
      case 'number':
        return 'text-theme-info';
      case 'boolean':
        return 'text-theme-interactive-primary';
      case 'object':
      case 'array':
        return 'text-theme-warning';
      default:
        return 'text-theme-secondary';
    }
  };

  const getSourceBadge = (source: string) => {
    const badges = {
      input: { label: 'Input', color: 'bg-theme-info/10 text-theme-info border-theme-info/20' },
      output: { label: 'Output', color: 'bg-theme-success/10 text-theme-success border-theme-success/20' },
      computed: { label: 'Computed', color: 'bg-theme-interactive-primary/10 text-theme-interactive-primary border-theme-interactive-primary/20' },
      system: { label: 'System', color: 'bg-theme-surface/10 text-theme-muted border-theme-muted/20' }
    };

    const badge = badges[source as keyof typeof badges] || badges.system;

    return (
      <span className={`px-2 py-0.5 rounded-full text-xs font-medium border ${badge.color}`}>
        {badge.label}
      </span>
    );
  };

  return (
    <div className={`fixed inset-y-0 right-0 w-96 bg-theme-surface border-l border-theme shadow-xl z-50 overflow-y-auto ${className}`}>
      {/* Header */}
      <div className="sticky top-0 bg-theme-surface border-b border-theme p-4 z-10">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
            <Database className="h-5 w-5" />
            Variable Inspector
          </h3>
          <button
            onClick={onClose}
            className="text-theme-secondary hover:text-theme-primary transition-colors"
          >
            ✕
          </button>
        </div>

        {/* Search */}
        <div className="relative mb-3">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-secondary" />
          <Input
            type="text"
            placeholder="Search variables..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>

        {/* Filters */}
        <div className="flex items-center gap-2">
          <select
            value={filterSource}
            onChange={(e) => setFilterSource(e.target.value)}
            className="flex-1 px-3 py-2 bg-theme-background border border-theme rounded-lg text-sm text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
          >
            <option value="all">All Sources</option>
            <option value="input">Inputs</option>
            <option value="output">Outputs</option>
            <option value="computed">Computed</option>
            <option value="system">System</option>
          </select>

          <button
            onClick={() => setShowSecrets(!showSecrets)}
            className={`p-2 rounded-lg border transition-colors ${
              showSecrets
                ? 'bg-theme-interactive-primary border-theme-interactive-primary text-white'
                : 'bg-theme-background border-theme text-theme-secondary hover:text-theme-primary'
            }`}
            title={showSecrets ? 'Hide secrets' : 'Show secrets'}
          >
            {showSecrets ? <Eye className="h-4 w-4" /> : <EyeOff className="h-4 w-4" />}
          </button>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-4">
        {/* Summary Stats */}
        <Card className="p-3">
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <p className="text-theme-secondary">Total Variables</p>
              <p className="text-theme-primary font-medium">{variables.length}</p>
            </div>
            <div>
              <p className="text-theme-secondary">Filtered</p>
              <p className="text-theme-primary font-medium">{filteredVariables.length}</p>
            </div>
          </div>
        </Card>

        {/* Variable Groups */}
        {Object.entries(groupedVariables).map(([source, vars]) => (
          vars.length > 0 && (
            <div key={source} className="space-y-2">
              <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wider">
                {source} Variables ({vars.length})
              </h4>

              {vars.map((variable) => (
                <Card
                  key={variable.name}
                  className={`p-3 cursor-pointer transition-colors ${
                    onVariableClick ? 'hover:bg-theme-background' : ''
                  }`}
                  onClick={() => onVariableClick?.(variable)}
                >
                  {/* Variable Header */}
                  <div className="flex items-start justify-between gap-2 mb-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <code className="text-sm font-mono text-theme-primary truncate">
                          {variable.name}
                        </code>
                        {variable.isSecret && (
                          <Lock className="h-3 w-3 text-theme-secondary flex-shrink-0" />
                        )}
                      </div>
                      {variable.description && (
                        <p className="text-xs text-theme-secondary">{variable.description}</p>
                      )}
                    </div>

                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleCopyValue(variable);
                      }}
                      className="p-1 rounded hover:bg-theme-background transition-colors"
                      title="Copy value"
                    >
                      {copiedVariable === variable.name ? (
                        <Check className="h-4 w-4 text-theme-success" />
                      ) : (
                        <Copy className="h-4 w-4 text-theme-secondary" />
                      )}
                    </button>
                  </div>

                  {/* Variable Metadata */}
                  <div className="flex items-center gap-2 mb-2">
                    {getSourceBadge(variable.source)}
                    <span className={`text-xs font-medium ${getTypeColor(variable.type)}`}>
                      {variable.type}
                    </span>
                    {variable.nodeName && (
                      <span className="text-xs text-theme-muted">
                        from {variable.nodeName}
                      </span>
                    )}
                  </div>

                  {/* Variable Value */}
                  <div className="bg-theme-background rounded-lg p-2 mt-2">
                    <pre className="text-xs font-mono text-theme-primary whitespace-pre-wrap break-all max-h-32 overflow-y-auto">
                      {formatValue(variable.value, variable.isSecret || false)}
                    </pre>
                  </div>

                  {/* Last Updated */}
                  {variable.lastUpdated && (
                    <p className="text-xs text-theme-muted mt-2">
                      Updated: {new Date(variable.lastUpdated).toLocaleTimeString()}
                    </p>
                  )}
                </Card>
              ))}
            </div>
          )
        ))}

        {/* Empty State */}
        {filteredVariables.length === 0 && (
          <div className="text-center py-8">
            <Database className="h-12 w-12 text-theme-secondary mx-auto mb-3 opacity-50" />
            <p className="text-sm text-theme-secondary">
              {searchQuery ? 'No variables match your search' : 'No variables to display'}
            </p>
          </div>
        )}
      </div>
    </div>
  );
};
