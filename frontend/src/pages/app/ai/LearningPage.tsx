import React, { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Lightbulb, BarChart3, Layers } from 'lucide-react';
import { type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { CompoundLearningContent } from '@/pages/app/ai/CompoundLearningPage';
import { RecommendationsContent } from '@/features/ai/learning/RecommendationsDashboard';
import { TrajectoryInsights } from '@/features/ai/learning/TrajectoryInsights';

// Knowledge › Learning (fc-43): everything the /ai/learning endpoint family
// serves, in one place — the compounding learnings themselves, and the
// improvement recommendations and trajectory insights mined from execution
// history. fc-26 had given the latter two their own "Learning Insights" page;
// fc-43 folded it in here so Learning has one home. All three read endpoints
// LearningController gates on ai.analytics.read.
const LEARNING_BASE_PATH = '/app/ai/knowledge/learning';

const tabs = [
  { id: 'compound', label: 'Compound Learning', icon: <Layers size={16} />, path: '/' },
  { id: 'recommendations', label: 'Recommendations', icon: <Lightbulb size={16} />, path: '/recommendations' },
  { id: 'insights', label: 'Insights', icon: <BarChart3 size={16} />, path: '/insights' },
];

interface LearningContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const LearningContent: React.FC<LearningContentProps> = ({ onActionsReady }) => {
  const location = useLocation();
  const segment = location.pathname.startsWith(LEARNING_BASE_PATH)
    ? location.pathname.slice(LEARNING_BASE_PATH.length).split('/')[1] || ''
    : '';
  const activeTab = tabs.find((t) => t.path === `/${segment}`)?.id ?? 'compound';

  // Only Compound Learning contributes page actions; don't leave its actions
  // showing over the other two.
  useEffect(() => {
    if (activeTab !== 'compound') onActionsReady?.([]);
  }, [activeTab, onActionsReady]);

  return (
    <TabContainer tabs={tabs} activeTab={activeTab} basePath="/app/ai/knowledge/learning" variant="pills" size="sm">
      <TabPanel tabId="compound" activeTab={activeTab}>
        <CompoundLearningContent onActionsReady={onActionsReady} />
      </TabPanel>
      <TabPanel tabId="recommendations" activeTab={activeTab}>
        <RecommendationsContent />
      </TabPanel>
      <TabPanel tabId="insights" activeTab={activeTab}>
        <TrajectoryInsights />
      </TabPanel>
    </TabContainer>
  );
};
