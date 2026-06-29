import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Plus } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import type { PageAction, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { useMissions } from '../hooks/useMissions';
import { useMissionModal } from '@/shared/hooks/useMissionModal';
import { MissionsIndexTable } from '../components/MissionsIndexTable';
import { NewMissionWizard } from '../components/new-mission/NewMissionWizard';
import type { CreateMissionParams } from '../types/mission';

export const MissionsContent: React.FC<{
  onActionsReady?: (actions: PageAction[]) => void;
}> = ({ onActionsReady }) => {
  const { openMission } = useMissionModal();
  const [showWizard, setShowWizard] = useState(false);

  const {
    missions,
    loading,
    hasReadPermission,
    hasManagePermission,
    fetchMissions,
    createMission,
  } = useMissions();

  // Fetch missions on mount
  useEffect(() => {
    if (hasReadPermission) fetchMissions();
  }, [hasReadPermission, fetchMissions]);

  // Actions for the PageContainer (bubbled up to MissionsPageWrapper)
  const actions = useMemo<PageAction[]>(() => {
    const items: PageAction[] = [];
    if (hasManagePermission) {
      items.push({
        id: 'new-mission',
        label: 'New Mission',
        onClick: () => setShowWizard(true),
        variant: 'primary',
        icon: Plus,
      });
    }
    return items;
  }, [hasManagePermission]);

  useEffect(() => {
    if (onActionsReady) onActionsReady(actions);
  }, [actions, onActionsReady]);

  // Mission action handlers (called from table row icons via the detail modal)
  const handleStartMission = useCallback(async (missionId: string) => {
    // Open the mission detail modal which has the Start button
    openMission(missionId);
  }, [openMission]);

  const handlePauseMission = useCallback(async (missionId: string) => {
    openMission(missionId);
  }, [openMission]);

  const handleCancelMission = useCallback(async (missionId: string) => {
    openMission(missionId);
  }, [openMission]);

  const handleApproveMission = useCallback(async (missionId: string) => {
    openMission(missionId);
  }, [openMission]);

  if (!hasReadPermission) {
    return (
      <div className="text-center py-12 text-theme-secondary">
        You do not have permission to view missions.
      </div>
    );
  }

  return (
    <>
      <MissionsIndexTable
        missions={missions}
        loading={loading}
        hasManagePermission={hasManagePermission}
        onNewMission={() => setShowWizard(true)}
        onStartMission={handleStartMission}
        onPauseMission={handlePauseMission}
        onCancelMission={handleCancelMission}
        onApproveMission={handleApproveMission}
      />

      {/* New Mission Wizard */}
      <NewMissionWizard
        isOpen={showWizard}
        onClose={() => setShowWizard(false)}
        onCreate={async (data: CreateMissionParams) => {
          const newMission = await createMission(data);
          setShowWizard(false);
          if (newMission?.id) {
            openMission(newMission.id);
          }
        }}
      />
    </>
  );
};

export const MissionsPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  const breadcrumbs = useMemo<BreadcrumbItem[]>(() => [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Missions' },
  ], []);

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
