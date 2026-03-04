import React, { useState, useEffect } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import { Bot, MessageSquare, Brain, ArrowLeft, BookOpen, Trophy, Lightbulb } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { agentsApi, intelligenceApi } from '@/shared/services/ai';
import type { ExperienceReplay, SelfChallenge, IntelligenceSummary } from '@/shared/services/ai/IntelligenceApiService';
import { AgentConnectionsGraph } from '@/features/ai/agents/components/AgentConnectionsGraph';
import { ContextBrowser } from '@/features/ai/memory/components/ContextBrowser';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import type { AiAgent } from '@/shared/types/ai';

const tabs = [
  { id: 'overview', label: 'Overview', path: '/' },
  { id: 'intelligence', label: 'Intelligence', path: '/intelligence' },
  { id: 'connections', label: 'Connections', path: '/connections' },
  { id: 'knowledge', label: 'Knowledge', path: '/knowledge' },
];

// ---- Intelligence Tab Content ----
const getDifficultyColor = (d: string) => {
  switch (d) {
    case 'easy': return 'success';
    case 'medium': return 'info';
    case 'hard': return 'warning';
    case 'expert': return 'danger';
    default: return 'secondary';
  }
};

const getChallengeStatusColor = (s: string) => {
  switch (s) {
    case 'completed': return 'success';
    case 'failed': case 'abandoned': return 'danger';
    case 'executing': case 'validating': return 'info';
    default: return 'secondary';
  }
};

