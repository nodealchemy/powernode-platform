import React from 'react';
import { Mail, Twitter, Linkedin, Facebook, Instagram, MessageSquare, Bell } from 'lucide-react';
import type { CampaignContent, ChannelType } from '../types';

interface CampaignContentPreviewProps {
  content: CampaignContent;
  onClick?: () => void;
}

const CHANNEL_ICONS: Record<ChannelType, React.ComponentType<{ className?: string }>> = {
  email: Mail,
  twitter: Twitter,
  linkedin: Linkedin,
  facebook: Facebook,
  instagram: Instagram,
  sms: MessageSquare,
  push: Bell,
};

const STATUS_COLORS: Record<string, string> = {
  draft: 'text-theme-secondary',
  review: 'text-theme-info',
  approved: 'text-theme-warning',
  published: 'text-theme-success',
};

export const CampaignContentPreview: React.FC<CampaignContentPreviewProps> = ({ content, onClick }) => {
  const Icon = CHANNEL_ICONS[content.channel] || Mail;
  const statusColor = STATUS_COLORS[content.status] || 'text-theme-secondary';

  return (
    <div
      onClick={onClick}
      className="card-theme p-4 hover:bg-theme-surface-hover cursor-pointer transition-colors"
      data-testid={`content-preview-${content.id}`}
    >
      <div className="flex items-start gap-3">
        <div className="p-2 rounded-lg bg-theme-surface">
          <Icon className="w-5 h-5 text-theme-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-medium text-theme-primary truncate">{content.subject}</h4>
            <span className={`text-xs font-medium capitalize ${statusColor}`}>
              {content.status}
            </span>
          </div>
          <p className="text-xs text-theme-tertiary capitalize mt-0.5">{content.channel}</p>
          <p className="text-sm text-theme-secondary mt-2 line-clamp-3">{content.body}</p>
          {content.scheduled_at && (
            <p className="text-xs text-theme-tertiary mt-2">
              Scheduled: {new Date(content.scheduled_at).toLocaleString()}
            </p>
          )}
        </div>
      </div>
    </div>
  );
};
