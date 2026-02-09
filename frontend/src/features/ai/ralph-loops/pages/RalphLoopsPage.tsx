import React, { useState, useCallback, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Settings,
  RotateCcw,
  Calendar,
  Wifi,
  WifiOff,
  GitFork,
  ListChecks,
  Repeat,
  TrendingUp,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Loading } from '@/shared/components/ui/Loading';
import { Modal } from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { useNotification } from '@/shared/hooks/useNotification';
import { RalphLoopList } from '../components/RalphLoopList';
import { RalphIterationList } from '../components/RalphIterationList';
import { RalphProgressView } from '../components/RalphProgressView';
import { RalphTaskList } from '../components/RalphTaskList';
import { CreateRalphLoopDialog } from '../components/CreateRalphLoopDialog';
import { RalphLoopScheduleStatus } from '../components/RalphLoopScheduleStatus';
import { RalphLoopScheduleConfig } from '../components/RalphLoopScheduleConfig';
import { RalphLiveExecutionPanel } from '../components/RalphLiveExecutionPanel';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import { cn } from '@/shared/utils/cn';
import { useRalphLoopExecutionWebSocket, RalphLoopExecutionUpdate } from '../hooks/useRalphLoopExecutionWebSocket';
import type {
  RalphLoop,
  RalphLoopSummary,
  RalphLoopStatus,
  RalphIteration,
  PrdTask,
  RalphSchedulingMode,
  RalphScheduleConfig,
} from '@/shared/services/ai/types/ralph-types';

type RalphLoopsPageProps = Record<string, never>;

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

interface RalphLoopsContentProps {
  refreshKey?: number;
}

