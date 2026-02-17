import React, { useMemo, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Play, Pause, XCircle, RotateCcw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import type { PageAction, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { useMission } from '../hooks/useMission';
import { PhaseTimeline } from '../components/mission-detail/PhaseTimeline';
import { PhaseCard } from '../components/mission-detail/PhaseCard';
import { MissionSidebar } from '../components/mission-detail/MissionSidebar';
import { AppPreviewPanel } from '../components/mission-detail/AppPreviewPanel';
import { ApprovalGateModal } from '../components/mission-detail/ApprovalGateModal';
import { isApprovalGate, phasesForType } from '../types/mission';

export const MissionDetailPage: React.FC = () => {
  const { missionId } = useParams<{ missionId: string }>();
  const navigate = useNavigate();
  const [showApprovalModal, setShowApprovalModal] = useState(false);

  const {
    mission,
    loading,
    error,
    events,
    hasManagePermission,
    startMission,
    approveMission,
    rejectMission,
    pauseMission,
    cancelMission,
    retryPhase,
  } = useMission(missionId);

  const breadcrumbs = useMemo<BreadcrumbItem[]>(() => [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Missions', href: '/app/ai/missions' },
    { label: mission?.name || 'Loading...' },
  ], [mission?.name]);

  const actions = useMemo<PageAction[]>(() => {
    if (!mission || !hasManagePermission) return [];
    const items: PageAction[] = [
      {
        id: 'back',
        label: 'Back',
        onClick: () => navigate('/app/ai/missions'),
        variant: 'secondary',
        icon: ArrowLeft,
      },
    ];

    if (mission.status === 'draft') {
      items.push({
        id: 'start',
        label: 'Start Mission',
        onClick: startMission,
        variant: 'primary',
        icon: Play,
      });
    }

    if (mission.status === 'active' && isApprovalGate(mission.current_phase)) {
      items.push({
        id: 'review',
        label: 'Review & Approve',
        onClick: () => setShowApprovalModal(true),
        variant: 'primary',
      });
    }

    if (mission.status === 'active') {
      items.push({
        id: 'pause',
        label: 'Pause',
        onClick: pauseMission,
        variant: 'secondary',
        icon: Pause,
      });
    }

    if (mission.status === 'failed') {
      items.push({
        id: 'retry',
        label: 'Retry',
        onClick: retryPhase,
        variant: 'secondary',
        icon: RotateCcw,
      });
    }

    if (['draft', 'active', 'paused'].includes(mission.status)) {
      items.push({
        id: 'cancel',
        label: 'Cancel',
        onClick: () => cancelMission('Cancelled by user'),
        variant: 'danger',
        icon: XCircle,
      });
    }

    return items;
  }, [mission, hasManagePermission, navigate, startMission, pauseMission, cancelMission, retryPhase]);

  if (loading && !mission) {
    return (
      <PageContainer title="Loading..." breadcrumbs={breadcrumbs}>
        <div className="text-center py-12 text-theme-secondary">Loading mission details...</div>
      </PageContainer>
    );
  }

  if (error || !mission) {
    return (
      <PageContainer title="Mission Not Found" breadcrumbs={breadcrumbs}>
        <div className="text-center py-12">
          <p className="text-theme-error mb-4">{error || 'Mission not found'}</p>
          <button onClick={() => navigate('/app/ai/missions')} className="btn-theme btn-theme-secondary">
            <ArrowLeft className="w-4 h-4 mr-2" /> Back to Missions
          </button>
        </div>
      </PageContainer>
    );
  }

  const phases = phasesForType(mission.mission_type);

  return (
    <PageContainer
      title={mission.name}
      description={mission.description || undefined}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Phase Timeline */}
        <PhaseTimeline
          phases={phases}
          currentPhase={mission.current_phase}
          phaseHistory={mission.phase_history}
          status={mission.status}
        />

        {/* Main Content + Sidebar */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Main content area */}
          <div className="lg:col-span-2 space-y-4">
            {/* Current phase detail */}
            <PhaseCard
              mission={mission}
              events={events}
            />

            {/* App Preview if deployed */}
            {mission.deployed_url && (
              <AppPreviewPanel
                url={mission.deployed_url}
                port={mission.deployed_port}
                containerId={mission.deployed_container_id}
              />
            )}
          </div>

          {/* Sidebar */}
          <div className="lg:col-span-1">
            <MissionSidebar mission={mission} />
          </div>
        </div>
      </div>

      {/* Approval Modal */}
      {mission && (
        <ApprovalGateModal
          isOpen={showApprovalModal}
          mission={mission}
          onApprove={async (data: { comment?: string; selected_feature?: Record<string, unknown> }) => {
            await approveMission(data);
            setShowApprovalModal(false);
          }}
          onReject={async (data: { comment?: string }) => {
            await rejectMission(data);
            setShowApprovalModal(false);
          }}
          onClose={() => setShowApprovalModal(false)}
        />
      )}
    </PageContainer>
  );
};
