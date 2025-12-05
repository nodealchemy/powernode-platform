import React, { useState, useMemo } from 'react';
import {
  Download,
  CheckCircle2,
  XCircle,
  ExternalLink,
  ChevronDown,
  ChevronUp,
  Filter,
  Search
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { BatchWorkflowStatus } from './BatchProgressPanel';

interface BatchResultsTableProps {
  batchId: string;
  workflows: BatchWorkflowStatus[];
  onViewRun?: (workflowId: string, runId: string) => void;
}

type SortField = 'name' | 'status' | 'duration' | 'completed_at';
type SortDirection = 'asc' | 'desc';

export const BatchResultsTable: React.FC<BatchResultsTableProps> = ({
  batchId,
  workflows,
  onViewRun
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'completed' | 'failed' | 'cancelled'>('all');
  const [sortField, setSortField] = useState<SortField>('name');
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');

  const { addNotification } = useNotifications();

  const toggleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const getSortIcon = (field: SortField) => {
    if (sortField !== field) return null;
    return sortDirection === 'asc'
      ? <ChevronUp className="h-4 w-4" />
      : <ChevronDown className="h-4 w-4" />;
  };

  const filteredAndSortedWorkflows = useMemo(() => {
    let filtered = workflows;

    // Apply search filter
    if (searchTerm) {
      filtered = filtered.filter(w =>
        w.workflow_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        w.workflow_id.toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    // Apply status filter
    if (statusFilter !== 'all') {
      filtered = filtered.filter(w => w.status === statusFilter);
    }

    // Apply sorting
    const sorted = [...filtered].sort((a, b) => {
      let aValue: string | number;
      let bValue: string | number;

      switch (sortField) {
        case 'name':
          aValue = a.workflow_name.toLowerCase();
          bValue = b.workflow_name.toLowerCase();
          break;
        case 'status':
          aValue = a.status;
          bValue = b.status;
          break;
        case 'duration':
          aValue = a.duration_ms || 0;
          bValue = b.duration_ms || 0;
          break;
        case 'completed_at':
          aValue = a.completed_at ? new Date(a.completed_at).getTime() : 0;
          bValue = b.completed_at ? new Date(b.completed_at).getTime() : 0;
          break;
        default:
          return 0;
      }

      if (aValue < bValue) return sortDirection === 'asc' ? -1 : 1;
      if (aValue > bValue) return sortDirection === 'asc' ? 1 : -1;
      return 0;
    });

    return sorted;
  }, [workflows, searchTerm, statusFilter, sortField, sortDirection]);

  const stats = useMemo(() => {
    const completed = workflows.filter(w => w.status === 'completed').length;
    const failed = workflows.filter(w => w.status === 'failed').length;
    const cancelled = workflows.filter(w => w.status === 'cancelled').length;
    const avgDuration = workflows
      .filter(w => w.duration_ms)
      .reduce((sum, w) => sum + (w.duration_ms || 0), 0) / workflows.length;

    return {
      total: workflows.length,
      completed,
      failed,
      cancelled,
      avgDuration: Math.round(avgDuration)
    };
  }, [workflows]);

  const exportToCSV = () => {
    try {
      const headers = ['Workflow Name', 'Workflow ID', 'Status', 'Run ID', 'Duration (ms)', 'Started At', 'Completed At', 'Error Message'];
      const rows = workflows.map(w => [
        w.workflow_name,
        w.workflow_id,
        w.status,
        w.run_id || '',
        w.duration_ms?.toString() || '',
        w.started_at || '',
        w.completed_at || '',
        w.error_message || ''
      ]);

      const csvContent = [
        headers.join(','),
        ...rows.map(row => row.map(cell => `"${cell.replace(/"/g, '""')}"`).join(','))
      ].join('\n');

      const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
      const link = document.createElement('a');
      const url = URL.createObjectURL(blob);
      link.setAttribute('href', url);
      link.setAttribute('download', `batch-${batchId}-results-${new Date().toISOString()}.csv`);
      link.style.visibility = 'hidden';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      addNotification({
        type: 'success',
        title: 'Export Complete',
        message: 'Batch results exported to CSV successfully.'
      });
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('CSV export error:', error);
      }
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export batch results. Please try again.'
      });
    }
  };

  const exportToJSON = () => {
    try {
      const jsonData = {
        batch_id: batchId,
        exported_at: new Date().toISOString(),
        statistics: stats,
        workflows: workflows
      };

      const blob = new Blob([JSON.stringify(jsonData, null, 2)], { type: 'application/json' });
      const link = document.createElement('a');
      const url = URL.createObjectURL(blob);
      link.setAttribute('href', url);
      link.setAttribute('download', `batch-${batchId}-results-${new Date().toISOString()}.json`);
      link.style.visibility = 'hidden';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      addNotification({
        type: 'success',
        title: 'Export Complete',
        message: 'Batch results exported to JSON successfully.'
      });
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('JSON export error:', error);
      }
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export batch results. Please try again.'
      });
    }
  };

  const formatDuration = (durationMs?: number) => {
    if (!durationMs) return '-';
    const seconds = Math.floor(durationMs / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return minutes > 0 ? `${minutes}m ${remainingSeconds}s` : `${seconds}s`;
  };

  const getStatusBadge = (status: BatchWorkflowStatus['status']) => {
    switch (status) {
      case 'completed':
        return <Badge variant="success" size="sm">Completed</Badge>;
      case 'failed':
        return <Badge variant="danger" size="sm">Failed</Badge>;
      case 'cancelled':
        return <Badge variant="warning" size="sm">Cancelled</Badge>;
      case 'running':
        return <Badge variant="info" size="sm">Running</Badge>;
      case 'pending':
      default:
        return <Badge variant="outline" size="sm">Pending</Badge>;
    }
  };

  return (
    <Card className="p-6">
      <div className="space-y-4">
        {/* Header with Statistics */}
        <div className="flex items-center justify-between pb-4 border-b border-theme">
          <div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">
              Batch Results
            </h3>
            <div className="flex items-center gap-6 text-sm text-theme-secondary">
              <span>
                Total: <span className="font-medium text-theme-primary">{stats.total}</span>
              </span>
              <span className="flex items-center gap-1">
                <CheckCircle2 className="h-4 w-4 text-theme-success" />
                <span className="font-medium text-theme-primary">{stats.completed}</span>
              </span>
              <span className="flex items-center gap-1">
                <XCircle className="h-4 w-4 text-theme-error" />
                <span className="font-medium text-theme-primary">{stats.failed}</span>
              </span>
              <span>
                Avg Duration: <span className="font-medium text-theme-primary">{formatDuration(stats.avgDuration)}</span>
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={exportToCSV}
              className="flex items-center gap-1"
            >
              <Download className="h-4 w-4" />
              Export CSV
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={exportToJSON}
              className="flex items-center gap-1"
            >
              <Download className="h-4 w-4" />
              Export JSON
            </Button>
          </div>
        </div>

        {/* Filters */}
        <div className="flex items-center gap-4">
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
              <Input
                type="text"
                placeholder="Search workflows..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="pl-10"
              />
            </div>
          </div>
          <div className="w-48">
            <Select
              value={statusFilter}
              onChange={(value) => setStatusFilter(value as any)}
            >
              <option value="all">All Statuses</option>
              <option value="completed">Completed</option>
              <option value="failed">Failed</option>
              <option value="cancelled">Cancelled</option>
            </Select>
          </div>
        </div>

        {/* Results Table */}
        <div className="border border-theme rounded-lg overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th
                    className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider cursor-pointer hover:bg-theme-surface-hover"
                    onClick={() => toggleSort('name')}
                  >
                    <div className="flex items-center gap-1">
                      Workflow
                      {getSortIcon('name')}
                    </div>
                  </th>
                  <th
                    className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider cursor-pointer hover:bg-theme-surface-hover"
                    onClick={() => toggleSort('status')}
                  >
                    <div className="flex items-center gap-1">
                      Status
                      {getSortIcon('status')}
                    </div>
                  </th>
                  <th
                    className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider cursor-pointer hover:bg-theme-surface-hover"
                    onClick={() => toggleSort('duration')}
                  >
                    <div className="flex items-center gap-1">
                      Duration
                      {getSortIcon('duration')}
                    </div>
                  </th>
                  <th
                    className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider cursor-pointer hover:bg-theme-surface-hover"
                    onClick={() => toggleSort('completed_at')}
                  >
                    <div className="flex items-center gap-1">
                      Completed At
                      {getSortIcon('completed_at')}
                    </div>
                  </th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {filteredAndSortedWorkflows.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="px-4 py-8 text-center text-theme-tertiary">
                      {workflows.length === 0
                        ? 'No workflow results yet'
                        : 'No workflows match your search criteria'}
                    </td>
                  </tr>
                ) : (
                  filteredAndSortedWorkflows.map((workflow) => (
                    <tr
                      key={workflow.workflow_id}
                      className="hover:bg-theme-surface transition-colors"
                    >
                      <td className="px-4 py-4">
                        <div>
                          <p className="font-medium text-theme-primary">
                            {workflow.workflow_name}
                          </p>
                          <p className="text-xs text-theme-tertiary mt-1">
                            ID: {workflow.workflow_id.slice(0, 8)}...
                          </p>
                          {workflow.error_message && (
                            <p className="text-xs text-theme-error mt-1 truncate">
                              {workflow.error_message}
                            </p>
                          )}
                        </div>
                      </td>
                      <td className="px-4 py-4">
                        {getStatusBadge(workflow.status)}
                      </td>
                      <td className="px-4 py-4 text-theme-secondary">
                        {formatDuration(workflow.duration_ms)}
                      </td>
                      <td className="px-4 py-4 text-theme-secondary">
                        {workflow.completed_at ? (
                          <div>
                            <p>{new Date(workflow.completed_at).toLocaleDateString()}</p>
                            <p className="text-xs text-theme-tertiary">
                              {new Date(workflow.completed_at).toLocaleTimeString()}
                            </p>
                          </div>
                        ) : (
                          '-'
                        )}
                      </td>
                      <td className="px-4 py-4 text-right">
                        {workflow.run_id && onViewRun && (
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => onViewRun(workflow.workflow_id, workflow.run_id!)}
                            className="flex items-center gap-1"
                          >
                            <ExternalLink className="h-4 w-4" />
                            View Run
                          </Button>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Results Summary */}
        {filteredAndSortedWorkflows.length > 0 && (
          <div className="flex items-center justify-between text-sm text-theme-secondary pt-2">
            <span>
              Showing {filteredAndSortedWorkflows.length} of {workflows.length} workflows
            </span>
            {(searchTerm || statusFilter !== 'all') && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => {
                  setSearchTerm('');
                  setStatusFilter('all');
                }}
                className="flex items-center gap-1"
              >
                <Filter className="h-4 w-4" />
                Clear Filters
              </Button>
            )}
          </div>
        )}
      </div>
    </Card>
  );
};
