import React, { useState } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { EvalResultsViewer } from '../components/EvalResultsViewer';
import { BenchmarkBuilder } from '../components/BenchmarkBuilder';
import { EvalComparison } from '../components/EvalComparison';

type TabType = 'results' | 'benchmarks' | 'comparison';

export const EvaluationDashboardPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState<TabType>('results');

  const tabs: { id: TabType; label: string }[] = [
    { id: 'results', label: 'Evaluation Results' },
    { id: 'benchmarks', label: 'Benchmarks' },
    { id: 'comparison', label: 'Agent Comparison' },
  ];

  return (
    <PageContainer
      title="Agent Evaluation"
      description="Evaluate agent quality, manage benchmarks, and compare performance"
    >
      <div className="space-y-6">
        <div className="flex gap-1 border-b border-theme-border">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-primary text-theme-primary'
                  : 'border-transparent text-theme-muted hover:text-theme-secondary'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {activeTab === 'results' && <EvalResultsViewer />}
        {activeTab === 'benchmarks' && <BenchmarkBuilder />}
        {activeTab === 'comparison' && <EvalComparison />}
      </div>
    </PageContainer>
  );
};
