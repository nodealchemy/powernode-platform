import React, { useState, useCallback } from 'react';
import {
  Play,
  Pause,
  Square,
  Settings,
  RotateCcw,
  Zap,
  FastForward,
  Calendar,
  Wifi,
  WifiOff,
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
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
import { agentsApi } from '@/shared/services/ai/AgentsApiService';
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

export const RalphLoopsPage: React.FC<RalphLoopsPageProps> = () => {
  const [selectedLoop, setSelectedLoop] = useState<RalphLoop | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState('tasks');
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [showScheduleConfigModal, setShowScheduleConfigModal] = useState(false);
  const [showSettingsModal, setShowSettingsModal] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
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
  const [settingsAgents, setSettingsAgents] = useState<{ id: string; name: string }[]>([]);
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

  const handleBack = () => {
    setSelectedLoop(null);
    setActiveTab('tasks');
    setEditedTasks([]);
    setLiveIterations([]);
  };

  const handleStart = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.startLoop(selectedLoop.id);
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start loop');
    }
  };

  const handlePause = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.pauseLoop(selectedLoop.id);
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to pause loop');
    }
  };

  const handleResume = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.resumeLoop(selectedLoop.id);
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to resume loop');
    }
  };

  const handleCancel = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.cancelLoop(selectedLoop.id);
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel loop');
    }
  };

  const handleReset = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.resetLoop(selectedLoop.id);
      showNotification('Loop reset successfully', 'success');
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to reset loop');
    }
  };

  const handleRunIteration = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.runIteration(selectedLoop.id);
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to run iteration');
    }
  };

  const handleRunAll = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.runAll(selectedLoop.id);
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start Run All');
    }
  };

  const handleStopRunAll = async () => {
    if (!selectedLoop) return;
    try {
      await ralphLoopsApi.stopRunAll(selectedLoop.id);
      loadLoop(selectedLoop.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to stop Run All');
    }
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

  const handleOpenSettings = useCallback(() => {
    if (!selectedLoop) return;
    setSettingsForm({
      name: selectedLoop.name,
      description: selectedLoop.description || '',
      max_iterations: selectedLoop.max_iterations,
      repository_url: selectedLoop.repository_url || '',
      default_agent_id: selectedLoop.default_agent_id || '',
    });
    agentsApi.getAgents({ per_page: 100 }).then((res) => {
      setSettingsAgents((res.items || []).map((a: { id: string; name: string }) => ({ id: a.id, name: a.name })));
    }).catch(() => {});
    setShowSettingsModal(true);
  }, [selectedLoop]);

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

  // Build breadcrumbs based on current view
  const getBreadcrumbs = () => {
    const base = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];

    if (selectedLoop) {
      return [
        ...base,
        { label: 'Ralph Loops', href: '/app/ai/ralph-loops' },
        { label: selectedLoop.name },
      ];
    }
    return [...base, { label: 'Ralph Loops' }];
  };

  // Build actions based on current view
  const getActions = (): PageAction[] => {
    if (selectedLoop) {
      const actions: PageAction[] = [
        {
          id: 'back',
          label: 'Back to List',
          onClick: handleBack,
          variant: 'secondary',
        },
      ];

      const canStart = selectedLoop.status === 'pending';
      const isRunning = selectedLoop.status === 'running';
      const isPaused = selectedLoop.status === 'paused';
      const canRunIteration = selectedLoop.status === 'running';
      const canReset = ['cancelled', 'completed', 'failed'].includes(selectedLoop.status);
      const runAllActive = !!selectedLoop.configuration?.run_all_active;

      if (canReset) {
        actions.push({
          id: 'reset',
          label: 'Reset',
          onClick: handleReset,
          variant: 'outline',
          icon: RotateCcw,
        });
      }
      if (canStart) {
        actions.push({
          id: 'start',
          label: 'Start Loop',
          onClick: handleStart,
          variant: 'primary',
          icon: Play,
        });
      }
      if (isRunning) {
        actions.push({
          id: 'pause',
          label: 'Pause',
          onClick: handlePause,
          variant: 'outline',
          icon: Pause,
        });
      }
      if (isPaused) {
        actions.push({
          id: 'resume',
          label: 'Resume',
          onClick: handleResume,
          variant: 'primary',
          icon: Play,
        });
        actions.push({
          id: 'cancel',
          label: 'Cancel',
          onClick: handleCancel,
          variant: 'outline',
          icon: Square,
        });
      }
      if (canRunIteration) {
        if (runAllActive) {
          actions.push({
            id: 'stop-run-all',
            label: 'Stop Run All',
            onClick: handleStopRunAll,
            variant: 'outline',
            icon: Square,
          });
        } else {
          actions.push({
            id: 'run-one',
            label: 'Run One',
            onClick: handleRunIteration,
            variant: 'outline',
            icon: Zap,
          });
          actions.push({
            id: 'run-all',
            label: 'Run All',
            onClick: handleRunAll,
            variant: 'primary',
            icon: FastForward,
          });
        }
      }
      actions.push({
        id: 'settings',
        label: 'Settings',
        onClick: handleOpenSettings,
        variant: 'secondary',
        icon: Settings,
      });

      return actions;
    }
    return [];
  };

  // Get page info based on current view
  const getPageInfo = () => {
    if (selectedLoop) {
      const status = statusConfig[selectedLoop.status] || statusConfig.pending;
      return {
        title: selectedLoop.name,
        description: selectedLoop.description || `${status.label} · ${selectedLoop.default_agent_name || 'No Agent'}`,
      };
    }
    return {
      title: 'Ralph Loops',
      description: 'Autonomous AI-driven iterative development loops',
    };
  };

  const pageInfo = getPageInfo();

  if (loading && !selectedLoop) {
    return (
      <PageContainer
        title="Ralph Loops"
        description="Loading..."
        breadcrumbs={getBreadcrumbs()}
      >
        <div className="flex items-center justify-center p-8">
          <Loading size="lg" />
        </div>
      </PageContainer>
    );
  }

  if (selectedLoop) {
    const status = statusConfig[selectedLoop.status] || statusConfig.pending;
    const isRunning = selectedLoop.status === 'running';
    const progressPercentage = selectedLoop.task_count
      ? Math.round((selectedLoop.completed_task_count || 0) / selectedLoop.task_count * 100)
      : 0;

    return (
      <PageContainer
        title={pageInfo.title}
        description={pageInfo.description}
        breadcrumbs={getBreadcrumbs()}
        actions={getActions()}
      >
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
            <TabsTrigger value="tasks">Tasks</TabsTrigger>
            <TabsTrigger value="iterations">Iterations</TabsTrigger>
            <TabsTrigger value="progress">Progress</TabsTrigger>
            <TabsTrigger value="schedule" className="flex items-center gap-1">
              <Calendar className="w-3 h-3" />
              Schedule
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
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={pageInfo.title}
      description={pageInfo.description}
      breadcrumbs={getBreadcrumbs()}
      actions={getActions()}
    >
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
    </PageContainer>
  );
};

export default RalphLoopsPage;
