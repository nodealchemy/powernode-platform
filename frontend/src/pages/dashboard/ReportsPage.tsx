import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { reportsService } from '../../services/reportsService';
import { LoadingSpinner } from '../../components/common/LoadingSpinner';
import { DateRangeFilter } from '../../components/analytics/DateRangeFilter';

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
  const { user } = useSelector((state: RootState) => state.auth);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'templates' | 'requests' | 'scheduled'>('templates');
  
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

  const handleTemplateSelect = (template: ReportTemplate) => {
    setSelectedTemplate(template);
    setReportConfig({
      name: `${template.name} Report - ${new Date().toLocaleDateString()}`,
      format: template.formats[0] as 'csv' | 'pdf' | 'xlsx' | 'json',
      filters: {}
    });
    setShowRequestModal(true);
  };

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
    { id: 'templates', label: 'Report Templates', icon: '📋' },
    { id: 'requests', label: 'My Requests', icon: '📄' },
    { id: 'scheduled', label: 'Scheduled Reports', icon: '⏰' }
  ] as const;

  if (loading) {
    return <LoadingSpinner size="large" message="Loading reports..." />;
  }

  if (error) {
    return (
      <div className="min-h-screen bg-theme-background-secondary p-6">
        <div className="max-w-7xl mx-auto">
          <div className="bg-theme-error text-theme-error card-theme p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <span className="text-theme-error text-xl">⚠️</span>
              </div>
              <div className="ml-3">
                <h3 className="text-sm font-medium text-theme-error">Error Loading Reports</h3>
                <p className="mt-1 text-sm text-theme-error">{error}</p>
                <button
                  onClick={loadData}
                  className="mt-2 px-3 py-1 bg-theme-error text-white rounded text-sm hover:opacity-80"
                >
                  Try Again
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-theme-background-secondary">
      {/* Header */}
      <div className="card-theme shadow-sm border-b border-theme">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between py-4">
            <div>
              <h1 className="text-2xl font-bold text-theme-primary">Reports</h1>
              <p className="text-sm text-theme-secondary">
                Generate and manage business reports for {user?.account?.name || 'your account'}
              </p>
            </div>
          </div>

          {/* Navigation Tabs */}
          <div className="flex space-x-8 -mb-px">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm whitespace-nowrap ${
                  activeTab === tab.id
                    ? 'border-theme-link text-theme-link'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                }`}
              >
                <span>{tab.icon}</span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        {activeTab === 'templates' && (
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
                            <button
                              onClick={() => handleTemplateSelect(template)}
                              className="btn-theme btn-theme-primary text-xs px-3 py-1"
                            >
                              Generate
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

        {activeTab === 'requests' && (
          <div className="space-y-4">
            {requests.length === 0 ? (
              <div className="text-center py-12">
                <span className="text-6xl">📄</span>
                <h3 className="text-lg font-medium text-theme-primary mt-2">No report requests yet</h3>
                <p className="text-theme-secondary">Start by generating a report from the templates tab.</p>
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
                        request.status === 'completed' ? 'bg-green-100 text-green-700' :
                        request.status === 'processing' ? 'bg-blue-100 text-blue-700' :
                        request.status === 'failed' ? 'bg-red-100 text-red-700' :
                        'bg-gray-100 text-gray-700'
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
        )}

        {activeTab === 'scheduled' && (
          <div className="text-center py-12">
            <span className="text-6xl">⏰</span>
            <h3 className="text-lg font-medium text-theme-primary mt-2">Scheduled Reports Coming Soon</h3>
            <p className="text-theme-secondary">Set up automated report generation and delivery.</p>
          </div>
        )}
      </div>

      {/* Report Request Modal */}
      {showRequestModal && selectedTemplate && (
        <>
          <div className="fixed inset-0 bg-black bg-opacity-50 z-40" onClick={() => setShowRequestModal(false)} />
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
    </div>
  );
};