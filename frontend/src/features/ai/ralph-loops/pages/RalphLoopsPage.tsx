import React, { useState, useCallback, useEffect } from 'react';
import { Calendar } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotification } from '@/shared/hooks/useNotification';
import { LoopSettingsModal } from '../components/LoopSettingsModal';
import { CreateRalphLoopDialog } from '../components/CreateRalphLoopDialog';
import { RalphLoopScheduleConfig } from '../components/RalphLoopScheduleConfig';
import { RalphLoopListPanel } from '../components/RalphLoopListPanel';
import { RalphLoopDetailPanel } from '../components/RalphLoopDetailPanel';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
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

interface RalphLoopsContentProps {
  refreshKey?: number;
}

export const RalphLoopsContent: React.FC<RalphLoopsContentProps> = ({ refreshKey: externalRefreshKey }) => {
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

    if (update.type === 'loop_started') {
      loadLoop(selectedLoop.id);
    } else if (update.type === 'loop_progress' || update.type === 'task_status_changed') {
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
    } else if (['loop_completed', 'loop_failed', 'loop_cancelled'].includes(update.type)) {
      loadLoop(selectedLoop.id);
    } else if (update.type === 'iteration_completed') {
      loadLoop(selectedLoop.id);
      const iterationNumber = update.data?.iteration_number;
      if (iterationNumber) {
        ralphLoopsApi.getIteration(selectedLoop.id, String(iterationNumber))
          .then(res => {
            setLiveIterations(prev => [...prev, res.iteration]);
          })
          .catch(() => {});
      }
    } else if (update.type === 'run_all_started') {
      loadLoop(selectedLoop.id);
    } else if (update.type === 'run_all_completed') {
      loadLoop(selectedLoop.id);
      showNotification('Run All completed', 'success');
    }
  }, [selectedLoop?.id]);

  // WebSocket for real-time updates
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

  return (
    <>
      {/* Split panel layout */}
      <div className="flex h-[calc(100vh-280px)]">
        <RalphLoopListPanel
          selectedLoopId={selectedLoop?.id || null}
          onSelectLoop={handleSelectLoop}
          onCreateLoop={handleCreateLoop}
          refreshKey={refreshKey}
        />
        <RalphLoopDetailPanel
          loop={selectedLoop}
          loading={loading}
          error={error}
          wsConnected={wsConnected}
          liveIterations={liveIterations}
          editedTasks={editedTasks}
          activeTab={activeTab}
          onActiveTabChange={setActiveTab}
          onTasksChange={handleTasksChange}
          onSavePrd={handleSavePrd}
          onShowScheduleConfig={() => setShowScheduleConfigModal(true)}
          onPauseSchedule={handlePauseSchedule}
          onResumeSchedule={handleResumeSchedule}
          onRegenerateToken={handleRegenerateToken}
          scheduleLoading={scheduleLoading}
        />
      </div>

      {/* Modals — outside flex container */}
      <CreateRalphLoopDialog
        isOpen={showCreateDialog}
        onClose={() => setShowCreateDialog(false)}
        onCreated={handleLoopCreated}
      />

      {selectedLoop && (
        <>
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

          <LoopSettingsModal
            isOpen={showSettingsModal}
            onClose={() => setShowSettingsModal(false)}
            settingsForm={settingsForm}
            onFormChange={(updates) => setSettingsForm(prev => ({ ...prev, ...updates }))}
            onSave={handleSaveSettings}
            loading={settingsLoading}
            agents={settingsAgents}
          />
        </>
      )}
    </>
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
