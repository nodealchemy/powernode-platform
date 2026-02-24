import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowLeft,
  Calendar,
  BarChart3,
  FileText,
  Eye,
  MousePointerClick,
  ArrowRightLeft,
  DollarSign,
} from 'lucide-react';
import { useCampaign } from '../hooks/useCampaigns';
import { useCampaignContents } from '../hooks/useCampaignContents';
import { useCampaignMetrics } from '../hooks/useCampaignAnalytics';
import { CampaignStatusBadge } from './CampaignStatusBadge';
import { CampaignContentEditor } from './CampaignContentEditor';
import { CampaignContentPreview } from './CampaignContentPreview';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { CampaignContent } from '../types';

interface CampaignDetailProps {
  campaignId: string;
}

type Tab = 'content' | 'metrics' | 'calendar';

export const CampaignDetail: React.FC<CampaignDetailProps> = ({ campaignId }) => {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<Tab>('content');
  const [selectedContent, setSelectedContent] = useState<CampaignContent | null>(null);
  const [showEditor, setShowEditor] = useState(false);

  const { campaign, loading, error } = useCampaign(campaignId);
  const { contents, refresh: refreshContents } = useCampaignContents({ campaignId });
  const { metrics } = useCampaignMetrics(campaignId);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner />
      </div>
    );
  }

  if (error || !campaign) {
    return (
      <div className="card-theme p-6 text-center">
        <p className="text-theme-error">{error || 'Campaign not found'}</p>
        <button onClick={() => navigate('/app/marketing/campaigns')} className="btn-theme btn-theme-secondary mt-4">
          Back to Campaigns
        </button>
      </div>
    );
  }

  const formatCurrency = (cents: number): string => {
    return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2 })}`;
  };

  const tabs: { id: Tab; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
    { id: 'content', label: 'Content', icon: FileText },
    { id: 'metrics', label: 'Metrics', icon: BarChart3 },
    { id: 'calendar', label: 'Schedule', icon: Calendar },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <button
          onClick={() => navigate('/app/marketing/campaigns')}
          className="p-2 rounded-lg hover:bg-theme-surface-hover text-theme-secondary"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <h2 className="text-xl font-semibold text-theme-primary">{campaign.name}</h2>
            <CampaignStatusBadge status={campaign.status} />
          </div>
          <p className="text-sm text-theme-secondary mt-1">{campaign.description}</p>
        </div>
      </div>

      {/* Metrics Overview */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="card-theme p-4">
          <Eye className="w-5 h-5 text-theme-info mb-2" />
          <p className="text-xs text-theme-secondary">Impressions</p>
          <p className="text-lg font-semibold text-theme-primary">
            {(campaign.metrics_summary?.impressions || 0).toLocaleString()}
          </p>
        </div>
        <div className="card-theme p-4">
          <MousePointerClick className="w-5 h-5 text-theme-warning mb-2" />
          <p className="text-xs text-theme-secondary">Clicks</p>
          <p className="text-lg font-semibold text-theme-primary">
            {(campaign.metrics_summary?.clicks || 0).toLocaleString()}
          </p>
        </div>
        <div className="card-theme p-4">
          <ArrowRightLeft className="w-5 h-5 text-theme-success mb-2" />
          <p className="text-xs text-theme-secondary">Conversions</p>
          <p className="text-lg font-semibold text-theme-primary">
            {(campaign.metrics_summary?.conversions || 0).toLocaleString()}
          </p>
        </div>
        <div className="card-theme p-4">
          <DollarSign className="w-5 h-5 text-theme-primary mb-2" />
          <p className="text-xs text-theme-secondary">Revenue</p>
          <p className="text-lg font-semibold text-theme-primary">
            {formatCurrency(campaign.metrics_summary?.revenue_cents || 0)}
          </p>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-theme-border">
        <div className="flex gap-4">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-primary text-theme-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon className="w-4 h-4" />
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Tab Content */}
      {activeTab === 'content' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-medium text-theme-primary">Campaign Content</h3>
            <button onClick={() => { setSelectedContent(null); setShowEditor(true); }} className="btn-theme btn-theme-primary btn-theme-sm">
              Add Content
            </button>
          </div>

          {showEditor && (
            <CampaignContentEditor
              campaignId={campaignId}
              content={selectedContent}
              onSave={() => { setShowEditor(false); refreshContents(); }}
              onCancel={() => setShowEditor(false)}
            />
          )}

          {contents.length === 0 && !showEditor ? (
            <div className="card-theme p-8 text-center">
              <FileText className="w-10 h-10 text-theme-tertiary mx-auto mb-3" />
              <p className="text-theme-secondary">No content yet. Add content for each channel.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {contents.map(content => (
                <CampaignContentPreview
                  key={content.id}
                  content={content}
                  onClick={() => { setSelectedContent(content); setShowEditor(true); }}
                />
              ))}
            </div>
          )}
        </div>
      )}

      {activeTab === 'metrics' && (
        <div className="space-y-4">
          <h3 className="text-lg font-medium text-theme-primary">Performance Metrics</h3>
          {metrics.length === 0 ? (
            <div className="card-theme p-8 text-center">
              <BarChart3 className="w-10 h-10 text-theme-tertiary mx-auto mb-3" />
              <p className="text-theme-secondary">No metrics data available yet.</p>
            </div>
          ) : (
            <div className="card-theme overflow-hidden">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-theme-border">
                    <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Date</th>
                    <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Channel</th>
                    <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Impressions</th>
                    <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Clicks</th>
                    <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Conversions</th>
                    <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Revenue</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-theme-border">
                  {metrics.map(metric => (
                    <tr key={metric.id} className="hover:bg-theme-surface-hover">
                      <td className="px-4 py-3 text-sm text-theme-primary">{metric.date}</td>
                      <td className="px-4 py-3 text-sm text-theme-secondary capitalize">{metric.channel}</td>
                      <td className="px-4 py-3 text-sm text-theme-primary text-right">{metric.impressions.toLocaleString()}</td>
                      <td className="px-4 py-3 text-sm text-theme-primary text-right">{metric.clicks.toLocaleString()}</td>
                      <td className="px-4 py-3 text-sm text-theme-primary text-right">{metric.conversions.toLocaleString()}</td>
                      <td className="px-4 py-3 text-sm text-theme-primary text-right">{formatCurrency(metric.revenue_cents)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {activeTab === 'calendar' && (
        <div className="space-y-4">
          <h3 className="text-lg font-medium text-theme-primary">Schedule</h3>
          <div className="card-theme p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-theme-secondary">Scheduled At</p>
                <p className="text-theme-primary font-medium">
                  {campaign.scheduled_at
                    ? new Date(campaign.scheduled_at).toLocaleString()
                    : 'Not scheduled'}
                </p>
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Started At</p>
                <p className="text-theme-primary font-medium">
                  {campaign.started_at
                    ? new Date(campaign.started_at).toLocaleString()
                    : 'Not started'}
                </p>
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Completed At</p>
                <p className="text-theme-primary font-medium">
                  {campaign.completed_at
                    ? new Date(campaign.completed_at).toLocaleString()
                    : 'In progress'}
                </p>
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Budget / Spent</p>
                <p className="text-theme-primary font-medium">
                  {formatCurrency(campaign.budget_cents)} / {formatCurrency(campaign.spent_cents)}
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
