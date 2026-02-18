import React from 'react';
import { useNavigate } from 'react-router-dom';
import {
  RotateCcw,
  Calendar,
  Wifi,
  WifiOff,
  GitFork,
  ListChecks,
  Repeat,
  TrendingUp,
  Loader2,
} from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { Badge } from '@/shared/components/ui/Badge';
import { LoopStatsCards } from './LoopStatsCards';
import { RalphIterationList } from './RalphIterationList';
import { RalphProgressView } from './RalphProgressView';
import { RalphTaskList } from './RalphTaskList';
import { RalphLoopScheduleStatus } from './RalphLoopScheduleStatus';
import { RalphLiveExecutionPanel } from './RalphLiveExecutionPanel';
import { cn } from '@/shared/utils/cn';
import type {
  RalphLoop,
  RalphLoopStatus,
  RalphIteration,
  PrdTask,
} from '@/shared/services/ai/types/ralph-types';

const statusConfig: Record<RalphLoopStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
}> = {
  pending: { variant: 'outline', label: 'Pending' },
  running: { variant: 'info', label: 'Running' },
  paused: { variant: 'warning', label: 'Paused' },
  completed: { variant: 'success', label: 'Completed' },
  failed: { variant: 'danger', label: 'Failed' },
  cancelled: { variant: 'outline', label: 'Cancelled' },
};

interface RalphLoopDetailPanelProps {
  loop: RalphLoop | null;
  loading: boolean;
  error: string | null;
  wsConnected: boolean;
  liveIterations: RalphIteration[];
  editedTasks: PrdTask[];
  activeTab: string;
  onActiveTabChange: (tab: string) => void;
  onTasksChange: (tasks: PrdTask[]) => void;
  onSavePrd: (tasks?: PrdTask[]) => Promise<void>;
  onShowScheduleConfig: () => void;
  onPauseSchedule: () => void;
  onResumeSchedule: () => void;
  onRegenerateToken: () => void;
  scheduleLoading: boolean;
}

export const RalphLoopDetailPanel: React.FC<RalphLoopDetailPanelProps> = ({
  loop,
  loading,
  error,
  wsConnected,
  liveIterations,
  editedTasks,
  activeTab,
  onActiveTabChange,
  onTasksChange,
  onSavePrd,
  onShowScheduleConfig,
  onPauseSchedule,
  onResumeSchedule,
  onRegenerateToken,
  scheduleLoading,
}) => {
  const navigate = useNavigate();

  // Empty state
  if (!loop && !loading && !error) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <RotateCcw className="w-12 h-12 text-theme-tertiary mx-auto mb-3" />
          <p className="text-sm text-theme-secondary">Select a loop to view details</p>
        </div>
      </div>
    );
  }

  // Loading state
  if (loading && !loop) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
      </div>
    );
  }

  // Error state
  if (error && !loop) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <p className="text-sm text-theme-error">{error}</p>
      </div>
    );
  }

  if (!loop) return null;

  const status = statusConfig[loop.status] || statusConfig.pending;
  const isRunning = loop.status === 'running';
  const progressPercentage = loop.task_count
    ? Math.round((loop.completed_task_count || 0) / loop.task_count * 100)
    : 0;

  return (
    <div className="flex-1 overflow-y-auto p-6">
      <div className="space-y-6">
        {/* Status Badge */}
        <div className="flex items-center gap-3 mb-4">
          <Badge variant={status.variant}>
            {isRunning && <RotateCcw className="w-3 h-3 mr-1 animate-spin" />}
            {status.label}
          </Badge>
          {(isRunning || loop.status === 'paused') && (
            <Badge variant={wsConnected ? 'success' : 'warning'} size="sm">
              {wsConnected ? (
                <>
                  <Wifi className="w-3 h-3 mr-1" />
                  Live
                </>
              ) : (
                <>
                  <WifiOff className="w-3 h-3 mr-1" />
                  Connecting...
                </>
              )}
            </Badge>
          )}
        </div>

        {/* Error */}
        {error && (
          <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error">
            {error}
          </div>
        )}

        <LoopStatsCards
          currentIteration={loop.current_iteration}
          maxIterations={loop.max_iterations}
          completedTaskCount={loop.completed_task_count || 0}
          taskCount={loop.task_count || 0}
          progressPercentage={progressPercentage}
          defaultAgentName={loop.default_agent_name}
        />

        {/* Progress Bar */}
        <div className="h-2 bg-theme-bg-secondary rounded-full overflow-hidden">
          <div
            className={cn(
              'h-full rounded-full transition-all duration-500',
              loop.status === 'completed' ? 'bg-theme-status-success' :
              loop.status === 'failed' ? 'bg-theme-status-error' :
              'bg-theme-status-info'
            )}
            style={{ width: `${progressPercentage}%` }}
          />
        </div>

        {/* Parallel Session Link */}
        {loop.configuration?.parallel_session_id && (
          <div
            className="flex items-center gap-3 p-3 bg-theme-status-info/5 border border-theme-status-info/20 rounded-lg cursor-pointer hover:bg-theme-status-info/10 transition-colors"
            onClick={() => navigate(`/app/ai/parallel-execution`)}
          >
            <GitFork className="w-5 h-5 text-theme-status-info" />
            <div className="flex-1">
              <div className="text-sm font-medium text-theme-text-primary">Parallel Execution Active</div>
              <div className="text-xs text-theme-text-secondary">
                Session {String(loop.configuration.parallel_session_id).substring(0, 8)} - Click to view worktree dashboard
              </div>
            </div>
          </div>
        )}

        {/* Live Execution Panel */}
        {(isRunning || liveIterations.length > 0) && (
          <RalphLiveExecutionPanel
            iterations={liveIterations}
            isRunning={isRunning}
          />
        )}

        {/* Tabs */}
        <Tabs value={activeTab} onValueChange={onActiveTabChange}>
          <TabsList>
            <TabsTrigger value="tasks">
              <span className="flex items-center gap-2"><ListChecks className="w-4 h-4" />Tasks</span>
            </TabsTrigger>
            <TabsTrigger value="iterations">
              <span className="flex items-center gap-2"><Repeat className="w-4 h-4" />Iterations</span>
            </TabsTrigger>
            <TabsTrigger value="progress">
              <span className="flex items-center gap-2"><TrendingUp className="w-4 h-4" />Progress</span>
            </TabsTrigger>
            <TabsTrigger value="schedule">
              <span className="flex items-center gap-2"><Calendar className="w-4 h-4" />Schedule</span>
            </TabsTrigger>
          </TabsList>

          <TabsContent value="tasks" className="mt-4">
            <RalphTaskList
              loopId={loop.id}
              prdTasks={editedTasks}
              onPrdTasksChange={onTasksChange}
              onSavePrd={onSavePrd}
              isRunning={isRunning}
            />
          </TabsContent>

          <TabsContent value="iterations" className="mt-4">
            <RalphIterationList loopId={loop.id} />
          </TabsContent>

          <TabsContent value="progress" className="mt-4">
            <RalphProgressView loopId={loop.id} />
          </TabsContent>

          <TabsContent value="schedule" className="mt-4">
            <RalphLoopScheduleStatus
              loop={loop}
              onPauseSchedule={onPauseSchedule}
              onResumeSchedule={onResumeSchedule}
              onRegenerateToken={onRegenerateToken}
              onConfigureSchedule={onShowScheduleConfig}
              isLoading={scheduleLoading}
            />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
};
