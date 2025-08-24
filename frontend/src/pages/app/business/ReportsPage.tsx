import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { useLocation, useNavigate } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { reportsService } from '@/features/reports/services/reportsService';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { DateRangeFilter } from '@/features/analytics/components/DateRangeFilter';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { RefreshCw } from 'lucide-react';
import { ReportsOverviewPage } from './ReportsOverviewPage';

export interface ReportRequest {
  id: string;
  name: string;
  type: string;
  format: 'csv' | 'pdf' | 'xlsx' | 'json';
  status: 'pending' | 'processing' | 'completed' | 'failed';
  requested_at: string;
  completed_at?: string;
  file_url?: string;
  parameters: {
    date_range: {
      start_date: string;
      end_date: string;
    };
    filters?: Record<string, any>;
  };
}

interface ReportTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  formats: string[];
  parameters: {
    requires_date_range: boolean;
    filters?: Array<{
      name: string;
      type: 'text' | 'select' | 'multi-select' | 'boolean';
      label: string;
      options?: string[];
      required?: boolean;
    }>;
  };
}

export const ReportsPage: React.FC = () => {
ReportsPage.displayName = 'ReportsPage';
  const { user } = useSelector((state: RootState) => state.auth);
  const location = useLocation();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [builderStep, setBuilderStep] = useState<1 | 2 | 3 | 4>(1);
  
  // Report data
  const [templates, setTemplates] = useState<ReportTemplate[]>([]);
  const [requests, setRequests] = useState<ReportRequest[]>([]);
  const [selectedTemplate, setSelectedTemplate] = useState<ReportTemplate | null>(null);
  
  // Report configuration
  const [dateRange, setDateRange] = useState<{
    startDate: Date;
    endDate: Date;
  }>({
    startDate: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000), // 30 days ago
    endDate: new Date()
  });
  
  const [reportConfig, setReportConfig] = useState<{
    name: string;
    format: 'csv' | 'pdf' | 'xlsx' | 'json';
    filters: Record<string, any>;
  }>({
    name: '',
    format: 'pdf',
    filters: {}
  });

  const [showRequestModal, setShowRequestModal] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Load initial data
  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      
      const [templatesResponse, requestsResponse] = await Promise.all([
        reportsService.getTemplates(),
        reportsService.getRequests()
      ]);
      
      setTemplates(templatesResponse.data);
      setRequests(requestsResponse.data);
    } catch (err) {
      console.error('Failed to load reports data:', err);
      setError(err instanceof Error ? err.message : 'Failed to load reports data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  // Auto-refresh requests
  useEffect(() => {
    const interval = setInterval(async () => {
      try {
        const response = await reportsService.getRequests();
        setRequests(response.data);
      } catch (error) {
        console.error('Failed to refresh requests:', error);
      }
    }, 10000); // Refresh every 10 seconds

    return () => clearInterval(interval);
  }, []);


  const handleSubmitRequest = async () => {
    if (!selectedTemplate) return;
    
    try {
      setIsSubmitting(true);
      
      const requestData = {
        template_id: selectedTemplate.id,
        name: reportConfig.name,
        format: reportConfig.format,
        parameters: {
          date_range: {
            start_date: dateRange.startDate.toISOString().split('T')[0],
            end_date: dateRange.endDate.toISOString().split('T')[0],
          },
          filters: reportConfig.filters
        }
      };

      await reportsService.requestReport(requestData);
      
      // Refresh requests list
      const response = await reportsService.getRequests();
      setRequests(response.data);
      
      setShowRequestModal(false);
      setSelectedTemplate(null);
      
    } catch (err) {
      console.error('Failed to submit report request:', err);
      setError(err instanceof Error ? err.message : 'Failed to submit report request');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDownloadReport = async (request: ReportRequest) => {
    if (!request.file_url) return;
    
    try {
      await reportsService.downloadReport(request.id);
    } catch (err) {
      console.error('Failed to download report:', err);
    }
  };

  const handleCancelRequest = async (requestId: string) => {
    try {
      await reportsService.cancelRequest(requestId);
      
      // Refresh requests list
      const response = await reportsService.getRequests();
      setRequests(response.data);
    } catch (err) {
      console.error('Failed to cancel request:', err);
    }
  };

  const categorizedTemplates = templates.reduce((acc, template) => {
    if (!acc[template.category]) {
      acc[template.category] = [];
    }
    acc[template.category].push(template);
    return acc;
  }, {} as Record<string, ReportTemplate[]>);

  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊', path: '/' },
    { id: 'library', label: 'Report Library', icon: '📚', path: '/library' },
    { id: 'builder', label: 'Report Builder', icon: '🏗️', path: '/builder' },
    { id: 'queue', label: 'Report Queue', icon: '📋', path: '/queue' },
    { id: 'scheduled', label: 'Scheduled Reports', icon: '⏰', path: '/scheduled' },
    { id: 'analytics', label: 'Analytics', icon: '📈', path: '/analytics' }
  ];

  // Get active tab from URL
  const getActiveTab = () => {
    const path = location.pathname;
    if (path === '/app/business/reports') return 'overview';
    if (path.includes('/library')) return 'library';
    if (path.includes('/builder')) return 'builder';
    if (path.includes('/queue')) return 'queue';
    if (path.includes('/scheduled')) return 'scheduled';
    if (path.includes('/analytics')) return 'analytics';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());
  
  // Update active tab when URL changes
  useEffect(() => {
    const newActiveTab = getActiveTab();
    if (newActiveTab !== activeTab) {
      setActiveTab(newActiveTab);
    }
  }, [location.pathname, activeTab]);

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadData,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    }
  ];

  // Dynamic breadcrumbs based on active tab
  const getBreadcrumbs = () => {
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'Business', href: '/app/business', icon: '💼' },
      { label: 'Reports', icon: '📄' }
    ];
    
    // Add active tab to breadcrumbs if not the default overview tab
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label,
        icon: activeTabInfo.icon
      });
    }
    
    return baseBreadcrumbs;
  };


  const getPageDescription = () => {
    if (loading) return "Loading reports...";
    if (error) return "Error loading reports";
    return `Generate and manage business reports for ${user?.account?.name || 'your account'}`;
  };

  const getPageActions = () => {
    if (error) {
      return [{
        id: 'retry',
        label: 'Try Again',
        onClick: loadData,
        variant: 'primary' as const
      }];
    }
    return pageActions;
  };

  return (
    <PageContainer
      title="Reports"
      description={getPageDescription()}
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {loading && (
        <LoadingSpinner size="lg" message="Loading reports..." />
      )}
      
      {error && (
        <div className="alert-theme alert-theme-error">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <span className="text-xl">⚠️</span>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium">Error Loading Reports</h3>
              <p className="mt-1 text-sm">{error}</p>
            </div>
          </div>
        </div>
      )}
      
      {!loading && !error && (
        <>
          <TabContainer
            tabs={tabs}
            activeTab={activeTab}
            onTabChange={setActiveTab}
            basePath="/app/business/reports"
            variant="underline"
            className="mb-6"
          >
            <TabPanel tabId="overview" activeTab={activeTab}>
              <ReportsOverviewPage />
            </TabPanel>

            <TabPanel tabId="builder" activeTab={activeTab}>
              <div className="space-y-6">
                {/* Builder Progress */}
                <div className="card-theme p-6">
              <div className="flex items-center justify-between mb-6">
                <h2 className="text-xl font-semibold text-theme-primary">Create Custom Report</h2>
                <div className="text-sm text-theme-secondary">Step {builderStep} of 4</div>
              </div>
              
              {/* Progress Bar */}
              <div className="w-full bg-theme-background-tertiary rounded-full h-2 mb-6">
                <div 
                  className="bg-theme-interactive-primary h-2 rounded-full transition-all duration-300"
                  style={{ width: `${(builderStep / 4) * 100}%` }}
                ></div>
              </div>
              
              {/* Step Content */}
              {builderStep === 1 && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-theme-primary">Select Report Type</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    {Object.entries(categorizedTemplates).map(([category, categoryTemplates]) => (
                      <div key={category} className="space-y-3">
                        <h4 className="font-medium text-theme-primary capitalize">{category}</h4>
                        {categoryTemplates.map((template) => (
                          <div 
                            key={template.id} 
                            className="p-4 border border-theme rounded-lg hover:bg-theme-surface cursor-pointer transition-colors"
                            onClick={() => {
                              setSelectedTemplate(template);
                              setBuilderStep(2);
                            }}>
                            <div className="flex items-center space-x-3">
                              <span className="text-xl">{template.icon}</span>
                              <div>
                                <div className="font-medium text-theme-primary">{template.name}</div>
                                <div className="text-sm text-theme-secondary">{template.description}</div>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    ))}
                  </div>
                </div>
              )}
              
              {builderStep === 2 && selectedTemplate && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-theme-primary">Configure Parameters</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">Report Name</label>
                      <input
                        type="text"
                        value={reportConfig.name}
                        onChange={(e) => setReportConfig(prev => ({ ...prev, name: e.target.value }))}
                        className="input-theme w-full"
                        placeholder="Enter report name"
                      />
                    </div>
                    {selectedTemplate.parameters.requires_date_range && (
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-2">Date Range</label>
                        <DateRangeFilter dateRange={dateRange} onChange={setDateRange} />
                      </div>
                    )}
                  </div>
                  {selectedTemplate.parameters.filters && (
                    <div className="space-y-4">
                      <h4 className="font-medium text-theme-primary">Filters</h4>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {selectedTemplate.parameters.filters.map((filter) => (
                          <div key={filter.name}>
                            <label className="block text-sm font-medium text-theme-primary mb-1">{filter.label}</label>
                            {filter.type === 'text' && (
                              <input type="text" className="input-theme w-full" />
                            )}
                            {filter.type === 'select' && filter.options && (
                              <select className="input-theme w-full">
                                <option value="">Select {filter.label}</option>
                                {filter.options.map((option) => (
                                  <option key={option} value={option}>{option}</option>
                                ))}
                              </select>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}
              
              {builderStep === 3 && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-theme-primary">Choose Format & Schedule</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">Output Format</label>
                      <div className="space-y-2">
                        {selectedTemplate?.formats.map((format) => (
                          <label key={format} className="flex items-center">
                            <input
                              type="radio"
                              name="format"
                              value={format}
                              checked={reportConfig.format === format}
                              onChange={(e) => setReportConfig(prev => ({ ...prev, format: e.target.value as any }))}
                              className="mr-2"
                            />
                            <span className="text-theme-primary">{format.toUpperCase()}</span>
                          </label>
                        ))}
                      </div>
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">Schedule</label>
                      <div className="space-y-2">
                        <label className="flex items-center">
                          <input type="radio" name="schedule" value="once" className="mr-2" defaultChecked />
                          <span className="text-theme-primary">Generate Once</span>
                        </label>
                        <label className="flex items-center">
                          <input type="radio" name="schedule" value="daily" className="mr-2" />
                          <span className="text-theme-primary">Daily</span>
                        </label>
                        <label className="flex items-center">
                          <input type="radio" name="schedule" value="weekly" className="mr-2" />
                          <span className="text-theme-primary">Weekly</span>
                        </label>
                        <label className="flex items-center">
                          <input type="radio" name="schedule" value="monthly" className="mr-2" />
                          <span className="text-theme-primary">Monthly</span>
                        </label>
                      </div>
                    </div>
                  </div>
                </div>
              )}
              
              {builderStep === 4 && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-theme-primary">Review & Generate</h3>
                  <div className="card-theme bg-theme-surface p-4">
                    <h4 className="font-medium text-theme-primary mb-3">Report Summary</h4>
                    <dl className="space-y-2 text-sm">
                      <div className="flex justify-between">
                        <dt className="text-theme-secondary">Template:</dt>
                        <dd className="text-theme-primary font-medium">{selectedTemplate?.name}</dd>
                      </div>
                      <div className="flex justify-between">
                        <dt className="text-theme-secondary">Name:</dt>
                        <dd className="text-theme-primary">{reportConfig.name}</dd>
                      </div>
                      <div className="flex justify-between">
                        <dt className="text-theme-secondary">Format:</dt>
                        <dd className="text-theme-primary">{reportConfig.format.toUpperCase()}</dd>
                      </div>
                      {selectedTemplate?.parameters.requires_date_range && (
                        <div className="flex justify-between">
                          <dt className="text-theme-secondary">Date Range:</dt>
                          <dd className="text-theme-primary">
                            {dateRange.startDate.toLocaleDateString()} - {dateRange.endDate.toLocaleDateString()}
                          </dd>
                        </div>
                      )}
                    </dl>
                  </div>
                </div>
              )}
              
              {/* Navigation */}
              <div className="flex items-center justify-between mt-8 pt-6 border-t border-theme">
                <button
                  onClick={() => setBuilderStep(Math.max(1, builderStep - 1) as 1 | 2 | 3 | 4)}
                  disabled={builderStep === 1}
                  className="btn-theme btn-theme-secondary disabled:opacity-50"
                >
                  &larr; Previous
                </button>
                
                {builderStep < 4 ? (
                  <button
                    onClick={() => setBuilderStep(Math.min(4, builderStep + 1) as 1 | 2 | 3 | 4)}
                    disabled={builderStep === 2 && !selectedTemplate}
                    className="btn-theme btn-theme-primary disabled:opacity-50"
                  >
                    Next &rarr;
                  </button>
                ) : (
                  <button
                    onClick={handleSubmitRequest}
                    disabled={isSubmitting || !reportConfig.name}
                    className="btn-theme btn-theme-primary disabled:opacity-50"
                  >
                    {isSubmitting ? 'Generating...' : 'Generate Report'}
                  </button>
                )}
                </div>
              </div>
              </div>
            </TabPanel>
        
            <TabPanel tabId="library" activeTab={activeTab}>
              <div className="space-y-6">
                {/* Search and Filters */}
                <div className="card-theme p-4">
                  <div className="flex flex-col sm:flex-row gap-4">
                    <div className="flex-1 relative">
                      <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <span className="text-theme-secondary text-sm w-4 h-4 flex items-center justify-center">🔍</span>
                      </div>
                      <input
                        type="text"
                        className="input-theme w-full pl-11"
                        placeholder="Search report templates..."
                      />
                    </div>
                    <select className="input-theme w-full sm:w-48">
                      <option value="">All Categories</option>
                      {Object.keys(categorizedTemplates).map((category) => (
                        <option key={category} value={category}>{category}</option>
                      ))}
                    </select>
                  </div>
                </div>
            
                {/* Template Grid */}
                <div className="space-y-6">
                  {Object.entries(categorizedTemplates).map(([category, categoryTemplates]) => (
                <div key={category}>
                  <h2 className="text-lg font-semibold text-theme-primary mb-4 capitalize">
                    {category} Reports
                  </h2>
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    {categoryTemplates.map((template) => (
                      <div key={template.id} className="card-theme p-4 hover:shadow-md transition-shadow">
                        <div className="flex items-start space-x-3">
                          <span className="text-2xl">{template.icon}</span>
                          <div className="flex-1">
                            <h3 className="font-medium text-theme-primary">{template.name}</h3>
                            <p className="text-sm text-theme-secondary mt-1">{template.description}</p>
                            <div className="flex items-center justify-between mt-3">
                              <div className="flex space-x-1">
                                {template.formats.map((format) => (
                                  <span
                                    key={format}
                                    className="px-2 py-1 text-xs bg-theme-background-tertiary text-theme-secondary rounded uppercase"
                                  >
                                    {format}
                                  </span>
                                ))}
                              </div>
                              <div className="flex space-x-2">
                                <button
                                  onClick={() => {
                                    setSelectedTemplate(template);
                                    navigate('/app/business/reports');
                                    setBuilderStep(2);
                                  }}className="btn-theme btn-theme-primary text-xs px-3 py-1"
                                >
                                  Use Template
                                </button>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
                  ))}
                </div>
              </div>
            </TabPanel>

            <TabPanel tabId="queue" activeTab={activeTab}>
              <div className="space-y-6">
                {requests.length === 0 ? (
                  <div className="text-center py-12">
                    <span className="text-6xl">📋</span>
                    <h3 className="text-lg font-medium text-theme-primary mt-2">No reports in queue</h3>
                    <p className="text-theme-secondary">Start by creating a report from the Builder or Library.</p>
                  </div>
                ) : (
                  requests.map((request) => (
                <div key={request.id} className="card-theme p-4">
                  <div className="flex items-center justify-between">
                    <div className="flex-1">
                      <h3 className="font-medium text-theme-primary">{request.name}</h3>
                      <div className="flex items-center space-x-4 text-sm text-theme-secondary mt-1">
                        <span>Type: {request.type}</span>
                        <span>Format: {request.format.toUpperCase()}</span>
                        <span>Requested: {new Date(request.requested_at).toLocaleDateString()}</span>
                      </div>
                    </div>
                    <div className="flex items-center space-x-3">
                      <span className={`px-2 py-1 text-xs rounded ${
                        request.status === 'completed' ? 'bg-theme-success text-theme-success' :
                        request.status === 'processing' ? 'bg-theme-info text-theme-info' :
                        request.status === 'failed' ? 'bg-theme-error text-theme-error' :
                        'bg-theme-background-secondary text-theme-secondary'
                      }`}>
                        {request.status.toUpperCase()}
                      </span>
                      {request.status === 'completed' && request.file_url && (
                        <button
                          onClick={() => handleDownloadReport(request)}
                          className="btn-theme btn-theme-primary text-xs px-3 py-1"
                        >
                          Download
                        </button>
                      )}
                      {request.status === 'pending' && (
                        <button
                          onClick={() => handleCancelRequest(request.id)}
                          className="btn-theme btn-theme-secondary text-xs px-3 py-1"
                        >
                          Cancel
                        </button>
                      )}
                    </div>
                  </div>
                </div>
                  ))
                )}
              </div>
            </TabPanel>

            <TabPanel tabId="scheduled" activeTab={activeTab}>
              <div className="space-y-6">
                {/* Create Schedule */}
                <div className="card-theme p-6">
                  <div className="flex items-center justify-between mb-6">
                <h2 className="text-xl font-semibold text-theme-primary">Scheduled Reports</h2>
                <button className="btn-theme btn-theme-primary">
                  + New Schedule
                </button>
              </div>
              
              {/* Example scheduled reports */}
              <div className="space-y-4">
                <div className="border border-theme rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div className="flex-1">
                      <h3 className="font-medium text-theme-primary">Monthly Revenue Report</h3>
                      <div className="flex items-center space-x-4 text-sm text-theme-secondary mt-1">
                        <span>Every 1st of month</span>
                        <span>PDF Format</span>
                        <span>Last run: 2 days ago</span>
                      </div>
                    </div>
                    <div className="flex items-center space-x-3">
                      <span className="px-2 py-1 text-xs rounded bg-theme-success text-theme-success">ACTIVE</span>
                      <button className="text-theme-secondary hover:text-theme-primary">Edit</button>
                      <button className="text-theme-secondary hover:text-theme-primary">Pause</button>
                    </div>
                  </div>
                </div>
                
                <div className="border border-theme rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div className="flex-1">
                      <h3 className="font-medium text-theme-primary">Weekly Customer Analytics</h3>
                      <div className="flex items-center space-x-4 text-sm text-theme-secondary mt-1">
                        <span>Every Monday</span>
                        <span>XLSX Format</span>
                        <span>Next run: in 3 days</span>
                      </div>
                    </div>
                    <div className="flex items-center space-x-3">
                      <span className="px-2 py-1 text-xs rounded bg-theme-warning text-theme-warning">PAUSED</span>
                      <button className="text-theme-secondary hover:text-theme-primary">Edit</button>
                      <button className="text-theme-secondary hover:text-theme-primary">Resume</button>
                    </div>
                  </div>
                </div>
                </div>
              </div>
            
              {/* Schedule Templates */}
              <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Common Schedules</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer">
                  <div className="text-2xl mb-2">📅</div>
                  <div className="font-medium text-theme-primary">Daily Reports</div>
                  <div className="text-sm text-theme-secondary">Daily operational metrics</div>
                </div>
                <div className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer">
                  <div className="text-2xl mb-2">📆</div>
                  <div className="font-medium text-theme-primary">Weekly Summary</div>
                  <div className="text-sm text-theme-secondary">Weekly performance overview</div>
                </div>
                <div className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer">
                  <div className="text-2xl mb-2">📊</div>
                  <div className="font-medium text-theme-primary">Monthly Analysis</div>
                  <div className="text-sm text-theme-secondary">Comprehensive monthly insights</div>
                </div>
                </div>
              </div>
              </div>
            </TabPanel>
            
            <TabPanel tabId="analytics" activeTab={activeTab}>
              <div className="space-y-6">
                {/* Usage Overview */}
                <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">47</div>
                <div className="text-sm text-theme-secondary">Reports Generated</div>
                <div className="text-xs text-theme-tertiary">This month</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">8</div>
                <div className="text-sm text-theme-secondary">Active Schedules</div>
                <div className="text-xs text-theme-tertiary">Running</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">23</div>
                <div className="text-sm text-theme-secondary">Templates Used</div>
                <div className="text-xs text-theme-tertiary">Total</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">2.1GB</div>
                <div className="text-sm text-theme-secondary">Data Generated</div>
                <div className="text-xs text-theme-tertiary">Total size</div>
              </div>
                </div>
            
                {/* Popular Templates */}
                <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Most Popular Templates</h3>
              <div className="space-y-3">
                {templates.slice(0, 5).map((template, index) => (
                  <div key={template.id} className="flex items-center justify-between py-2">
                    <div className="flex items-center space-x-3">
                      <span className="text-theme-secondary font-medium">{index + 1}</span>
                      <span className="text-lg">{template.icon}</span>
                      <span className="text-theme-primary">{template.name}</span>
                    </div>
                    <div className="text-sm text-theme-secondary">
                      {Math.floor(Math.random() * 50) + 10} uses
                    </div>
                  </div>
                ))}
              </div>
                </div>
            
                {/* Recent Activity */}
                <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Recent Activity</h3>
              <div className="space-y-3">
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-success rounded-full"></div>
                  <span className="text-theme-primary">Monthly Revenue Report completed</span>
                  <span className="text-sm text-theme-secondary">2 hours ago</span>
                </div>
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-info rounded-full"></div>
                  <span className="text-theme-primary">Customer Analytics scheduled</span>
                  <span className="text-sm text-theme-secondary">1 day ago</span>
                </div>
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-warning rounded-full"></div>
                  <span className="text-theme-primary">Subscription Report failed</span>
                  <span className="text-sm text-theme-secondary">2 days ago</span>
                </div>
              </div>
                </div>
              </div>
            </TabPanel>
          </TabContainer>
        </>
      )}

      {/* Report Request Modal */}
      {showRequestModal && selectedTemplate && (
        <>
          <div className="fixed inset-0 bg-theme-overlay z-40" onClick={() => setShowRequestModal(false)} />
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
            <div className="card-theme w-full max-w-lg max-h-screen overflow-y-auto">
              <div className="flex items-center justify-between p-6 border-b border-theme">
                <h2 className="text-lg font-semibold text-theme-primary">
                  Generate {selectedTemplate.name}
                </h2>
                <button
                  onClick={() => setShowRequestModal(false)}
                  className="text-theme-secondary hover:text-theme-primary"
                >
                  ✕
                </button>
              </div>

              <div className="p-6 space-y-4">
                {/* Report Name */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Report Name
                  </label>
                  <input
                    type="text"
                    value={reportConfig.name}
                    onChange={(e) => setReportConfig(prev => ({ ...prev, name: e.target.value }))}
                    className="input-theme w-full"
                    placeholder="Enter report name"
                  />
                </div>

                {/* Format Selection */}
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Format
                  </label>
                  <select
                    value={reportConfig.format}
                    onChange={(e) => setReportConfig(prev => ({ ...prev, format: e.target.value as any }))}
                    className="input-theme w-full"
                  >
                    {selectedTemplate.formats.map((format) => (
                      <option key={format} value={format}>
                        {format.toUpperCase()}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Date Range */}
                {selectedTemplate.parameters.requires_date_range && (
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      Date Range
                    </label>
                    <DateRangeFilter
                      dateRange={dateRange}
                      onChange={setDateRange}
                    />
                  </div>
                )}

                {/* Additional Filters */}
                {selectedTemplate.parameters.filters?.map((filter) => (
                  <div key={filter.name}>
                    <label className="block text-sm font-medium text-theme-primary mb-1">
                      {filter.label}
                    </label>
                    {filter.type === 'text' && (
                      <input
                        type="text"
                        className="input-theme w-full"
                        onChange={(e) => setReportConfig(prev => ({
                          ...prev,
                          filters: { ...prev.filters, [filter.name]: e.target.value }
                        }))}
                      />
                    )}
                    {filter.type === 'select' && filter.options && (
                      <select
                        className="input-theme w-full"
                        onChange={(e) => setReportConfig(prev => ({
                          ...prev,
                          filters: { ...prev.filters, [filter.name]: e.target.value }
                        }))}
                      >
                        <option value="">Select {filter.label}</option>
                        {filter.options.map((option) => (
                          <option key={option} value={option}>
                            {option}
                          </option>
                        ))}
                      </select>
                    )}
                    {filter.type === 'boolean' && (
                      <label className="flex items-center">
                        <input
                          type="checkbox"
                          className="mr-2"
                          onChange={(e) => setReportConfig(prev => ({
                            ...prev,
                            filters: { ...prev.filters, [filter.name]: e.target.checked }
                          }))}
                        />
                        {filter.label}
                      </label>
                    )}
                  </div>
                ))}
              </div>

              <div className="flex items-center justify-end space-x-3 p-6 border-t border-theme">
                <button
                  onClick={() => setShowRequestModal(false)}
                  className="btn-theme btn-theme-secondary"
                  disabled={isSubmitting}
                >
                  Cancel
                </button>
                <button
                  onClick={handleSubmitRequest}
                  className="btn-theme btn-theme-primary"
                  disabled={isSubmitting || !reportConfig.name}
                >
                  {isSubmitting ? 'Generating...' : 'Generate Report'}
                </button>
              </div>
            </div>
          </div>
        </>
      )}
    </PageContainer>
  );
};