export const RalphLoopsContent: React.FC<RalphLoopsContentProps> = ({ refreshKey: externalRefreshKey }) => {
  const navigate = useNavigate();
  const [selectedLoop, setSelectedLoop] = useState<RalphLoop | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState('tasks');
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [showScheduleConfigModal, setShowScheduleConfigModal] = useState(false);
  const [showSettingsModal, setShowSettingsModal] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    if (externalRefreshKey && externalRefreshKey > 0) {
      setRefreshKey(k => k + 1);
    }
  }, [externalRefreshKey]);

  const [editedTasks, setEditedTasks] = useState<PrdTask[]>([]);
  const [scheduleLoading, setScheduleLoading] = useState(false);
  const [settingsForm, setSettingsForm] = useState({
    name: '',
    description: '',
    max_iterations: 50,
    repository_url: '',
    default_agent_id: '',
  });
  const [settingsLoading, setSettingsLoading] = useState(false);
  const [settingsAgents] = useState<{ id: string; name: string }[]>([]);
  const [liveIterations, setLiveIterations] = useState<RalphIteration[]>([]);
  const { showNotification } = useNotification();

  const loadLoop = async (loopId: string) => {
    try {
      setLoading(true);
      setError(null);
      const response = await ralphLoopsApi.getLoop(loopId);
      setSelectedLoop(response.ralph_loop);
      setEditedTasks(response.ralph_loop.prd_json?.tasks || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load loop');
    } finally {
      setLoading(false);
    }
  };

  // WebSocket handler for real-time updates
  const handleWebSocketUpdate = useCallback((update: RalphLoopExecutionUpdate) => {
    if (!selectedLoop || update.loop_id !== selectedLoop.id) return;

    // For started event, reload to get full running state
    if (update.type === 'loop_started') {
      loadLoop(selectedLoop.id);
    }
    // For progress updates, update state directly without full reload
    else if (update.type === 'loop_progress' || update.type === 'task_status_changed') {
      setSelectedLoop(prev => {
        if (!prev) return prev;
        return {
          ...prev,
          status: (update.status as RalphLoopStatus) || prev.status,
          current_iteration: update.current_iteration ?? prev.current_iteration,
          completed_task_count: update.completed_task_count ?? prev.completed_task_count,
          task_count: update.task_count ?? prev.task_count,
        };
      });
    }
    // For terminal events, do a full reload to get final state
    else if (['loop_completed', 'loop_failed', 'loop_cancelled'].includes(update.type)) {
      loadLoop(selectedLoop.id);
    }
    // For iteration completed, reload and update live panel
    else if (update.type === 'iteration_completed') {
      loadLoop(selectedLoop.id);
      // Fetch latest iteration for live panel
      const iterationNumber = update.data?.iteration_number;
      if (iterationNumber) {
        ralphLoopsApi.getIteration(selectedLoop.id, String(iterationNumber))
          .then(res => {
            setLiveIterations(prev => [...prev, res.iteration]);
          })
          .catch(() => {});
      }
    }
    // Run All events
    else if (update.type === 'run_all_started') {
      loadLoop(selectedLoop.id);
    }
    else if (update.type === 'run_all_completed') {
      loadLoop(selectedLoop.id);
      showNotification('Run All completed', 'success');
    }
  }, [selectedLoop?.id]);

  // WebSocket for real-time updates — subscribe whenever a loop is selected
  const { isConnected: wsConnected } = useRalphLoopExecutionWebSocket({
    loopId: selectedLoop?.id,
    enabled: !!selectedLoop,
    onUpdate: handleWebSocketUpdate,
  });

  const handleSelectLoop = (loop: RalphLoopSummary) => {
    setLiveIterations([]);
    loadLoop(loop.id);
  };

  const handleCreateLoop = () => {
    setShowCreateDialog(true);
  };

  const handleLoopCreated = (loopId: string) => {
    setRefreshKey(prev => prev + 1);
    loadLoop(loopId);
  };

  const handleSavePrd = async (tasksToSave?: PrdTask[]) => {
    if (!selectedLoop) return;
    const tasks = tasksToSave ?? editedTasks;
    try {
      await ralphLoopsApi.parsePrd(selectedLoop.id, {
        prd_json: { tasks },
        replace_existing: true,
      });
      showNotification(`PRD tasks saved successfully (${tasks.length} tasks)`, 'success');
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save PRD');
    }
  };

  const handleTasksChange = (tasks: PrdTask[]) => {
    setEditedTasks(tasks);
  };

  // Schedule actions
  const handlePauseSchedule = useCallback(async () => {
    if (!selectedLoop) return;
    try {
      setScheduleLoading(true);
      await ralphLoopsApi.pauseSchedule(selectedLoop.id);
      showNotification('Schedule paused successfully', 'success');
      loadLoop(selectedLoop.id);
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to pause schedule', 'error');
    } finally {
      setScheduleLoading(false);
    }
  }, [selectedLoop, showNotification]);

  const handleResumeSchedule = useCallback(async () => {
    if (!selectedLoop) return;
    try {
      setScheduleLoading(true);
      await ralphLoopsApi.resumeSchedule(selectedLoop.id);
      showNotification('Schedule resumed successfully', 'success');
      loadLoop(selectedLoop.id);
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to resume schedule', 'error');
    } finally {
      setScheduleLoading(false);
    }
  }, [selectedLoop, showNotification]);

  const handleRegenerateToken = useCallback(async () => {
    if (!selectedLoop) return;
    try {
      setScheduleLoading(true);
      await ralphLoopsApi.regenerateWebhookToken(selectedLoop.id);
      showNotification('Webhook token regenerated successfully', 'success');
      loadLoop(selectedLoop.id);
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to regenerate token', 'error');
    } finally {
      setScheduleLoading(false);
    }
  }, [selectedLoop, showNotification]);

  const handleSaveScheduleConfig = useCallback(async (
    mode: RalphSchedulingMode,
    config: RalphScheduleConfig
  ) => {
    if (!selectedLoop) return;
    try {
      setScheduleLoading(true);
      await ralphLoopsApi.updateLoop(selectedLoop.id, {
        scheduling_mode: mode,
        schedule_config: config,
      });
      showNotification('Schedule configuration saved successfully', 'success');
      setShowScheduleConfigModal(false);
      loadLoop(selectedLoop.id);
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to save schedule configuration', 'error');
    } finally {
      setScheduleLoading(false);
    }
  }, [selectedLoop, showNotification]);

  const handleSaveSettings = useCallback(async () => {
    if (!selectedLoop) return;
    try {
      setSettingsLoading(true);
      await ralphLoopsApi.updateLoop(selectedLoop.id, {
        name: settingsForm.name,
        description: settingsForm.description || undefined,
        max_iterations: settingsForm.max_iterations,
        repository_url: settingsForm.repository_url || undefined,
        default_agent_id: settingsForm.default_agent_id || undefined,
      });
      showNotification('Settings saved successfully', 'success');
      setShowSettingsModal(false);
      loadLoop(selectedLoop.id);
    } catch (err) {
      showNotification(err instanceof Error ? err.message : 'Failed to save settings', 'error');
    } finally {
      setSettingsLoading(false);
    }
  }, [selectedLoop, settingsForm, showNotification]);

  if (loading && !selectedLoop) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  if (selectedLoop) {
    const status = statusConfig[selectedLoop.status] || statusConfig.pending;
    const isRunning = selectedLoop.status === 'running';
    const progressPercentage = selectedLoop.task_count
      ? Math.round((selectedLoop.completed_task_count || 0) / selectedLoop.task_count * 100)
      : 0;

    return (
      <div className="space-y-6">
        {/* Status Badge */}
        <div className="flex items-center gap-3 mb-4">
          <Badge variant={status.variant}>
            {isRunning && <RotateCcw className="w-3 h-3 mr-1 animate-spin" />}
            {status.label}
          </Badge>
          {(isRunning || selectedLoop.status === 'paused') && (
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

        {/* Stats Cards */}
        <div className="grid grid-cols-4 gap-4">
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold text-theme-text-primary">
                {selectedLoop.current_iteration}/{selectedLoop.max_iterations}
              </div>
              <div className="text-sm text-theme-text-secondary">Iterations</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold text-theme-text-primary">
                {selectedLoop.completed_task_count || 0}/{selectedLoop.task_count || 0}
              </div>
              <div className="text-sm text-theme-text-secondary">Tasks Completed</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold text-theme-text-primary">
                {progressPercentage}%
              </div>
              <div className="text-sm text-theme-text-secondary">Progress</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4">
              <div className="text-2xl font-bold text-theme-text-primary truncate">
                {selectedLoop.default_agent_name || 'No Agent'}
              </div>
              <div className="text-sm text-theme-text-secondary">Default Agent</div>
            </CardContent>
          </Card>
        </div>

        {/* Progress Bar */}
        <div className="h-2 bg-theme-bg-secondary rounded-full overflow-hidden">
          <div
            className={cn(
              'h-full rounded-full transition-all duration-500',
              selectedLoop.status === 'completed' ? 'bg-theme-status-success' :
              selectedLoop.status === 'failed' ? 'bg-theme-status-error' :
              'bg-theme-status-info'
            )}
            style={{ width: `${progressPercentage}%` }}
          />
        </div>

        {/* Parallel Session Link */}
        {selectedLoop.configuration?.parallel_session_id && (
          <div
            className="flex items-center gap-3 p-3 bg-theme-status-info/5 border border-theme-status-info/20 rounded-lg cursor-pointer hover:bg-theme-status-info/10 transition-colors"
            onClick={() => navigate(`/app/ai/parallel-execution`)}
          >
            <GitFork className="w-5 h-5 text-theme-status-info" />
            <div className="flex-1">
              <div className="text-sm font-medium text-theme-text-primary">Parallel Execution Active</div>
              <div className="text-xs text-theme-text-secondary">
                Session {String(selectedLoop.configuration.parallel_session_id).substring(0, 8)} - Click to view worktree dashboard
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
        <Tabs value={activeTab} onValueChange={setActiveTab}>
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
              loopId={selectedLoop.id}
              prdTasks={editedTasks}
              onPrdTasksChange={handleTasksChange}
              onSavePrd={handleSavePrd}
              isRunning={isRunning}
            />
          </TabsContent>

          <TabsContent value="iterations" className="mt-4">
            <RalphIterationList loopId={selectedLoop.id} />
          </TabsContent>

          <TabsContent value="progress" className="mt-4">
            <RalphProgressView loopId={selectedLoop.id} />
          </TabsContent>

          <TabsContent value="schedule" className="mt-4">
            <RalphLoopScheduleStatus
              loop={selectedLoop}
              onPauseSchedule={handlePauseSchedule}
              onResumeSchedule={handleResumeSchedule}
              onRegenerateToken={handleRegenerateToken}
              onConfigureSchedule={() => setShowScheduleConfigModal(true)}
              isLoading={scheduleLoading}
            />
          </TabsContent>
        </Tabs>

        {/* Schedule Configuration Modal */}
        <Modal
          isOpen={showScheduleConfigModal}
          onClose={() => setShowScheduleConfigModal(false)}
          title="Configure Schedule"
          icon={<Calendar className="w-5 h-5 text-theme-brand-primary" />}
          size="lg"
        >
          <RalphLoopScheduleConfig
            schedulingMode={selectedLoop.scheduling_mode}
            scheduleConfig={selectedLoop.schedule_config}
            onChange={handleSaveScheduleConfig}
            onCancel={() => setShowScheduleConfigModal(false)}
          />
        </Modal>

        {/* Settings Modal */}
        <Modal
          isOpen={showSettingsModal}
          onClose={() => setShowSettingsModal(false)}
          title="Loop Settings"
          icon={<Settings className="w-5 h-5 text-theme-brand-primary" />}
          size="md"
          footer={
            <>
              <Button
                variant="outline"
                onClick={() => setShowSettingsModal(false)}
                disabled={settingsLoading}
              >
                Cancel
              </Button>
              <Button
                variant="primary"
                onClick={handleSaveSettings}
                disabled={settingsLoading || !settingsForm.name.trim()}
              >
                {settingsLoading ? 'Saving...' : 'Save Settings'}
              </Button>
            </>
          }
        >
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Name *
              </label>
              <Input
                value={settingsForm.name}
                onChange={(e) => setSettingsForm(prev => ({ ...prev, name: e.target.value }))}
                placeholder="Loop name"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Description
              </label>
              <Input
                value={settingsForm.description}
                onChange={(e) => setSettingsForm(prev => ({ ...prev, description: e.target.value }))}
                placeholder="Optional description..."
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Max Iterations
              </label>
              <Input
                type="number"
                value={settingsForm.max_iterations}
                onChange={(e) => setSettingsForm(prev => ({ ...prev, max_iterations: parseInt(e.target.value) || 50 }))}
                min={1}
                max={1000}
              />
              <p className="text-xs text-theme-text-secondary mt-1">
                Maximum number of AI iterations before stopping
              </p>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Repository URL
              </label>
              <Input
                value={settingsForm.repository_url}
                onChange={(e) => setSettingsForm(prev => ({ ...prev, repository_url: e.target.value }))}
                placeholder="https://github.com/user/repo"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Default Agent
              </label>
              <Select
                value={settingsForm.default_agent_id}
                onChange={(value) => setSettingsForm(prev => ({ ...prev, default_agent_id: value }))}
              >
                <option value="">No agent selected</option>
                {settingsAgents.map((agent) => (
                  <option key={agent.id} value={agent.id}>
                    {agent.name}
                  </option>
                ))}
              </Select>
              <p className="text-xs text-theme-text-secondary mt-1">
                AI agent that will execute loop tasks
              </p>
            </div>
          </div>
        </Modal>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <RalphLoopList
        key={refreshKey}
        onSelectLoop={handleSelectLoop}
        onCreateLoop={handleCreateLoop}
      />

      <CreateRalphLoopDialog
        isOpen={showCreateDialog}
        onClose={() => setShowCreateDialog(false)}
        onCreated={handleLoopCreated}
      />
    </div>
  );
};

export const RalphLoopsPage: React.FC<RalphLoopsPageProps> = () => {
  return (
    <PageContainer
      title="Ralph Loops"
      description="Autonomous AI-driven iterative development loops"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Ralph Loops' },
      ]}
    >
      <RalphLoopsContent />
    </PageContainer>
  );
};

export default RalphLoopsPage;
