import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Plus, RefreshCw, Rocket, Clock, CheckCircle2, AlertCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import type { PageAction, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { useMissions } from '../hooks/useMissions';
import { NewMissionWizard } from '../components/new-mission/NewMissionWizard';
import type { Mission, MissionStatus, CreateMissionParams } from '../types/mission';
import { phaseLabel } from '../types/mission';

const TABS = [
  { id: 'active', label: 'Active' },
  { id: 'completed', label: 'Completed' },
  { id: 'all', label: 'All' },
] as const;

type TabId = typeof TABS[number]['id'];

const STATUS_STYLES: Record<MissionStatus, { bg: string; text: string; dot: string }> = {
  draft: { bg: 'bg-theme-surface', text: 'text-theme-secondary', dot: 'bg-theme-secondary' },
  active: { bg: 'bg-theme-info/10', text: 'text-theme-info', dot: 'bg-theme-info' },
  paused: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', dot: 'bg-theme-warning' },
  completed: { bg: 'bg-theme-success/10', text: 'text-theme-success', dot: 'bg-theme-success' },
  failed: { bg: 'bg-theme-error/10', text: 'text-theme-error', dot: 'bg-theme-error' },
  cancelled: { bg: 'bg-theme-surface', text: 'text-theme-tertiary', dot: 'bg-theme-tertiary' },
};

const TYPE_LABELS: Record<string, { label: string; icon: string }> = {
  development: { label: 'Development', icon: '🛠' },
  research: { label: 'Research', icon: '🔬' },
  operations: { label: 'Operations', icon: '⚙' },
};

function formatDuration(ms: number | null): string {
  if (!ms) return '-';
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remainingMins = minutes % 60;
  return `${hours}h ${remainingMins}m`;
}

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

const MissionCard: React.FC<{ mission: Mission; onClick: () => void }> = ({ mission, onClick }) => {
  const statusStyle = STATUS_STYLES[mission.status] || STATUS_STYLES.draft;
  const typeInfo = TYPE_LABELS[mission.mission_type] || { label: mission.mission_type, icon: '📋' };

  return (
    <button
      onClick={onClick}
      className="card-theme-elevated p-5 text-left w-full hover:ring-1 hover:ring-theme-accent/30 transition-all"
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-semibold text-theme-primary truncate">{mission.name}</h3>
          {mission.description && (
            <p className="text-xs text-theme-tertiary mt-1 line-clamp-2">{mission.description}</p>
          )}
        </div>
        <span className={`ml-3 inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium ${statusStyle.bg} ${statusStyle.text}`}>
          <span className={`w-1.5 h-1.5 rounded-full ${statusStyle.dot}`} />
          {mission.status}
        </span>
      </div>

      <div className="flex items-center gap-3 mb-3">
        <span className="inline-flex items-center gap-1 text-xs text-theme-secondary bg-theme-surface px-2 py-0.5 rounded">
          {typeInfo.icon} {typeInfo.label}
        </span>
        {mission.repository && (
          <span className="text-xs text-theme-tertiary truncate">{mission.repository.full_name || mission.repository.name}</span>
        )}
      </div>

      {mission.current_phase && mission.status === 'active' && (
        <div className="mb-3">
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-theme-secondary">{phaseLabel(mission.current_phase)}</span>
            <span className="text-xs text-theme-tertiary">{mission.phase_progress}%</span>
          </div>
          <div className="w-full h-1.5 bg-theme-surface rounded-full overflow-hidden">
            <div
              className="h-full bg-theme-accent rounded-full transition-all"
              style={{ width: `${mission.phase_progress}%` }}
            />
          </div>
        </div>
      )}

      <div className="flex items-center justify-between text-xs text-theme-tertiary">
        <div className="flex items-center gap-1">
          <Clock className="w-3 h-3" />
          {mission.started_at ? timeAgo(mission.started_at) : timeAgo(mission.created_at)}
        </div>
        {mission.duration_ms && (
          <span>{formatDuration(mission.duration_ms)}</span>
        )}
      </div>
    </button>
  );
};

export const MissionsPage: React.FC = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<TabId>('active');
  const [showWizard, setShowWizard] = useState(false);

  const {
    missions,
    loading,
    hasReadPermission,
    hasManagePermission,
    fetchMissions,
    createMission,
  } = useMissions();

  // Sync tab from URL
  useEffect(() => {
    const segment = location.pathname.split('/').filter(Boolean).pop() || '';
    if (segment === 'completed') setActiveTab('completed');
    else if (segment === 'all') setActiveTab('all');
    else setActiveTab('active');
  }, [location.pathname]);

  useEffect(() => {
    if (hasReadPermission) fetchMissions();
  }, [hasReadPermission, fetchMissions]);

  const handleRefresh = useCallback(() => {
    fetchMissions();
  }, [fetchMissions]);

  const navigateTab = useCallback((tab: TabId) => {
    const base = '/app/ai/missions';
    if (tab === 'active') navigate(base);
    else navigate(`${base}/${tab}`);
  }, [navigate]);

  const filteredMissions = useMemo(() => {
    switch (activeTab) {
      case 'active':
        return missions.filter(m => ['draft', 'active', 'paused'].includes(m.status));
      case 'completed':
        return missions.filter(m => ['completed', 'failed', 'cancelled'].includes(m.status));
      case 'all':
      default:
        return missions;
    }
  }, [missions, activeTab]);

  const breadcrumbs = useMemo<BreadcrumbItem[]>(() => [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Missions' },
  ], []);

  const actions = useMemo<PageAction[]>(() => {
    const items: PageAction[] = [
      {
        id: 'refresh',
        label: 'Refresh',
        onClick: handleRefresh,
        variant: 'secondary',
        icon: RefreshCw,
        disabled: loading,
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
    return items;
  }, [handleRefresh, loading, hasManagePermission]);

  if (!hasReadPermission) {
    return (
      <PageContainer
        title="Missions"
        description="AI-assisted development missions"
        breadcrumbs={breadcrumbs}
      >
        <div className="text-center py-12 text-theme-secondary">
          You do not have permission to view missions.
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Missions"
      description="AI-assisted development missions"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Tab Navigation */}
        <div className="flex space-x-1 border-b border-theme-border">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => navigateTab(tab.id)}
              className={`px-4 py-2 text-sm font-medium transition-colors ${
                activeTab === tab.id
                  ? 'text-theme-accent border-b-2 border-theme-accent'
                  : 'text-theme-secondary hover:text-theme-primary'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        {loading && missions.length === 0 ? (
          <div className="text-center py-12 text-theme-secondary">Loading missions...</div>
        ) : filteredMissions.length === 0 ? (
          <div className="text-center py-16">
            <Rocket className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">
              {activeTab === 'active' ? 'No active missions' : activeTab === 'completed' ? 'No completed missions' : 'No missions yet'}
            </h3>
            <p className="text-sm text-theme-tertiary mb-6">
              {activeTab === 'active'
                ? 'Create a new mission to get started with AI-assisted development.'
                : 'Completed missions will appear here.'}
            </p>
            {hasManagePermission && activeTab !== 'completed' && (
              <button
                onClick={() => setShowWizard(true)}
                className="btn-theme btn-theme-primary"
              >
                <Plus className="w-4 h-4 mr-2" />
                New Mission
              </button>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filteredMissions.map((mission) => (
              <MissionCard
                key={mission.id}
                mission={mission}
                onClick={() => navigate(`/app/ai/missions/${mission.id}`)}
              />
            ))}
          </div>
        )}

        {/* Stats row */}
        {missions.length > 0 && (
          <div className="grid grid-cols-3 gap-4">
            <div className="card-theme p-4 text-center">
              <div className="flex items-center justify-center gap-2 mb-1">
                <Rocket className="w-4 h-4 text-theme-info" />
                <span className="text-lg font-bold text-theme-primary">
                  {missions.filter(m => m.status === 'active').length}
                </span>
              </div>
              <span className="text-xs text-theme-tertiary">Active</span>
            </div>
            <div className="card-theme p-4 text-center">
              <div className="flex items-center justify-center gap-2 mb-1">
                <CheckCircle2 className="w-4 h-4 text-theme-success" />
                <span className="text-lg font-bold text-theme-primary">
                  {missions.filter(m => m.status === 'completed').length}
                </span>
              </div>
              <span className="text-xs text-theme-tertiary">Completed</span>
            </div>
            <div className="card-theme p-4 text-center">
              <div className="flex items-center justify-center gap-2 mb-1">
                <AlertCircle className="w-4 h-4 text-theme-error" />
                <span className="text-lg font-bold text-theme-primary">
                  {missions.filter(m => m.status === 'failed').length}
                </span>
              </div>
              <span className="text-xs text-theme-tertiary">Failed</span>
            </div>
          </div>
        )}
      </div>

      {/* New Mission Wizard Modal */}
      <NewMissionWizard
        isOpen={showWizard}
        onClose={() => setShowWizard(false)}
        onCreate={async (data: CreateMissionParams) => {
          await createMission(data);
          setShowWizard(false);
        }}
      />
    </PageContainer>
  );
};