const IntelligenceContent: React.FC<{ agentId: string }> = ({ agentId }) => {
  const [summary, setSummary] = useState<IntelligenceSummary | null>(null);
  const [replays, setReplays] = useState<ExperienceReplay[]>([]);
  const [challenges, setChallenges] = useState<SelfChallenge[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const [summaryRes, replaysRes, challengesRes] = await Promise.all([
        intelligenceApi.getIntelligenceSummary(agentId).catch(() => null),
        intelligenceApi.getExperienceReplays(agentId, { per_page: 10 }).catch(() => null),
        intelligenceApi.getSelfChallenges(agentId, { per_page: 10 }).catch(() => null),
      ]);
      if (summaryRes?.summary) setSummary(summaryRes.summary);
      if (replaysRes?.items) setReplays(replaysRes.items);
      if (challengesRes?.items) setChallenges(challengesRes.items);
      setLoading(false);
    };
    load();
  }, [agentId]);

  if (loading) return <LoadingSpinner size="md" className="py-8" message="Loading intelligence data..." />;

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      {summary && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{summary.experience_replays.active}</div>
            <div className="text-xs text-theme-tertiary">Active Replays</div>
            <div className="text-xs text-theme-secondary mt-1">Avg Quality: {(summary.experience_replays.avg_quality * 100).toFixed(0)}%</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{(summary.experience_replays.avg_effectiveness * 100).toFixed(0)}%</div>
            <div className="text-xs text-theme-tertiary">Replay Effectiveness</div>
            <div className="text-xs text-theme-secondary mt-1">{summary.experience_replays.total} total</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{summary.self_challenges.completed}</div>
            <div className="text-xs text-theme-tertiary">Challenges Completed</div>
            <div className="text-xs text-theme-secondary mt-1">{summary.self_challenges.active} active</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{summary.self_challenges.pass_rate.toFixed(0)}%</div>
            <div className="text-xs text-theme-tertiary">Challenge Pass Rate</div>
            <div className="text-xs text-theme-secondary mt-1">{summary.self_challenges.total} total</div>
          </Card>
        </div>
      )}

      {/* Experience Replays */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Lightbulb size={18} className="text-theme-warning" />
          <h3 className="text-lg font-medium text-theme-primary">Experience Replays</h3>
          <Badge variant="secondary" size="sm">{replays.length}</Badge>
        </div>
        {replays.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No experience replays captured yet. Replays are created from successful executions.</p>
        ) : (
          <div className="space-y-3">
            {replays.map(r => (
              <div key={r.id} className="border border-theme-border rounded-lg p-3">
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={r.status === 'active' ? 'success' : 'secondary'} size="sm">{r.status}</Badge>
                    <span className="text-xs text-theme-tertiary">{new Date(r.created_at).toLocaleDateString()}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs">
                    <span className="text-theme-secondary">Quality: <strong>{((r.quality_score || 0) * 100).toFixed(0)}%</strong></span>
                    <span className="text-theme-secondary">Effect: <strong>{((r.effectiveness_score || 0) * 100).toFixed(0)}%</strong></span>
                    <span className="text-theme-tertiary">Injected {r.injection_count}x</span>
                  </div>
                </div>
                <p className="text-sm text-theme-secondary line-clamp-2">{r.compressed_example}</p>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Self-Challenges */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Trophy size={18} className="text-theme-info" />
          <h3 className="text-lg font-medium text-theme-primary">Self-Challenges</h3>
          <Badge variant="secondary" size="sm">{challenges.length}</Badge>
        </div>
        {challenges.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No self-challenges generated yet. Challenges test and improve agent capabilities.</p>
        ) : (
          <div className="space-y-3">
            {challenges.map(c => (
              <div key={c.id} className="border border-theme-border rounded-lg p-3">
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={getChallengeStatusColor(c.status) as 'success' | 'danger' | 'info' | 'secondary'} size="sm">{c.status}</Badge>
                    <Badge variant={getDifficultyColor(c.difficulty) as 'success' | 'info' | 'warning' | 'danger'} size="sm">{c.difficulty}</Badge>
                    {c.skill && <span className="text-xs text-theme-info">{c.skill.name}</span>}
                  </div>
                  <div className="flex items-center gap-2 text-xs">
                    {c.quality_score != null && <span className="text-theme-secondary">Score: <strong>{(c.quality_score * 100).toFixed(0)}%</strong></span>}
                    <span className="text-theme-tertiary">{new Date(c.created_at).toLocaleDateString()}</span>
                  </div>
                </div>
                {c.challenge_prompt && <p className="text-sm text-theme-secondary line-clamp-2">{c.challenge_prompt}</p>}
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
};

export const AgentDetailPage: React.FC = () => {
  const { agentId } = useParams<{ agentId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const { openConversationMaximized } = useChatWindow();
  const [agent, setAgent] = useState<AiAgent | null>(null);
  const [loading, setLoading] = useState(true);

  const getActiveTab = () => {
    if (location.pathname.includes('/intelligence')) return 'intelligence';
    if (location.pathname.includes('/connections')) return 'connections';
    if (location.pathname.includes('/knowledge')) return 'knowledge';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  useEffect(() => {
    if (!agentId) return;
    const load = async () => {
      try {
        setLoading(true);
        const data = await agentsApi.getAgent(agentId);
        setAgent(data);
      } catch (_err) {
        navigate('/app/ai/agents');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [agentId, navigate]);

  if (loading || !agent) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading agent..." />;
  }

  const statusVariant = agent.status === 'active' ? 'success' : agent.status === 'error' ? 'danger' : 'secondary';

  const pageActions = [
    {
      id: 'back',
      label: 'Back to Agents',
      onClick: () => navigate('/app/ai/agents/list'),
      variant: 'secondary' as const,
      icon: ArrowLeft,
    },
    {
      id: 'chat',
      label: 'Chat',
      onClick: () => openConversationMaximized(agent.id, agent.name),
      variant: 'outline' as const,
      icon: MessageSquare,
    },
    {
      id: 'memory',
      label: 'Memory',
      onClick: () => navigate(`/app/ai/agents/${agent.id}/memory`),
      variant: 'outline' as const,
      icon: Brain,
    },
  ];

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'Agents', href: '/app/ai/agents' },
      { label: agent.name },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title={agent.name}
      description={agent.description || 'AI Agent'}
      breadcrumbs={getBreadcrumbs()}
      actions={pageActions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath={`/app/ai/agents/${agentId}`}
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <Card className="p-6">
            <div className="flex items-start gap-4 mb-6">
              <div className="h-12 w-12 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
                <Bot className="h-6 w-6 text-theme-info" />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1">
                  <h2 className="text-xl font-semibold text-theme-primary">{agent.name}</h2>
                  <Badge variant={statusVariant} size="sm">{agent.status}</Badge>
                </div>
                {agent.description && (
                  <p className="text-sm text-theme-secondary">{agent.description}</p>
                )}
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Type</span>
                  <span className="text-theme-primary">{agent.agent_type || 'N/A'}</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Provider</span>
                  <span className="text-theme-primary">{agent.provider?.name || 'N/A'}</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Model</span>
                  <span className="text-theme-primary">{agent.model || 'N/A'}</span>
                </div>
              </div>

              <div className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Total Executions</span>
                  <span className="text-theme-primary">{agent.execution_stats?.total_executions || 0}</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Success Rate</span>
                  <span className="text-theme-primary">{agent.execution_stats?.success_rate || 0}%</span>
                </div>
                {agent.skill_slugs && agent.skill_slugs.length > 0 && (
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-tertiary">Skills</span>
                    <div className="flex flex-wrap gap-1 justify-end">
                      {agent.skill_slugs.map((slug) => (
                        <Badge key={slug} variant="info" size="sm">{slug}</Badge>
                      ))}
                    </div>
                  </div>
                )}
                {agent.skill_slugs && agent.skill_slugs.length > 0 && (
                  <div className="text-xs">
                    <button type="button" onClick={() => navigate('/app/ai/knowledge?tab=skill-graph')} className="text-theme-info hover:underline">
                      View skills in graph →
                    </button>
                  </div>
                )}
              </div>
            </div>
          </Card>
        </TabPanel>

        <TabPanel tabId="intelligence" activeTab={activeTab}>
          {agentId && <IntelligenceContent agentId={agentId} />}
        </TabPanel>

        <TabPanel tabId="connections" activeTab={activeTab}>
          {agentId && <AgentConnectionsGraph agentId={agentId} />}
        </TabPanel>

        <TabPanel tabId="knowledge" activeTab={activeTab}>
          {agentId && (
            <div className="space-y-4">
              <div className="flex items-center gap-2 mb-4">
                <BookOpen size={18} className="text-theme-secondary" />
                <h3 className="text-lg font-medium text-theme-primary">Agent Knowledge & Contexts</h3>
              </div>
              <ContextBrowser
                filters={{ ai_agent_id: agentId }}
                linkToDetail
              />
            </div>
          )}
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default AgentDetailPage;
