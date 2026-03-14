import { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { skillsApi } from './services/skillsApi';
import { skillLifecycleApi } from './services/skillLifecycleApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { TabContainer } from '@/shared/components/layout/TabContainer';
import { SkillCard } from './components/SkillCard';
import { SkillDetailPanel } from './components/SkillDetailPanel';
import { SkillEditor } from './components/SkillEditor';
import { ResearchModal } from './components/ResearchModal';
import { ProposalsList } from './components/ProposalsList';
import { SkillGraphEmbed } from './components/SkillGraphEmbed';
import { OptimizationDashboard } from './components/OptimizationDashboard';
import type { AiSkillSummary, SkillCategory, SkillFilters } from './types';
import type { PageAction } from '@/shared/components/layout/PageContainer';

interface SkillsPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

const ALL_CATEGORIES: { value: SkillCategory | ''; label: string }[] = [
  { value: '', label: 'All' },
  { value: 'productivity', label: 'Productivity' },
  { value: 'sales', label: 'Sales' },
  { value: 'customer_support', label: 'Support' },
  { value: 'product_management', label: 'Product' },
  { value: 'marketing', label: 'Marketing' },
  { value: 'legal', label: 'Legal' },
  { value: 'finance', label: 'Finance' },
  { value: 'data', label: 'Data' },
  { value: 'business_search', label: 'Search' },
  { value: 'bio_research', label: 'Bio' },
  { value: 'skill_management', label: 'Management' },
  { value: 'code_intelligence', label: 'Code Intel' },
  { value: 'testing_qa', label: 'Testing' },
  { value: 'devops', label: 'DevOps' },
  { value: 'security', label: 'Security' },
  { value: 'sre_observability', label: 'SRE' },
  { value: 'database_ops', label: 'Database' },
  { value: 'release_management', label: 'Releases' },
  { value: 'research', label: 'Research' },
  { value: 'documentation', label: 'Docs' },
];

type TopTab = 'skills' | 'graph' | 'proposals' | 'optimization';

const SKILLS_BASE_PATH = '/app/ai/knowledge/skills';

const getSubTab = (pathname: string): TopTab => {
  if (pathname.includes('/skills/graph')) return 'graph';
  if (pathname.includes('/skills/proposals')) return 'proposals';
  if (pathname.includes('/skills/optimization')) return 'optimization';
  return 'skills';
};

export function SkillsPage({ onActionsReady }: SkillsPageProps) {
  const { showNotification } = useNotifications();
  const location = useLocation();
  const [skills, setSkills] = useState<AiSkillSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedCategory, setSelectedCategory] = useState<string>('');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedSkillId, setSelectedSkillId] = useState<string | null>(null);
  const [showEditor, setShowEditor] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [activeTab, setActiveTab] = useState<TopTab>(getSubTab(location.pathname));
  const [pendingCount, setPendingCount] = useState(0);
  const [showResearch, setShowResearch] = useState(false);

  const loadSkills = useCallback(async () => {
    setLoading(true);
    const filters: SkillFilters = {};
    if (selectedCategory) filters.category = selectedCategory as SkillCategory;
    if (searchQuery) filters.search = searchQuery;

    const response = await skillsApi.getSkills(1, 100, filters);
    if (response.success && response.data) {
      setSkills(response.data.skills);
    } else {
      showNotification(response.error || 'Failed to load skills', 'error');
    }
    setLoading(false);
  }, [selectedCategory, searchQuery, showNotification]);

  const loadPendingCount = useCallback(async () => {
    const response = await skillLifecycleApi.getProposals(1, 'proposed');
    if (response.success && response.data) {
      setPendingCount(response.data.proposals.length);
    }
  }, []);

  const { refreshAction } = useRefreshAction({
    onRefresh: async () => {
      setIsRefreshing(true);
      await loadSkills();
      await loadPendingCount();
      setIsRefreshing(false);
    },
    loading: isRefreshing,
  });

  // Sync sub-tab state from URL path
  useEffect(() => {
    const newTab = getSubTab(location.pathname);
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  useEffect(() => {
    loadSkills();
    loadPendingCount();
  }, [loadSkills, loadPendingCount]);

  useEffect(() => {
    if (onActionsReady) {
      onActionsReady([
        refreshAction,
        {
          id: 'research',
          label: 'Research',
          onClick: () => setShowResearch(true),
          variant: 'secondary',
        },
        {
          id: 'new-skill',
          label: 'New Skill',
          onClick: () => setShowEditor(true),
          variant: 'primary',
        },
      ]);
    }
  }, [onActionsReady, refreshAction]);

  const handleToggle = async (id: string, enabled: boolean) => {
    const response = enabled
      ? await skillsApi.activateSkill(id)
      : await skillsApi.deactivateSkill(id);

    if (response.success) {
      showNotification(`Skill ${enabled ? 'enabled' : 'disabled'}`, 'success');
      loadSkills();
    } else {
      showNotification(response.error || 'Failed to toggle skill', 'error');
    }
  };

  const handleProposalCreated = () => {
    setActiveTab('proposals');
    loadPendingCount();
  };

  if (showEditor) {
    return (
      <SkillEditor
        onSaved={() => {
          setShowEditor(false);
          loadSkills();
        }}
        onCancel={() => setShowEditor(false)}
      />
    );
  }

  const topTabs = [
    { id: 'skills', label: 'Skills', path: '/' },
    { id: 'graph', label: 'Skill Graph', path: '/graph' },
    {
      id: 'proposals',
      label: 'Proposals',
      path: '/proposals',
      badge: pendingCount > 0 ? { count: pendingCount, variant: 'warning' as const } : undefined,
    },
    { id: 'optimization', label: 'Optimization', path: '/optimization' },
  ];

  return (
    <div className="space-y-6">
      {/* Top-level Tabs */}
      <TabContainer
        tabs={topTabs}
        activeTab={activeTab}
        onTabChange={(tabId) => setActiveTab(tabId as TopTab)}
        basePath={SKILLS_BASE_PATH}
        variant="pills"
        size="md"
      />

      {/* Skills Tab */}
      {activeTab === 'skills' && (
        <div className="space-y-6">
          {/* Search */}
          <div>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search skills..."
              className="w-full max-w-md px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>

          {/* Category Tabs */}
          <TabContainer
            tabs={ALL_CATEGORIES.map((cat) => ({
              id: cat.value || 'all',
              label: cat.label,
            }))}
            activeTab={selectedCategory || 'all'}
            onTabChange={(tabId) => setSelectedCategory(tabId === 'all' ? '' : tabId)}
            variant="underline"
            size="sm"
            compact
          />

          {/* Skills Grid */}
          {loading ? (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {[1, 2, 3, 4, 5, 6].map((i) => (
                <div key={i} className="animate-pulse bg-theme-surface border border-theme rounded-lg p-5">
                  <div className="h-5 bg-theme-surface-secondary rounded w-3/4 mb-3" />
                  <div className="h-3 bg-theme-surface-secondary rounded w-1/2 mb-3" />
                  <div className="h-8 bg-theme-surface-secondary rounded mb-3" />
                </div>
              ))}
            </div>
          ) : skills.length === 0 ? (
            <div className="text-center py-12 text-theme-tertiary">
              <p className="text-lg">No skills found</p>
              <p className="text-sm mt-1">
                {searchQuery || selectedCategory
                  ? 'Try adjusting your search or filters'
                  : 'Create your first skill to get started'}
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {skills.map((skill) => (
                <SkillCard
                  key={skill.id}
                  skill={skill}
                  onToggle={handleToggle}
                  onClick={(id) => setSelectedSkillId(id)}
                />
              ))}
            </div>
          )}

          {/* Detail Panel */}
          {selectedSkillId && (
            <SkillDetailPanel
              skillId={selectedSkillId}
              onClose={() => setSelectedSkillId(null)}
              onUpdated={loadSkills}
            />
          )}
        </div>
      )}

      {/* Skill Graph Tab */}
      {activeTab === 'graph' && (
        <SkillGraphEmbed
          focusSkillId={(location.state as { focusSkillId?: string } | null)?.focusSkillId}
          onViewSkill={(skillId) => {
            setActiveTab('skills');
            setSelectedSkillId(skillId);
          }}
        />
      )}

      {/* Proposals Tab */}
      {activeTab === 'proposals' && <ProposalsList />}

      {/* Optimization Tab */}
      {activeTab === 'optimization' && <OptimizationDashboard />}

      {/* Research Modal */}
      <ResearchModal
        isOpen={showResearch}
        onClose={() => setShowResearch(false)}
        onProposalCreated={handleProposalCreated}
      />
    </div>
  );
}
