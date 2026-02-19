import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Search } from 'lucide-react';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import { A2aTaskListItem } from './A2aTaskListItem';
import { a2aTasksApiService } from '@/shared/services/ai';
import { Loading } from '@/shared/components/ui/Loading';
import { cn } from '@/shared/utils/cn';
import type { A2aTask, A2aTaskFilters, A2aTaskStatus } from '@/shared/services/ai/types/a2a-types';

interface A2aTaskListPanelProps {
  selectedTaskId: string | null;
  onSelectTask: (task: A2aTask) => void;
  refreshKey?: number;
}

const statusIconMap: Record<string, string> = {
  pending: 'text-theme-muted',
  active: 'text-theme-info',
  completed: 'text-theme-success',
  failed: 'text-theme-danger',
  cancelled: 'text-theme-warning',
  input_required: 'text-theme-warning',
};

type TabFilter = 'all' | A2aTaskStatus;

const tabs: { key: TabFilter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'pending', label: 'Pending' },
  { key: 'active', label: 'Active' },
  { key: 'completed', label: 'Completed' },
  { key: 'failed', label: 'Failed' },
  { key: 'input_required', label: 'Input Required' },
];

export const A2aTaskListPanel: React.FC<A2aTaskListPanelProps> = ({
  selectedTaskId,
  onSelectTask,
  refreshKey,
}) => {
  const [tasks, setTasks] = useState<A2aTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<TabFilter>('all');
  const [searchQuery, setSearchQuery] = useState('');

  const loadTasks = useCallback(async () => {
    try {
      setLoading(true);
      const filters: A2aTaskFilters = { per_page: 100 };
      if (activeTab !== 'all') filters.status = activeTab;
      const response = await a2aTasksApiService.getTasks(filters);
      setTasks(response.items || []);
    } catch {
      setTasks([]);
    } finally {
      setLoading(false);
    }
  }, [activeTab]);

  useEffect(() => {
    loadTasks();
  }, [loadTasks, refreshKey]);

  const filteredTasks = useMemo(() => {
    if (!searchQuery) return tasks;
    const q = searchQuery.toLowerCase();
    return tasks.filter(
      (task) =>
        task.task_id.toLowerCase().includes(q) ||
        task.from_agent_id?.toLowerCase().includes(q) ||
        task.to_agent_id?.toLowerCase().includes(q)
    );
  }, [tasks, searchQuery]);

  const stats = useMemo(() => {
    const active = tasks.filter((t) => t.status === 'active').length;
    const completed = tasks.filter((t) => t.status === 'completed').length;
    return { total: tasks.length, active, completed };
  }, [tasks]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (filteredTasks.length === 0) return;

      const currentIndex = filteredTasks.findIndex((t) => t.task_id === selectedTaskId);

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const nextIndex = currentIndex < filteredTasks.length - 1 ? currentIndex + 1 : 0;
        onSelectTask(filteredTasks[nextIndex]);
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const prevIndex = currentIndex > 0 ? currentIndex - 1 : filteredTasks.length - 1;
        onSelectTask(filteredTasks[prevIndex]);
      } else if (e.key === 'Enter' && currentIndex >= 0) {
        e.preventDefault();
        onSelectTask(filteredTasks[currentIndex]);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        // Deselect by selecting with null-like - parent handles this
      }
    },
    [filteredTasks, selectedTaskId, onSelectTask]
  );

  const tabPills = (
    <div className="flex flex-wrap gap-1 px-3 py-2 border-b border-theme">
      {tabs.map((tab) => (
        <button
          key={tab.key}
          onClick={() => setActiveTab(tab.key)}
          className={cn(
            'flex-1 px-2 py-1 text-xs font-medium rounded transition-colors',
            activeTab === tab.key
              ? 'bg-theme-interactive-primary/10 text-theme-accent'
              : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );

  const search = (
    <div className="px-3 py-2 border-b border-theme">
      <div className="relative">
        <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-muted" />
        <input
          type="text"
          placeholder="Search tasks..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="w-full pl-7 pr-2 py-1.5 text-xs bg-theme-surface-dark border border-theme rounded text-theme-primary placeholder:text-theme-muted focus:outline-none focus:border-theme-interactive-primary"
        />
      </div>
    </div>
  );

  const footer = (
    <div className="px-3 py-2 border-t border-theme text-xs text-theme-muted flex items-center gap-3">
      <span>{stats.total} total</span>
      <span>{stats.active} active</span>
      <span>{stats.completed} completed</span>
    </div>
  );

  const collapsedContent = (
    <>
      {filteredTasks.slice(0, 10).map((task) => {
        const color = statusIconMap[task.status] || 'text-theme-muted';
        return (
          <button
            key={task.id}
            onClick={() => onSelectTask(task)}
            className={cn(
              'w-8 h-8 rounded flex items-center justify-center transition-colors',
              task.task_id === selectedTaskId
                ? 'bg-theme-interactive-primary/20'
                : 'hover:bg-theme-surface-hover'
            )}
            title={`${task.task_id.substring(0, 8)} - ${task.status}`}
          >
            <div className={cn('w-2.5 h-2.5 rounded-full', color.replace('text-', 'bg-'))} />
          </button>
        );
      })}
    </>
  );

  return (
    <ResizableListPanel
      storageKeyPrefix="a2a-tasks-panel"
      title="A2A Tasks"
      tabPills={tabPills}
      search={search}
      footer={footer}
      collapsedContent={collapsedContent}
      onKeyDown={handleKeyDown}
    >
      {loading ? (
        <div className="flex items-center justify-center py-8">
          <Loading size="sm" message="Loading..." />
        </div>
      ) : filteredTasks.length === 0 ? (
        <div className="px-3 py-8 text-center text-xs text-theme-muted">
          No tasks found
        </div>
      ) : (
        filteredTasks.map((task) => (
          <A2aTaskListItem
            key={task.id}
            task={task}
            isSelected={task.task_id === selectedTaskId}
            onClick={() => onSelectTask(task)}
          />
        ))
      )}
    </ResizableListPanel>
  );
};

export default A2aTaskListPanel;
