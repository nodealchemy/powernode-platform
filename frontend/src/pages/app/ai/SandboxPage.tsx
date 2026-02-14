// Sandbox Page - Enterprise AI Agent Testing Infrastructure
import React, { useState, useEffect } from 'react';
import { Plus, TestTube, Play, Search, Filter, Beaker, FlaskConical, BarChart3 } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import {
  sandboxApi,
  Sandbox,
  TestScenario,
  TestRun,
  PerformanceBenchmark,
  AbTest
} from '@/shared/services/ai/SandboxApiService';

// Type guard for API errors
interface ApiErrorResponse {
  response?: {
    data?: {
      error?: string;
    };
  };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) {
    return error.response?.data?.error || fallback;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}

type TabType = 'sandboxes' | 'scenarios' | 'mocks' | 'runs' | 'benchmarks' | 'ab-tests';

const SandboxPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('sandboxes');
  const [sandboxes, setSandboxes] = useState<Sandbox[]>([]);
  const [selectedSandbox, setSelectedSandbox] = useState<Sandbox | null>(null);
  const [scenarios, setScenarios] = useState<TestScenario[]>([]);
  const [runs, setRuns] = useState<TestRun[]>([]);
  const [benchmarks, setBenchmarks] = useState<PerformanceBenchmark[]>([]);
  const [abTests, setAbTests] = useState<AbTest[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');

  // WebSocket for real-time sandbox and workflow updates
  useAiOrchestrationWebSocket({
    onWorkflowRunEvent: (event) => {
      // Refresh sandbox data when workflow runs complete (test runs)
      if (['run_completed', 'run_failed'].includes(event.type)) {
        if (selectedSandbox) {
          loadSandboxData(selectedSandbox.id);
        }
      }
    },
    onBatchEvent: (event) => {
      // Refresh sandbox data when batch test executions complete
      if (['batch_completed', 'batch_failed', 'batch_progress_update'].includes(event.type)) {
        if (selectedSandbox) {
          loadSandboxData(selectedSandbox.id);
        }
      }
    },
  });

  useEffect(() => {
    loadData();
  }, []);

  useEffect(() => {
    if (selectedSandbox) {
      loadSandboxData(selectedSandbox.id);
    }
  }, [selectedSandbox]);

  const loadData = async () => {
    try {
      setLoading(true);
      const [sandboxesRes, abTestsRes] = await Promise.all([
        sandboxApi.getSandboxes(),
        sandboxApi.getAbTests()
      ]);
      setSandboxes(sandboxesRes.items || []);
      setAbTests(abTestsRes.items || []);

      // Auto-select first sandbox if available
      if (sandboxesRes.items && sandboxesRes.items.length > 0 && !selectedSandbox) {
        setSelectedSandbox(sandboxesRes.items[0]);
      }
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load sandbox data')
      }));
    } finally {
      setLoading(false);
    }
  };

  const loadSandboxData = async (sandboxId: string) => {
    try {
      const [scenariosRes, runsRes, benchmarksRes] = await Promise.all([
        sandboxApi.getScenarios(sandboxId),
        sandboxApi.getRuns(sandboxId),
        sandboxApi.getBenchmarks(sandboxId)
      ]);
      setScenarios(scenariosRes.items || []);
      setRuns(runsRes.items || []);
      setBenchmarks(benchmarksRes.items || []);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load sandbox details')
      }));
    }
  };

  const handleCreateSandbox = async () => {
    try {
      const result = await sandboxApi.createSandbox({
        name: `Sandbox ${sandboxes.length + 1}`,
        sandbox_type: 'standard'
      });
      dispatch(addNotification({
        type: 'success',
        message: 'Sandbox created successfully'
      }));
      setSandboxes([...sandboxes, result.sandbox]);
      setSelectedSandbox(result.sandbox);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to create sandbox')
      }));
    }
  };

  const handleRunTests = async () => {
    if (!selectedSandbox) return;

    try {
      const result = await sandboxApi.createRun(selectedSandbox.id, {
        run_type: 'manual'
      });
      dispatch(addNotification({
        type: 'success',
        message: 'Test run started'
      }));
      setRuns([result.run, ...runs]);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to start test run')
      }));
    }
  };

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'active': return 'text-theme-success bg-theme-success/10';
      case 'inactive': return 'text-theme-secondary bg-theme-surface';
      case 'paused': return 'text-theme-warning bg-theme-warning/10';
      case 'completed': return 'text-theme-success bg-theme-success/10';
      case 'running': return 'text-theme-info bg-theme-info/10';
      case 'failed': return 'text-theme-danger bg-theme-danger/10';
      case 'passed': return 'text-theme-success bg-theme-success/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: loadData,
    loading,
  });

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Sandbox' }
  ];

  const tabs = [
    { id: 'sandboxes' as TabType, label: 'Sandboxes', icon: Beaker },
    { id: 'scenarios' as TabType, label: 'Test Scenarios', icon: TestTube },
    { id: 'mocks' as TabType, label: 'Mock Responses', icon: FlaskConical },
    { id: 'runs' as TabType, label: 'Test Runs', icon: Play },
    { id: 'benchmarks' as TabType, label: 'Benchmarks', icon: BarChart3 },
    { id: 'ab-tests' as TabType, label: 'A/B Tests', icon: TestTube }
  ];

  return (
    <PageContainer
      title="AI Sandbox & Testing"
      description="Isolated testing environments for AI agents with recording, playback, and performance profiling"
      breadcrumbs={breadcrumbs}
      actions={[
        refreshAction,
        {
          id: 'run-tests',
          label: 'Run Tests',
          onClick: handleRunTests,
          icon: Play,
          variant: 'secondary' as const,
          disabled: !selectedSandbox
        },
        {
          id: 'create-sandbox',
          label: 'Create Sandbox',
          onClick: handleCreateSandbox,
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      {/* Sandbox Selector */}
      {sandboxes.length > 0 && (
        <div className="flex items-center gap-4 mb-6 p-4 bg-theme-surface border border-theme rounded-lg">
          <label className="text-sm font-medium text-theme-primary">Active Sandbox:</label>
          <select
            value={selectedSandbox?.id || ''}
            onChange={(e) => {
              const sandbox = sandboxes.find(s => s.id === e.target.value);
              setSelectedSandbox(sandbox || null);
            }}
            className="flex-1 max-w-md px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            {sandboxes.map(sandbox => (
              <option key={sandbox.id} value={sandbox.id}>
                {sandbox.name} ({sandbox.sandbox_type}) - {sandbox.status}
              </option>
            ))}
          </select>
          {selectedSandbox && (
            <div className="flex gap-4 text-sm text-theme-secondary">
              <span>{selectedSandbox.test_runs_count} runs</span>
              <span>{selectedSandbox.total_executions} executions</span>
            </div>
          )}
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex gap-4">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2 border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-accent text-theme-accent'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon size={16} />
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-4 mb-6">
        <div className="flex-1 min-w-64">
          <div className="relative">
            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-secondary" />
            <input
              type="search"
              placeholder="Search..."
              className="w-full pl-10 pr-4 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Filter size={16} className="text-theme-secondary" />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="all">All Status</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
            <option value="paused">Paused</option>
          </select>
        </div>
        <div className="flex items-center gap-2">
          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="all">All Types</option>
            <option value="unit">Unit</option>
            <option value="integration">Integration</option>
            <option value="regression">Regression</option>
            <option value="performance">Performance</option>
          </select>
        </div>
      </div>

      {/* Tab Content */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading sandbox data...</p>
        </div>
      ) : (
        <>
          {/* Sandboxes Tab */}
          {activeTab === 'sandboxes' && (
            <div className="space-y-4">
              {sandboxes.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Beaker size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No sandboxes</h3>
                  <p className="text-theme-secondary mb-6">Create a sandbox to start testing AI agents</p>
                  <button
                    onClick={handleCreateSandbox}
                    className="btn-theme btn-theme-primary"
                  >
                    Create Sandbox
                  </button>
                </div>
              ) : (
                <div data-testid="sandbox-grid" className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {sandboxes.map(sandbox => (
                    <div
                      key={sandbox.id}
                      data-testid="sandbox-card"
                      data-selected={selectedSandbox?.id === sandbox.id}
                      onClick={() => setSelectedSandbox(sandbox)}
                      className={`bg-theme-surface border rounded-lg p-4 cursor-pointer transition-colors ${
                        selectedSandbox?.id === sandbox.id ? 'border-theme-accent' : 'border-theme hover:border-theme-accent/50'
                      }`}
                    >
                      <div className="flex items-center justify-between mb-2">
                        <h3 className="font-medium text-theme-primary">{sandbox.name}</h3>
                        <span data-testid="sandbox-status-badge" className={`px-2 py-1 text-xs rounded ${getStatusColor(sandbox.status)}`}>
                          {sandbox.status}
                        </span>
                      </div>
                      <p className="text-sm text-theme-secondary mb-3">{sandbox.description || 'No description'}</p>
                      <div className="flex gap-4 text-xs text-theme-secondary">
                        <span>{sandbox.sandbox_type}</span>
                        <span>{sandbox.test_runs_count} runs</span>
                        <span>{sandbox.total_executions} executions</span>
                      </div>
                      {sandbox.recording_enabled && (
                        <span className="inline-block mt-2 px-2 py-1 text-xs bg-theme-danger/10 text-theme-danger rounded">Recording</span>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Scenarios Tab */}
          {activeTab === 'scenarios' && (
            <div className="space-y-4">
              {!selectedSandbox ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a sandbox to view scenarios</p>
                </div>
              ) : scenarios.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <TestTube size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No test scenarios</h3>
                  <p className="text-theme-secondary mb-6">Create test scenarios for your AI workflows</p>
                  <button className="btn-theme btn-theme-primary">
                    Create Scenario
                  </button>
                </div>
              ) : (
                scenarios.map(scenario => (
                  <div key={scenario.id} data-testid="scenario-card" className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{scenario.name}</h3>
                        <span data-testid="scenario-status-badge" className={`px-2 py-1 text-xs rounded ${getStatusColor(scenario.status)}`}>
                          {scenario.status}
                        </span>
                        <span data-testid="scenario-type-badge" className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">
                          {scenario.scenario_type}
                        </span>
                      </div>
                      <span className="text-sm text-theme-secondary">
                        {scenario.pass_rate !== null ? `${(scenario.pass_rate * 100).toFixed(1)}% pass rate` : 'No runs'}
                      </span>
                    </div>
                    <p className="text-sm text-theme-secondary mb-2">{scenario.description}</p>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      <span>{scenario.run_count} runs</span>
                      <span className="text-theme-success">{scenario.pass_count} passed</span>
                      <span className="text-theme-danger">{scenario.fail_count} failed</span>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Mocks Tab */}
          {activeTab === 'mocks' && (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <FlaskConical size={48} className="mx-auto text-theme-secondary mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">Mock Responses</h3>
              <p className="text-theme-secondary mb-6">Configure mock AI provider responses for testing</p>
              <button className="btn-theme btn-theme-primary">
                Create Mock
              </button>
            </div>
          )}

          {/* Runs Tab */}
          {activeTab === 'runs' && (
            <div className="space-y-4">
              {!selectedSandbox ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a sandbox to view test runs</p>
                </div>
              ) : runs.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Play size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No test runs</h3>
                  <p className="text-theme-secondary mb-6">Run tests to see results here</p>
                  <button
                    onClick={handleRunTests}
                    className="btn-theme btn-theme-primary"
                  >
                    Run Tests
                  </button>
                </div>
              ) : (
                runs.map(run => (
                  <div key={run.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <span className="font-mono text-sm text-theme-primary">{run.run_id}</span>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(run.status)}`}>
                          {run.status}
                        </span>
                        <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">
                          {run.run_type}
                        </span>
                      </div>
                      <span className="text-sm font-medium text-theme-primary">
                        {run.pass_rate.toFixed(1)}% pass rate
                      </span>
                    </div>
                    <div className="flex gap-4 text-sm text-theme-secondary">
                      <span>{run.total_scenarios} scenarios</span>
                      <span className="text-theme-success">{run.passed_scenarios} passed</span>
                      <span className="text-theme-danger">{run.failed_scenarios} failed</span>
                      {run.duration_ms && <span>{(run.duration_ms / 1000).toFixed(2)}s</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Benchmarks Tab */}
          {activeTab === 'benchmarks' && (
            <div className="space-y-4">
              {!selectedSandbox ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a sandbox to view benchmarks</p>
                </div>
              ) : benchmarks.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <BarChart3 size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No benchmarks</h3>
                  <p className="text-theme-secondary mb-6">Create performance benchmarks for your AI workflows</p>
                  <button className="btn-theme btn-theme-primary">
                    Create Benchmark
                  </button>
                </div>
              ) : (
                benchmarks.map(benchmark => (
                  <div key={benchmark.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <h3 className="font-medium text-theme-primary">{benchmark.name}</h3>
                      <div className="flex items-center gap-2">
                        {benchmark.trend && (
                          <span className={`px-2 py-1 text-xs rounded ${
                            benchmark.trend === 'improving' ? 'text-theme-success bg-theme-success/10' :
                            benchmark.trend === 'degrading' ? 'text-theme-danger bg-theme-danger/10' :
                            'text-theme-secondary bg-theme-surface'
                          }`}>
                            {benchmark.trend}
                          </span>
                        )}
                        {benchmark.latest_score !== null && (
                          <span className="text-lg font-bold text-theme-accent">{benchmark.latest_score}</span>
                        )}
                      </div>
                    </div>
                    <p className="text-sm text-theme-secondary">{benchmark.description}</p>
                    <div className="flex gap-4 text-xs text-theme-secondary mt-2">
                      <span>{benchmark.run_count} runs</span>
                      <span>Sample size: {benchmark.sample_size}</span>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* A/B Tests Tab */}
          {activeTab === 'ab-tests' && (
            <div className="space-y-4">
              {abTests.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <TestTube size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No A/B tests</h3>
                  <p className="text-theme-secondary mb-6">Create A/B tests to compare AI model variants</p>
                  <button className="btn-theme btn-theme-primary">
                    Create A/B Test
                  </button>
                </div>
              ) : (
                abTests.map(test => (
                  <div key={test.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{test.name}</h3>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(test.status)}`}>
                          {test.status}
                        </span>
                      </div>
                      {test.winning_variant && (
                        <span className="text-sm font-medium text-theme-success">
                          Winner: {test.winning_variant}
                        </span>
                      )}
                    </div>
                    <p className="text-sm text-theme-secondary mb-2">{test.description}</p>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      <span>{test.target_type}</span>
                      <span>{test.total_impressions} impressions</span>
                      <span>{test.total_conversions} conversions</span>
                      {test.statistical_significance !== null && (
                        <span>{(test.statistical_significance * 100).toFixed(1)}% significance</span>
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </>
      )}
    </PageContainer>
  );
};

export default SandboxPage;
