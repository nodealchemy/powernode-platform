import React, { useState } from 'react';
import { Rocket, Loader2 } from 'lucide-react';
import { PhaseTimeline } from './mission-detail/PhaseTimeline';
import { PhaseCard } from './mission-detail/PhaseCard';
import { MissionSidebar } from './mission-detail/MissionSidebar';
import { AppPreviewPanel } from './mission-detail/AppPreviewPanel';
import { MissionTaskGraph } from './task-graph/MissionTaskGraph';
import { useMissionTaskGraph } from '../hooks/useMissionTaskGraph';
import type { Mission, MissionWebSocketEvent, MissionPhase } from '../types/mission';

interface MissionDetailPanelProps {
  mission: Mission | null;
  loading: boolean;
  error: string | null;
  events: MissionWebSocketEvent[];
}

export const MissionDetailPanel: React.FC<MissionDetailPanelProps> = ({
  mission,
  loading,
  error,
  events,
}) => {
  const [selectedPhase, setSelectedPhase] = useState<MissionPhase | null>(null);
  const { taskGraph, loading: graphLoading } = useMissionTaskGraph(
    mission?.ralph_loop_id ? mission.id : null
  );

  // Empty state
  if (!mission && !loading && !error) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <Rocket className="w-12 h-12 text-theme-tertiary mx-auto mb-3" />
          <p className="text-sm text-theme-secondary">Select a mission to view details</p>
        </div>
      </div>
    );
  }

  // Loading state
  if (loading && !mission) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
      </div>
    );
  }

  // Error state
  if (error && !mission) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <p className="text-sm text-theme-error">{error}</p>
      </div>
    );
  }

  if (!mission) return null;

  const phases = (mission.phases ?? []) as MissionPhase[];

  return (
    <div className="flex-1 overflow-y-auto p-6">
      <div className="space-y-6">
        {/* Mission header */}
        <div>
          <h2 className="text-lg font-semibold text-theme-primary">{mission.name}</h2>
          {mission.description && (
            <p className="text-sm text-theme-secondary mt-1">{mission.description}</p>
          )}
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
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 space-y-4">
            <PhaseCard
              mission={mission}
              events={events}
            />
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
      </div>
    </div>
  );
};
