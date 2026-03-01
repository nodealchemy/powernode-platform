import React, { useState } from 'react';
import { X, Twitter, Linkedin, Facebook, Instagram, Youtube, Wifi } from 'lucide-react';
import { logger } from '@/shared/utils/logger';
import type { SocialPlatform } from '../types';

interface ConnectSocialModalProps {
  onConnect: (data: { platform: SocialPlatform; auth_code: string; redirect_uri: string }) => Promise<void>;
  onClose: () => void;
}

const PLATFORMS: { value: SocialPlatform; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { value: 'twitter', label: 'Twitter', icon: Twitter },
  { value: 'linkedin', label: 'LinkedIn', icon: Linkedin },
  { value: 'facebook', label: 'Facebook', icon: Facebook },
  { value: 'instagram', label: 'Instagram', icon: Instagram },
  { value: 'youtube', label: 'YouTube', icon: Youtube },
  { value: 'tiktok', label: 'TikTok', icon: Wifi },
];

export const ConnectSocialModal: React.FC<ConnectSocialModalProps> = ({ onConnect, onClose }) => {
  const [selectedPlatform, setSelectedPlatform] = useState<SocialPlatform | null>(null);
  const [authCode, setAuthCode] = useState('');
  const [connecting, setConnecting] = useState(false);

  const handleConnect = async () => {
    if (!selectedPlatform || !authCode.trim()) return;
    try {
      setConnecting(true);
      await onConnect({
        platform: selectedPlatform,
        auth_code: authCode.trim(),
        redirect_uri: window.location.origin + '/app/marketing/social/callback',
      });
      onClose();
    } catch (err) {
      logger.error('Failed to connect social account:', err);
    } finally {
      setConnecting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="card-theme-elevated p-6 w-full max-w-md">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-medium text-theme-primary">Connect Social Account</h3>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="space-y-4">
          {/* Platform Selection */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">Select Platform</label>
            <div className="grid grid-cols-3 gap-2">
              {PLATFORMS.map(p => (
                <button
                  key={p.value}
                  onClick={() => setSelectedPlatform(p.value)}
                  className={`flex flex-col items-center gap-1.5 p-3 rounded-lg border transition-colors ${
                    selectedPlatform === p.value
                      ? 'border-theme-primary bg-theme-primary bg-opacity-5'
                      : 'border-theme-border hover:bg-theme-surface-hover'
                  }`}
                >
                  <p.icon className={`w-6 h-6 ${
                    selectedPlatform === p.value ? 'text-theme-primary' : 'text-theme-secondary'
                  }`} />
                  <span className="text-xs text-theme-primary">{p.label}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Auth Code */}
          {selectedPlatform && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Authorization Code
              </label>
              <p className="text-xs text-theme-tertiary mb-2">
                Complete the OAuth flow for {selectedPlatform} and paste the authorization code below.
              </p>
              <input
                type="text"
                value={authCode}
                onChange={(e) => setAuthCode(e.target.value)}
                className="input-theme w-full"
                placeholder="Paste authorization code"
              />
            </div>
          )}

          {/* Actions */}
          <div className="flex justify-end gap-3 pt-2">
            <button onClick={onClose} className="btn-theme btn-theme-secondary">
              Cancel
            </button>
            <button
              onClick={handleConnect}
              disabled={!selectedPlatform || !authCode.trim() || connecting}
              className="btn-theme btn-theme-primary disabled:opacity-50"
            >
              {connecting ? 'Connecting...' : 'Connect'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
