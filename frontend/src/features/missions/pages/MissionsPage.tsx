import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import { RefreshCw, Plus, Play, Pause, XCircle, RotateCcw, ArrowLeft } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import type { PageAction, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { useMissions } from '../hooks/useMissions';
import { useMission } from '../hooks/useMission';
import { MissionListPanel } from '../components/MissionListPanel';
import type { MissionTabId } from '../components/MissionListPanel';
import { MissionDetailPanel } from '../components/MissionDetailPanel';
import { NewMissionWizard } from '../components/new-mission/NewMissionWizard';
import { ApprovalGateModal } from '../components/mission-detail/ApprovalGateModal';
import { isApprovalGate } from '../types/mission';
import type { CreateMissionParams } from '../types/mission';

export const MissionsContent: React.FC<{
  onActionsReady?: (actions: PageAction[]) => void;
}> = ({ onActionsReady }) => {
  const { missionId } = useParams<{ missionId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const [activeTab, setActiveTab] = useState<MissionTabId>('active');
  const [showWizard, setShowWizard] = useState(false);
  const [showApprovalModal, setShowApprovalModal] = useState(false);
  const [showMobileDetail, setShowMobileDetail] = useState(false);

  const {
    missions,
    loading: listLoading,
    hasReadPermission,
    hasManagePermission,
    fetchMissions,
    createMission,
  } = useMissions();

  const {
    mission: selectedMission,
    loading: detailLoading,
    error: detailError,
    events,
    hasManagePermission: detailManagePermission,
    startMission,
    approveMission,
    rejectMission,
    pauseMission,
    cancelMission,
    retryPhase,
  } = useMission(missionId);

  // Sync tab from URL (only when no missionId)
  useEffect(() => {
    if (missionId) return;
    const segment = location.pathname.split('/').filter(Boolean).pop() || '';
    if (segment === 'completed') setActiveTab('completed');
    else if (segment === 'all') setActiveTab('all');
    else setActiveTab('active');
  }, [location.pathname, missionId]);

  // Fetch missions on mount
  useEffect(() => {
    if (hasReadPermission) fetchMissions();
  }, [hasReadPermission, fetchMissions]);

  // Show mobile detail when missionId is present
  useEffect(() => {
    setShowMobileDetail(!!missionId);
  }, [missionId]);

  // Auto-open approval modal when navigated from notification
  useEffect(() => {
    const state = location.state as { openApproval?: boolean } | null;
    if (state?.openApproval && selectedMission && isApprovalGate(selectedMission.current_phase, selectedMission.approval_gate_phases)) {
      setShowApprovalModal(true);
      // Clear the state so refreshing doesn't re-open
      navigate(location.pathname, { replace: true, state: {} });
    }
  }, [location.state, selectedMission, navigate, location.pathname]);

  const handleRefresh = useCallback(() => {
    fetchMissions();
  }, [fetchMissions]);

  const handleSelectMission = useCallback((id: string) => {
    navigate(`/app/ai/missions/${id}`);
  }, [navigate]);

  const handleTabChange = useCallback((tab: MissionTabId) => {
    setActiveTab(tab);
    if (!missionId) {
      const base = '/app/ai/missions';
      if (tab === 'active') navigate(base);
      else navigate(`${base}/${tab}`);
    }
  }, [navigate, missionId]);

  const handleBack = useCallback(() => {
    setShowMobileDetail(false);
    navigate('/app/ai/missions');
  }, [navigate]);

  // Build actions and bubble up to parent
  const actions = useMemo<PageAction[]>(() => {
    const items: PageAction[] = [
      {
        id: 'refresh',
        label: 'Refresh',
        onClick: handleRefresh,
        variant: 'secondary',
        icon: RefreshCw,
        disabled: listLoading,
      },
    ];

    if (hasManagePermission) {
      items.push({
        id: 'new-mission',
        label: 'New Mission',
        onClick: () => setShowWizard(true),
        variant: 'primary',
        icon: Plus,
      });
    }

    if (selectedMission && detailManagePermission) {
      if (selectedMission.status === 'draft') {
        items.push({
          id: 'start',
          label: 'Start Mission',
          onClick: startMission,
          variant: 'primary',
          icon: Play,
        });
      }

      if (selectedMission.status === 'active' && isApprovalGate(selectedMission.current_phase, selectedMission.approval_gate_phases)) {
        items.push({
          id: 'review',
          label: 'Review & Approve',
          onClick: () => setShowApprovalModal(true),
          variant: 'primary',
        });
      }

      if (selectedMission.status === 'active') {
        items.push({
          id: 'pause',
          label: 'Pause',
          onClick: pauseMission,
          variant: 'secondary',
          icon: Pause,
        });
      }

      if (selectedMission.status === 'failed') {
        items.push({
          id: 'retry',
          label: 'Retry',
          onClick: retryPhase,
          variant: 'secondary',
          icon: RotateCcw,
        });
      }

      if (['draft', 'active', 'paused'].includes(selectedMission.status)) {
        items.push({
          id: 'cancel',
          label: 'Cancel',
          onClick: () => cancelMission('Cancelled by user'),
          variant: 'danger',
          icon: XCircle,
        });
      }
    }

    return items;
  }, [handleRefresh, listLoading, hasManagePermission, selectedMission, detailManagePermission, startMission, pauseMission, cancelMission, retryPhase]);

  useEffect(() => {
    if (onActionsReady) onActionsReady(actions);
  }, [actions, onActionsReady]);

  if (!hasReadPermission) {
    return (
      <div className="text-center py-12 text-theme-secondary">
        You do not have permission to view missions.
      </div>
    );
  }

  return (
    <>
      <div className="flex h-[calc(100vh-220px)] -mx-6 -mb-6 overflow-hidden">
        {/* Left panel - hidden on mobile when detail is showing */}
        <div className={`${showMobileDetail ? 'hidden lg:flex' : 'flex'}`}>
          <MissionListPanel
            missions={missions}
            loading={listLoading}
            selectedMissionId={missionId || null}
            activeTab={activeTab}
            onTabChange={handleTabChange}
            onSelectMission={handleSelectMission}
            onNewMission={() => setShowWizard(true)}
            hasManagePermission={hasManagePermission}
          />
        </div>

        {/* Right panel */}
        <div className={`flex-1 flex flex-col min-w-0 ${showMobileDetail ? 'flex' : 'hidden lg:flex'}`}>
          {/* Mobile back button */}
          {showMobileDetail && (
            <div className="lg:hidden px-4 py-2 border-b border-theme">
              <button
                onClick={handleBack}
                className="flex items-center gap-1 text-sm text-theme-secondary hover:text-theme-primary transition-colors"
              >
                <ArrowLeft className="w-4 h-4" />
                Back to list
              </button>
            </div>
          )}
          <MissionDetailPanel
            mission={selectedMission}
            loading={detailLoading}
            error={detailError}
            events={events}
          />
        </div>
      </div>

      {/* New Mission Wizard */}
      <NewMissionWizard
        isOpen={showWizard}
        onClose={() => setShowWizard(false)}
        onCreate={async (data: CreateMissionParams) => {
          const newMission = await createMission(data);
          setShowWizard(false);
          if (newMission?.id) {
            navigate(`/app/ai/missions/${newMission.id}`);
          }
        }}
      />

      {/* Approval Modal */}
      {selectedMission && (
        <ApprovalGateModal
          isOpen={showApprovalModal}
          mission={selectedMission}
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
    </>
  );
};

export const MissionsPage: React.FC = () => {
  const { missionId } = useParams<{ missionId: string }>();
  const [actions, setActions] = useState<PageAction[]>([]);

  const breadcrumbs = useMemo<BreadcrumbItem[]>(() => {
    const crumbs: BreadcrumbItem[] = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'Missions' },
    ];
    return crumbs;
  }, [missionId]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="Missions"
      description="AI-assisted development missions"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <MissionsContent onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};
