import React from 'react';
import {
  MessageSquare,
  Users,
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  Settings,
  Power,
  PowerOff,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import type { ChatChannelSummary, ChatPlatform, ChannelStatus } from '@/shared/services/ai';

interface ChannelCardProps {
  channel: ChatChannelSummary;
  onSelect?: (channel: ChatChannelSummary) => void;
  onConnect?: (channel: ChatChannelSummary) => void;
  onDisconnect?: (channel: ChatChannelSummary) => void;
  onSettings?: (channel: ChatChannelSummary) => void;
  className?: string;
}

const platformIcons: Record<ChatPlatform, React.ReactNode> = {
  telegram: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.894 8.221l-1.97 9.28c-.145.658-.537.818-1.084.508l-3-2.21-1.446 1.394c-.14.14-.26.26-.534.26l.193-2.98 5.453-4.93c.24-.213-.05-.332-.373-.119l-6.738 4.244-2.9-.907c-.63-.198-.643-.63.133-.933l11.32-4.365c.524-.194.983.126.811.93l.135-.172z" />
    </svg>
  ),
  discord: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M20.317 4.37a19.791 19.791 0 00-4.885-1.515.074.074 0 00-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 00-5.487 0 12.64 12.64 0 00-.617-1.25.077.077 0 00-.079-.037A19.736 19.736 0 003.677 4.37a.07.07 0 00-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 00.031.057 19.9 19.9 0 005.993 3.03.078.078 0 00.084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 00-.041-.106 13.107 13.107 0 01-1.872-.892.077.077 0 01-.008-.128 10.2 10.2 0 00.372-.292.074.074 0 01.077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 01.078.01c.12.098.246.198.373.292a.077.077 0 01-.006.127 12.299 12.299 0 01-1.873.892.077.077 0 00-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 00.084.028 19.839 19.839 0 006.002-3.03.077.077 0 00.032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 00-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z" />
    </svg>
  ),
  slack: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M5.042 15.165a2.528 2.528 0 01-2.52 2.523A2.528 2.528 0 010 15.165a2.527 2.527 0 012.522-2.52h2.52v2.52zm1.271 0a2.527 2.527 0 012.521-2.52 2.527 2.527 0 012.521 2.52v6.313A2.528 2.528 0 018.834 24a2.528 2.528 0 01-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 01-2.521-2.52A2.528 2.528 0 018.834 0a2.528 2.528 0 012.521 2.522v2.52H8.834zm0 1.271a2.528 2.528 0 012.521 2.521 2.528 2.528 0 01-2.521 2.521H2.522A2.528 2.528 0 010 8.834a2.528 2.528 0 012.522-2.521h6.312zm10.124 2.521a2.528 2.528 0 012.522-2.521A2.528 2.528 0 0124 8.834a2.528 2.528 0 01-2.52 2.521h-2.522V8.834zm-1.268 0a2.528 2.528 0 01-2.523 2.521 2.527 2.527 0 01-2.52-2.521V2.522A2.527 2.527 0 0115.165 0a2.528 2.528 0 012.523 2.522v6.312zm-2.523 10.124a2.528 2.528 0 012.523 2.52A2.528 2.528 0 0115.165 24a2.527 2.527 0 01-2.52-2.522v-2.52h2.52zm0-1.268a2.527 2.527 0 01-2.52-2.523 2.526 2.526 0 012.52-2.52h6.313A2.527 2.527 0 0124 15.165a2.528 2.528 0 01-2.522 2.523h-6.313z" />
    </svg>
  ),
  whatsapp: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
    </svg>
  ),
  mattermost: (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12.081 0C7.048-.067 2.477 3.09.637 7.876c-1.95 5.075-.149 10.318 3.627 13.618 1.304 1.14 3.721 2.297 5.59 2.506-.483-1.24-.664-3.327-.664-3.327-.591.104-1.335-.002-1.926-.358-.74-.446-1.15-1.32-1.185-1.399a2.252 2.252 0 01-.053-.132c-.113-.315-.16-.6-.183-.863 0-.032-.004-.07-.007-.108-.006-.065-.01-.13-.013-.186-.014-.286-.014-.485-.014-.485-.074-.088-.17-.176-.285-.281-.192-.177-.465-.378-.775-.598-.31-.22-.657-.458-.997-.707-.18-.132-.36-.265-.533-.4-.172-.136-.334-.272-.48-.407-.293-.272-.52-.54-.62-.79a1.238 1.238 0 01-.046-.62c.032-.166.1-.314.184-.447.084-.132.183-.248.285-.35.204-.203.41-.345.532-.418l.087-.052a9.63 9.63 0 01.2-.107c.265-.136.52-.25.715-.336.586-.257 1.094-.365 1.094-.365l-.003-.04c-.01-.127-.024-.28-.024-.457 0-.177.008-.378.042-.598.034-.22.09-.46.19-.715.1-.256.244-.527.457-.8a3.38 3.38 0 01.806-.758c.348-.237.762-.43 1.234-.548a5.188 5.188 0 011.074-.156 6.24 6.24 0 01.758.009c.124.01.247.024.37.044.123.02.245.045.367.077.49.127.967.34 1.397.632.43.292.813.663 1.112 1.095.15.216.277.447.378.688s.176.492.222.744c.023.126.04.253.051.38.012.127.018.254.018.38 0 .253-.024.504-.068.75-.045.244-.11.483-.197.714a5.05 5.05 0 01-.315.666 5.4 5.4 0 01-.39.594 7.65 7.65 0 01-.233.297c-.08.097-.16.19-.235.275-.15.17-.282.305-.382.398-.1.093-.166.144-.166.144l.048.063c.068.092.177.237.315.431.138.193.305.435.482.72.088.142.178.293.267.452.09.16.178.328.26.504.083.176.162.36.231.55.07.19.131.387.18.588.048.2.084.404.103.609.02.205.023.41.006.614a2.893 2.893 0 01-.078.475 3.2 3.2 0 01-.151.433c-.06.137-.131.27-.213.398-.164.257-.372.498-.624.718-.252.22-.548.417-.885.586a5.12 5.12 0 01-1.056.407c-.366.095-.75.155-1.138.177-.194.011-.389.013-.584.004a5.974 5.974 0 01-.578-.04c-.095-.012-.19-.026-.284-.043a4.67 4.67 0 01-.278-.057 5.67 5.67 0 01-.544-.146 6.44 6.44 0 01-.525-.187c-.17-.07-.335-.148-.494-.232-.08-.042-.158-.086-.234-.132a4.64 4.64 0 01-.225-.144c-.073-.05-.144-.102-.213-.155-.07-.053-.136-.107-.2-.162a4.002 4.002 0 01-.353-.343c-.054-.058-.104-.116-.152-.175a3.07 3.07 0 01-.13-.17c-.04-.055-.076-.11-.109-.163a2.64 2.64 0 01-.09-.15c-.053-.095-.096-.185-.127-.266a1.782 1.782 0 01-.086-.257 1.33 1.33 0 01-.032-.186 1.14 1.14 0 01-.01-.16v.003s-.082 2.053.338 3.34c0 0-2.166-.434-4.062-1.59A11.915 11.915 0 0012.083 24c6.589 0 11.93-5.342 11.93-11.93 0-6.588-5.342-11.93-11.93-11.93l-.002-.14z" />
    </svg>
  ),
};

