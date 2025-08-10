import { api } from './api';

export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error?: string;
}

export interface ReportTemplate {
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

export interface ReportRequest {
  id: string;
  name: string;
  type: string;
  format: 'csv' | 'pdf' | 'xlsx' | 'json';
  status: 'pending' | 'processing' | 'completed' | 'failed';
  requested_at: string;
  completed_at?: string;
  file_url?: string;
  file_size?: number;
  error_message?: string;
  parameters: {
    date_range: {
      start_date: string;
      end_date: string;
    };
    filters?: Record<string, any>;
  };
}

export interface ReportRequestParams {
  template_id: string;
  name: string;
  format: 'csv' | 'pdf' | 'xlsx' | 'json';
  parameters: {
    date_range: {
      start_date: string;
      end_date: string;
    };
    filters?: Record<string, any>;
  };
}

export interface ScheduledReport {
  id: string;
  name: string;
  template_id: string;
  frequency: 'daily' | 'weekly' | 'monthly' | 'quarterly';
  next_run: string;
  last_run?: string;
  enabled: boolean;
  delivery_method: 'email' | 'download';
  recipients?: string[];
  parameters: {
    date_range_type: 'last_30_days' | 'last_quarter' | 'last_month' | 'custom';
    filters?: Record<string, any>;
  };
  format: 'csv' | 'pdf' | 'xlsx' | 'json';
}

class ReportsService {
  
  async getTemplates(): Promise<ApiResponse<ReportTemplate[]>> {
    const response = await api.get('/reports/templates');
    return response.data;
  }

  async getRequests(page = 1, limit = 20): Promise<ApiResponse<ReportRequest[]>> {
    const params = new URLSearchParams({
      page: page.toString(),
      limit: limit.toString()
    });

    const response = await api.get(`/reports/requests?${params}`);
    return response.data;
  }

  async getRequest(requestId: string): Promise<ApiResponse<ReportRequest>> {
    const response = await api.get(`/reports/requests/${requestId}`);
    return response.data;
  }

  async requestReport(params: ReportRequestParams): Promise<ApiResponse<ReportRequest>> {
    const response = await api.post('/reports/requests', params);
    return response.data;
  }

  async cancelRequest(requestId: string): Promise<ApiResponse<{ success: boolean }>> {
    const response = await api.delete(`/reports/requests/${requestId}`);
    return response.data;
  }

  async downloadReport(requestId: string): Promise<void> {
    const response = await api.get(`/reports/requests/${requestId}/download`, {
      responseType: 'blob'
    });

    // Get filename from Content-Disposition header or generate one
    const contentDisposition = response.headers['content-disposition'];
    let filename = `report_${requestId}.pdf`; // default filename
    
    if (contentDisposition) {
      const filenameMatch = contentDisposition.match(/filename="?([^";]+)"?/);
      if (filenameMatch) {
        filename = filenameMatch[1];
      }
    }

    // Create and trigger download
    const blob = new Blob([response.data]);
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
  }

  async getScheduledReports(): Promise<ApiResponse<ScheduledReport[]>> {
    const response = await api.get('/reports/scheduled');
    return response.data;
  }

  async createScheduledReport(params: {
    name: string;
    template_id: string;
    frequency: 'daily' | 'weekly' | 'monthly' | 'quarterly';
    delivery_method: 'email' | 'download';
    recipients?: string[];
    parameters: {
      date_range_type: 'last_30_days' | 'last_quarter' | 'last_month' | 'custom';
      filters?: Record<string, any>;
    };
    format: 'csv' | 'pdf' | 'xlsx' | 'json';
  }): Promise<ApiResponse<ScheduledReport>> {
    const response = await api.post('/reports/scheduled', params);
    return response.data;
  }

  async updateScheduledReport(
    reportId: string, 
    params: Partial<ScheduledReport>
  ): Promise<ApiResponse<ScheduledReport>> {
    const response = await api.patch(`/reports/scheduled/${reportId}`, params);
    return response.data;
  }

  async deleteScheduledReport(reportId: string): Promise<ApiResponse<{ success: boolean }>> {
    const response = await api.delete(`/reports/scheduled/${reportId}`);
    return response.data;
  }

  async toggleScheduledReport(reportId: string, enabled: boolean): Promise<ApiResponse<ScheduledReport>> {
    const response = await api.patch(`/reports/scheduled/${reportId}`, { enabled });
    return response.data;
  }

  // Report status polling for real-time updates
  pollRequestStatus(requestId: string, callback: (request: ReportRequest) => void): () => void {
    const intervalId = setInterval(async () => {
      try {
        const response = await this.getRequest(requestId);
        const request = response.data;
        callback(request);
        
        // Stop polling if request is completed or failed
        if (request.status === 'completed' || request.status === 'failed') {
          clearInterval(intervalId);
        }
      } catch (error) {
        console.error('Failed to poll request status:', error);
        clearInterval(intervalId);
      }
    }, 2000); // Poll every 2 seconds

    // Return cleanup function
    return () => clearInterval(intervalId);
  }

  // Legacy analytics export for backward compatibility
  async exportAnalytics(
    format: 'csv' | 'pdf',
    reportType: string,
    dateRange: { startDate: Date; endDate: Date },
    accountId?: string
  ): Promise<void> {
    // Convert to new report request format
    const templateId = this.mapLegacyReportTypeToTemplate(reportType);
    
    const params: ReportRequestParams = {
      template_id: templateId,
      name: `${reportType} Analytics Export - ${new Date().toLocaleDateString()}`,
      format,
      parameters: {
        date_range: {
          start_date: dateRange.startDate.toISOString().split('T')[0],
          end_date: dateRange.endDate.toISOString().split('T')[0]
        },
        filters: accountId ? { account_id: accountId } : {}
      }
    };

    // For immediate exports, we can use the legacy endpoint or create a request and wait
    const response = await api.get('/analytics/export', {
      params: {
        format,
        report_type: reportType,
        start_date: dateRange.startDate.toISOString().split('T')[0],
        end_date: dateRange.endDate.toISOString().split('T')[0],
        ...(accountId && { account_id: accountId })
      },
      responseType: 'blob'
    });

    // Create and trigger download
    const blob = new Blob([response.data]);
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${reportType}_analytics_${new Date().toISOString().split('T')[0]}.${format}`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
  }

  private mapLegacyReportTypeToTemplate(reportType: string): string {
    const mapping: Record<string, string> = {
      'revenue': 'revenue_analytics',
      'growth': 'growth_analytics',
      'churn': 'churn_analysis',
      'customers': 'customer_analytics',
      'cohorts': 'cohort_analysis',
      'all': 'comprehensive_report'
    };
    
    // eslint-disable-next-line security/detect-object-injection
    return mapping[reportType] || 'comprehensive_report';
  }
}

export const reportsService = new ReportsService();