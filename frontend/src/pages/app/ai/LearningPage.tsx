import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Lightbulb, BarChart3 } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { RecommendationsContent } from '@/features/ai/learning/RecommendationsDashboard';
import { TrajectoryInsights } from '@/features/ai/learning/TrajectoryInsights';

// fc-26: /app/ai/learning/recommendations and /app/ai/learning/insights were
// each their own standalone route with no nav entry and no in-app link —
// reachable only by typing the URL. Folded into one hub page (same
// basePath+tabs convention as DockerHubPage/SwarmHubPage/AIAgentsPage) so
// each is a click away from the other, rather than deleting either — both
// render real data off the `/ai/learning/*` API.
const tabs = [
  { id: 'recommendations', label: 'Recommendations', icon: <Lightbulb size={16} />, path: '/recommendations' },
  { id: 'insights', label: 'Insights', icon: <BarChart3 size={16} />, path: '/insights' },
];

export const LearningPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => (location.pathname.includes('/learning/insights') ? 'insights' : 'recommendations');

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    const activeTabInfo = tabs.find((t) => t.id === activeTab);
    base.push({ label: 'Learning' });
    if (activeTabInfo) base.push({ label: activeTabInfo.label });
    return base;
  };

  return (
    <PageContainer
      title="Learning"
      description="Improvement recommendations and trajectory insights from agent execution history"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/learning"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="recommendations" activeTab={activeTab}>
          <RecommendationsContent />
        </TabPanel>
        <TabPanel tabId="insights" activeTab={activeTab}>
          <TrajectoryInsights />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default LearningPage;