const statusConfig: Record<ChannelStatus, { icon: React.FC<{ className?: string }>; variant: 'success' | 'danger' | 'warning' | 'outline'; label: string }> = {
  active: { icon: CheckCircle, variant: 'success', label: 'Connected' },
  inactive: { icon: AlertCircle, variant: 'outline', label: 'Inactive' },
  error: { icon: XCircle, variant: 'danger', label: 'Error' },
  disconnected: { icon: PowerOff, variant: 'warning', label: 'Disconnected' },
};

export const ChannelCard: React.FC<ChannelCardProps> = ({
  channel,
  onSelect,
  onConnect,
  onDisconnect,
  onSettings,
  className,
}) => {
  const status = statusConfig[channel.status] || statusConfig.inactive;
  const StatusIcon = status.icon;

  const formatTime = (timestamp?: string) => {
    if (!timestamp) return 'Never';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };

  return (
    <Card
      className={cn(
        'cursor-pointer transition-all hover:shadow-md',
        'border-theme-border-primary',
        className
      )}
      onClick={() => onSelect?.(channel)}
    >
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-bg-secondary text-theme-text-primary">
              {platformIcons[channel.platform]}
            </div>
            <div>
              <h3 className="font-medium text-theme-text-primary">{channel.name}</h3>
              <p className="text-sm text-theme-text-secondary capitalize">{channel.platform}</p>
            </div>
          </div>
          <Badge variant={status.variant} size="sm">
            <StatusIcon className="w-3 h-3 mr-1" />
            {status.label}
          </Badge>
        </div>

        <div className="mt-4 grid grid-cols-3 gap-4 text-sm">
          <div className="flex items-center gap-2 text-theme-text-secondary">
            <Users className="w-4 h-4" />
            <span>{channel.active_sessions} active</span>
          </div>
          <div className="flex items-center gap-2 text-theme-text-secondary">
            <MessageSquare className="w-4 h-4" />
            <span>{channel.total_sessions} total</span>
          </div>
          <div className="flex items-center gap-2 text-theme-text-secondary">
            <Clock className="w-4 h-4" />
            <span>{formatTime(channel.last_message_at)}</span>
          </div>
        </div>

        <div className="mt-4 flex gap-2" onClick={(e) => e.stopPropagation()}>
          {channel.status === 'active' ? (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onDisconnect?.(channel)}
              className="flex-1"
            >
              <PowerOff className="w-4 h-4 mr-1" />
              Disconnect
            </Button>
          ) : (
            <Button
              variant="primary"
              size="sm"
              onClick={() => onConnect?.(channel)}
              className="flex-1"
            >
              <Power className="w-4 h-4 mr-1" />
              Connect
            </Button>
          )}
          <Button
            variant="ghost"
            size="sm"
            onClick={() => onSettings?.(channel)}
          >
            <Settings className="w-4 h-4" />
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default ChannelCard;
