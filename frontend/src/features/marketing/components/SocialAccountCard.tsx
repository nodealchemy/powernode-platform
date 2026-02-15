import React from 'react';
import {
  Twitter,
  Linkedin,
  Facebook,
  Instagram,
  Youtube,
  RefreshCw,
  Trash2,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  Wifi,
} from 'lucide-react';
import type { SocialMediaAccount, SocialPlatform, SocialAccountStatus } from '../types';

interface SocialAccountCardProps {
  account: SocialMediaAccount;
  onTest: (id: string) => void;
  onRefreshToken: (id: string) => void;
  onDisconnect: (id: string) => void;
}

const PLATFORM_ICONS: Record<SocialPlatform, React.ComponentType<{ className?: string }>> = {
  twitter: Twitter,
  linkedin: Linkedin,
  facebook: Facebook,
  instagram: Instagram,
  youtube: Youtube,
  tiktok: Wifi,
};

const STATUS_CONFIG: Record<SocialAccountStatus, { icon: React.ComponentType<{ className?: string }>; color: string; label: string }> = {
  connected: { icon: CheckCircle2, color: 'text-theme-success', label: 'Connected' },
  disconnected: { icon: XCircle, color: 'text-theme-error', label: 'Disconnected' },
  expired: { icon: AlertTriangle, color: 'text-theme-warning', label: 'Token Expired' },
  error: { icon: XCircle, color: 'text-theme-error', label: 'Error' },
};

export const SocialAccountCard: React.FC<SocialAccountCardProps> = ({
  account,
  onTest,
  onRefreshToken,
  onDisconnect,
}) => {
  const PlatformIcon = PLATFORM_ICONS[account.platform] || Wifi;
  const statusConfig = STATUS_CONFIG[account.status];
  const StatusIcon = statusConfig.icon;

  return (
    <div className="card-theme p-4" data-testid={`social-account-${account.id}`}>
      <div className="flex items-start gap-4">
        {/* Avatar / Platform Icon */}
        <div className="flex-shrink-0">
          {account.avatar_url ? (
            <img
              src={account.avatar_url}
              alt={account.account_name}
              className="w-12 h-12 rounded-full"
            />
          ) : (
            <div className="w-12 h-12 rounded-full bg-theme-surface flex items-center justify-center">
              <PlatformIcon className="w-6 h-6 text-theme-primary" />
            </div>
          )}
        </div>

        {/* Account Info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h4 className="text-sm font-medium text-theme-primary truncate">{account.account_name}</h4>
            <PlatformIcon className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
          </div>
          <p className="text-xs text-theme-tertiary">@{account.account_handle}</p>

          <div className="flex items-center gap-3 mt-2">
            <div className="flex items-center gap-1">
              <StatusIcon className={`w-3.5 h-3.5 ${statusConfig.color}`} />
              <span className={`text-xs font-medium ${statusConfig.color}`}>
                {statusConfig.label}
              </span>
            </div>
            <span className="text-xs text-theme-tertiary">
              {account.followers_count.toLocaleString()} followers
            </span>
          </div>

          {account.token_expires_at && (
            <p className="text-[10px] text-theme-tertiary mt-1">
              Token expires: {new Date(account.token_expires_at).toLocaleDateString()}
            </p>
          )}
        </div>

        {/* Actions */}
        <div className="flex flex-col gap-1 flex-shrink-0">
          <button
            onClick={() => onTest(account.id)}
            className="p-1.5 rounded hover:bg-theme-surface-hover text-theme-secondary"
            title="Test connection"
          >
            <CheckCircle2 className="w-4 h-4" />
          </button>
          {(account.status === 'expired' || account.status === 'error') && (
            <button
              onClick={() => onRefreshToken(account.id)}
              className="p-1.5 rounded hover:bg-theme-surface-hover text-theme-warning"
              title="Refresh token"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
          )}
          <button
            onClick={() => onDisconnect(account.id)}
            className="p-1.5 rounded hover:bg-theme-surface-hover text-theme-error"
            title="Disconnect account"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
};
