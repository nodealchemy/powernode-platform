import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { EvalResultsViewer } from '../components/EvalResultsViewer';
import { BenchmarkBuilder } from '../components/BenchmarkBuilder';
import { EvalComparison } from '../components/EvalComparison';

type TabType = 'results' | 'benchmarks' | 'comparison';

// Nested under ObservabilityPage's "evaluation" tab (routed as `evaluation/*`
// so paths beneath it aren't caught by ObservabilityPage's own catch-all).
const EVALUATION_BASE_PATH = '/app/ai/observability/evaluation';

const evalTabs: { id: TabType; label: string; path: string }[] = [
  { id: 'results', label: 'Evaluation Results', path: '/' },
  { id: 'benchmarks', label: 'Benchmarks', path: '/benchmarks' },
  { id: 'comparison', label: 'Agent Comparison', path: '/comparison' },
];

const getActiveEvalTab = (pathname: string): TabType => {
  if (pathname.includes('/evaluation/benchmarks')) return 'benchmarks';
  if (pathname.includes('/evaluation/comparison')) return 'comparison';
  return 'results';
};

export const EvaluationContent: React.FC = () => {
  const location = useLocation();
  const [activeTab, setActiveTab] = useState<TabType>(getActiveEvalTab(location.pathname));

  useEffect(() => {
    const newTab = getActiveEvalTab(location.pathname);
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  return (
    <div className="space-y-6">
      <TabContainer
        tabs={evalTabs}
        activeTab={activeTab}
        onTabChange={(id) => setActiveTab(id as TabType)}
        basePath={EVALUATION_BASE_PATH}
        variant="underline"
      >
        <TabPanel tabId="results" activeTab={activeTab}>
          <EvalResultsViewer />
        </TabPanel>
        <TabPanel tabId="benchmarks" activeTab={activeTab}>
          <BenchmarkBuilder />
        </TabPanel>
        <TabPanel tabId="comparison" activeTab={activeTab}>
          <EvalComparison />
        </TabPanel>
      </TabContainer>
    </div>
  );
};

export const EvaluationDashboardPage: React.FC = () => (
  <PageContainer
    title="Agent Evaluation"
    description="Evaluate agent quality, manage benchmarks, and compare performance"
  >
    <EvaluationContent />
  </PageContainer>
);
