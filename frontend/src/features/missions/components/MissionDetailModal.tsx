import React, { useState, useEffect, useCallback } from 'react';
import { Rocket, Play, Pause, XCircle, CheckCircle, RotateCcw, Loader2 } from 'lucide-react';
import { useMissionModal } from '@/shared/hooks/useMissionModal';
import { useNotification } from '@/shared/hooks/useNotification';
import { Modal } from '@/shared/components/ui/Modal';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { PhaseTimeline } from './mission-detail/PhaseTimeline';
import { PhaseCard } from './mission-detail/PhaseCard';
import { MissionSidebar } from './mission-detail/MissionSidebar';
import { AppPreviewPanel } from './mission-detail/AppPreviewPanel';
import { ApprovalGateModal } from './mission-detail/ApprovalGateModal';
import { MissionTaskGraph } from './task-graph/MissionTaskGraph';
import { useMission } from '../hooks/useMission';
import { useMissionTaskGraph } from '../hooks/useMissionTaskGraph';
import { STATUS_CONFIG, MISSION_TYPE_LABELS } from '../constants/missionConstants';
import { isApprovalGate } from '../types/mission';
import type { MissionPhase } from '../types/mission';

export const MissionDetailModal: React.FC = () => {
  const { missionId, isOpen, closeMission } = useMissionModal();
  const { showNotification } = useNotification();
  const {
    mission, loading, error, events, hasManagePermission,
    startMission, approveMission, rejectMission, pauseMission, cancelMission, retryPhase,
  } = useMission(isOpen ? missionId ?? undefined : undefined);

  const { taskGraph, loading: graphLoading } = useMissionTaskGraph(
    mission?.ralph_loop_id ? mission.id : null
  );

  const [selectedPhase, setSelectedPhase] = useState<MissionPhase | null>(null);
  const [showApprovalModal, setShowApprovalModal] = useState(false);

  // Reset selected phase when mission changes
  useEffect(() => {
    setSelectedPhase(null);
    setShowApprovalModal(false);
  }, [missionId]);

  // --- Action Handlers ---

  const handleStart = useCallback(async () => {
    try {
      await startMission();
      showNotification('Mission started', 'success');
    } catch {
      showNotification('Failed to start mission', 'error');
    }
  }, [startMission, showNotification]);

  const handlePause = useCallback(async () => {
    try {
      await pauseMission();
      showNotification('Mission paused', 'success');
    } catch {
      showNotification('Failed to pause mission', 'error');
    }
  }, [pauseMission, showNotification]);

  const handleCancel = useCallback(async () => {
    try {
      await cancelMission();
      showNotification('Mission cancelled', 'info');
      closeMission();
    } catch {
      showNotification('Failed to cancel mission', 'error');
    }
  }, [cancelMission, showNotification, closeMission]);

  const handleRetry = useCallback(async () => {
    try {
      await retryPhase();
      showNotification('Retrying phase', 'success');
    } catch {
      showNotification('Failed to retry phase', 'error');
    }
  }, [retryPhase, showNotification]);

  const handleApprove = useCallback(async (data: { comment?: string; selected_feature?: Record<string, unknown> }) => {
    try {
      await approveMission(data);
      showNotification('Mission approved', 'success');
      setShowApprovalModal(false);
    } catch {
      showNotification('Failed to approve mission', 'error');
    }
  }, [approveMission, showNotification]);

  const handleReject = useCallback(async (data: { comment?: string }) => {
    try {
      await rejectMission(data);
      showNotification('Mission rejected', 'info');
      setShowApprovalModal(false);
    } catch {
      showNotification('Failed to reject mission', 'error');
    }
  }, [rejectMission, showNotification]);

  // --- Render Content ---

  const renderContent = () => {
    if (loading && !mission) {
      return (
        <div className="flex items-center justify-center py-24">
          <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
        </div>
      );
    }

    if (error && !mission) {
      return (
        <div className="flex items-center justify-center py-24">
          <p className="text-sm text-theme-error">{error}</p>
        </div>
      );
    }

    if (!mission) return null;

    const statusConfig = STATUS_CONFIG[mission.status];
    const phases = (mission.phases ?? []) as MissionPhase[];

    return (
      <div className="px-6 py-5 overflow-y-auto max-h-[80vh]">
        {/* Header */}
        <div className="flex items-start justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <Rocket className="h-5 w-5 text-theme-info" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">{mission.name}</h2>
              <div className="flex items-center gap-2 mt-0.5">
                <Badge variant={statusConfig.variant} size="sm">{statusConfig.label}</Badge>
                <Badge variant="outline" size="xs">{MISSION_TYPE_LABELS[mission.mission_type]}</Badge>
                {mission.repository && (
                  <span className="text-xs text-theme-tertiary">{mission.repository.name}</span>
                )}
              </div>
            </div>
          </div>

          {/* Context-aware action buttons */}
          <div className="flex items-center gap-1.5">
            {mission.status === 'draft' && hasManagePermission && (
              <Button variant="primary" size="sm" onClick={handleStart}>
                <Play className="h-3.5 w-3.5 mr-1" />Start
              </Button>
            )}
            {mission.status === 'active' && isApprovalGate(mission.current_phase, mission.approval_gate_phases) && hasManagePermission && (
              <Button variant="success" size="sm" onClick={() => setShowApprovalModal(true)}>
                <CheckCircle className="h-3.5 w-3.5 mr-1" />Review
              </Button>
            )}
            {mission.status === 'active' && hasManagePermission && (
              <Button variant="warning" size="sm" onClick={handlePause}>
                <Pause className="h-3.5 w-3.5 mr-1" />Pause
              </Button>
            )}
            {mission.status === 'failed' && hasManagePermission && (
              <Button variant="outline" size="sm" onClick={handleRetry}>
                <RotateCcw className="h-3.5 w-3.5 mr-1" />Retry
              </Button>
            )}
            {['active', 'paused', 'draft'].includes(mission.status) && hasManagePermission && (
              <Button variant="danger" size="sm" onClick={handleCancel}>
                <XCircle className="h-3.5 w-3.5 mr-1" />Cancel
              </Button>
            )}
          </div>
        </div>

        {/* Phase Timeline */}
        <PhaseTimeline
          phases={phases}
          currentPhase={mission.current_phase}
          phaseHistory={mission.phase_history}
          status={mission.status}
          onPhaseClick={setSelectedPhase}
          selectedPhase={selectedPhase}
        />

        {/* Task Graph (when ralph_loop exists) */}
        {mission.ralph_loop_id && (
          <MissionTaskGraph
            taskGraph={taskGraph}
            loading={graphLoading}
            selectedPhase={selectedPhase}
          />
        )}

        {/* Main Content + Sidebar */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mt-6">
          <div className="lg:col-span-2 space-y-4">
            <PhaseCard mission={mission} events={events} />
            {mission.deployed_url && (
              <AppPreviewPanel
                url={mission.deployed_url}
                port={mission.deployed_port}
                containerId={mission.deployed_container_id}
              />
            )}
          </div>
          <div className="lg:col-span-1">
            <MissionSidebar mission={mission} />
          </div>
        </div>

        {/* Approval Gate Modal */}
        <ApprovalGateModal
          isOpen={showApprovalModal}
          mission={mission}
          onApprove={handleApprove}
          onReject={handleReject}
          onClose={() => setShowApprovalModal(false)}
        />
      </div>
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={closeMission}
      title=""
      maxWidth="5xl"
      variant="centered"
      disableContentScroll
    >
      {renderContent()}
    </Modal>
  );
};
