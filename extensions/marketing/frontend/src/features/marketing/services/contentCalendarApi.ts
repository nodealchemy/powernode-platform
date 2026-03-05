import { apiClient } from '@/shared/services/apiClient';
import type {
  ContentCalendarEntry,
  CalendarEntryFormData,
  ContentStatus,
  CalendarEntryType,
  ApiResponse,
  Pagination,
} from '../types';

export const contentCalendarApi = {
  list: async (params?: {
    page?: number;
    per_page?: number;
    start_date?: string;
    end_date?: string;
    status?: ContentStatus;
    entry_type?: CalendarEntryType;
    campaign_id?: string;
  }): Promise<{ entries: ContentCalendarEntry[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      entries: ContentCalendarEntry[];
      pagination: Pagination;
    }>>('/marketing/calendar', { params });
    return response.data.data;
  },

  get: async (id: string): Promise<ContentCalendarEntry> => {
    const response = await apiClient.get<ApiResponse<{
      entry: ContentCalendarEntry;
    }>>(`/marketing/calendar/${id}`);
    return response.data.data.entry;
  },

  create: async (data: CalendarEntryFormData): Promise<ContentCalendarEntry> => {
    const response = await apiClient.post<ApiResponse<{
      entry: ContentCalendarEntry;
    }>>('/marketing/calendar', { calendar_entry: data });
    return response.data.data.entry;
  },

  update: async (id: string, data: Partial<CalendarEntryFormData>): Promise<ContentCalendarEntry> => {
    const response = await apiClient.patch<ApiResponse<{
      entry: ContentCalendarEntry;
    }>>(`/marketing/calendar/${id}`, { calendar_entry: data });
    return response.data.data.entry;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/marketing/calendar/${id}`);
  },

  conflicts: async (params: {
    scheduled_date: string;
    scheduled_time?: string;
    exclude_id?: string;
  }): Promise<ContentCalendarEntry[]> => {
    const response = await apiClient.get<ApiResponse<{
      conflicts: ContentCalendarEntry[];
    }>>('/marketing/calendar/conflicts', { params });
    return response.data.data.conflicts;
  },
};
