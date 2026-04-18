import React, { useState, useEffect } from 'react';
import { Calendar, RefreshCw } from 'lucide-react';
import { api } from '@/shared/services/api';
import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';
import { logger } from '@/shared/utils/logger';

interface DailySummary {
  id: string;
  title: string;
  slug: string;
  date: string;
  content?: string;
  published_at: string;
  word_count: number;
  estimated_read_time: number;
  created_at: string;
}

interface DailySummariesPanelProps {
  className?: string;
}

export const DailySummariesPanel: React.FC<DailySummariesPanelProps> = ({ className = '' }) => {
  const [summaries, setSummaries] = useState<DailySummary[]>([]);
  const [selectedSummary, setSelectedSummary] = useState<DailySummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);

  const fetchSummaries = async () => {
    try {
      setLoading(true);
      const response = await api.get('/admin/daily_summaries');
      setSummaries(response.data.data?.summaries || []);
    } catch {
      logger.warn('[DailySummariesPanel] Failed to fetch summaries');
    } finally {
      setLoading(false);
    }
  };

  const fetchLatest = async () => {
    try {
      const response = await api.get('/admin/daily_summaries/latest');
      const summary = response.data.data?.summary;
      if (summary) {
        setSelectedSummary(summary);
      }
    } catch {
      logger.warn('[DailySummariesPanel] Failed to fetch latest summary');
    }
  };

  const handleGenerate = async () => {
    try {
      setGenerating(true);
      const response = await api.post('/admin/daily_summaries/generate');
      const summary = response.data.data?.summary;
      if (summary) {
        setSelectedSummary(summary);
        await fetchSummaries();
      }
    } catch {
      logger.warn('[DailySummariesPanel] Failed to generate summary');
    } finally {
      setGenerating(false);
    }
  };

  const handleSelectSummary = async (summary: DailySummary) => {
    if (summary.content) {
      setSelectedSummary(summary);
      return;
    }
    // Fetch full content
    try {
      const response = await api.get(`/admin/pages/${summary.id}`);
      const page = response.data.data;
      setSelectedSummary({ ...summary, content: page?.content || '' });
    } catch {
      logger.warn('[DailySummariesPanel] Failed to fetch summary content');
    }
  };

  useEffect(() => {
    fetchSummaries();
    fetchLatest();
  }, []);

  if (loading) {
    return (
      <div className={`flex items-center justify-center py-12 ${className}`}>
        <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-link border-t-transparent" />
      </div>
    );
  }

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-theme-primary">Daily Summaries</h2>
          <p className="text-sm text-theme-secondary mt-1">
            Auto-generated operational summaries
          </p>
        </div>
        <button
          onClick={handleGenerate}
          disabled={generating}
          className="btn-theme btn-theme-secondary flex items-center gap-2"
        >
          <RefreshCw className={`w-4 h-4 ${generating ? 'animate-spin' : ''}`} />
          {generating ? 'Generating...' : 'Generate Now'}
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
        {/* Timeline sidebar */}
        <div className="lg:col-span-1">
          <div className="card-theme p-4">
            <h3 className="text-sm font-medium text-theme-secondary mb-3 uppercase tracking-wider">
              History
            </h3>
            {summaries.length > 0 ? (
              <ul className="space-y-1">
                {summaries.map((s) => (
                  <li key={s.id}>
                    <button
                      onClick={() => handleSelectSummary(s)}
                      className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center gap-2 ${
                        selectedSummary?.id === s.id
                          ? 'bg-theme-surface text-theme-link font-medium'
                          : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-background-secondary'
                      }`}
                    >
                      <Calendar className="w-3.5 h-3.5 shrink-0" />
                      <span>{s.date}</span>
                    </button>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-theme-tertiary italic">
                No summaries yet. Click &ldquo;Generate Now&rdquo; to create one.
              </p>
            )}
          </div>
        </div>

        {/* Content area */}
        <div className="lg:col-span-3">
          {selectedSummary?.content ? (
            <div className="card-theme p-6">
              <MarkdownRenderer
                content={selectedSummary.content}
                variant="admin"
                enableAdvancedFeatures
              />
            </div>
          ) : (
            <div className="card-theme p-12 text-center">
              <Calendar className="w-12 h-12 mx-auto mb-3 text-theme-tertiary opacity-30" />
              <p className="text-theme-secondary">
                {summaries.length > 0
                  ? 'Select a summary from the timeline to view it.'
                  : 'No summaries available. Generate your first one.'}
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
