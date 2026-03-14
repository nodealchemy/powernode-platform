import React, { useState } from 'react';
import { X, Key, CheckCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Badge } from '@/shared/components/ui/Badge';
import { useSigningKeys } from '../../hooks/useAttestations';

interface SignAttestationModalProps {
  attestationId: string;
  attestationName: string;
  onClose: () => void;
  onSign: (signingKeyId?: string) => Promise<void>;
}

export const SignAttestationModal: React.FC<SignAttestationModalProps> = ({
  attestationName,
  onClose,
  onSign,
}) => {
  const { signingKeys, loading: loadingKeys } = useSigningKeys();
  const [selectedKeyId, setSelectedKeyId] = useState<string | null>(null);
  const [signing, setSigning] = useState(false);

  const handleSign = async () => {
    try {
      setSigning(true);
      await onSign(selectedKeyId || undefined);
      onClose();
    } finally {
      setSigning(false);
    }
  };

  const defaultKey = signingKeys.find((k) => k.is_default);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      <div className="relative z-10 w-full max-w-lg bg-theme-surface rounded-lg shadow-xl mx-4">
        <div className="border-b border-theme px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Key className="w-5 h-5 text-theme-interactive-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">Sign Attestation</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover">
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        <div className="p-6">
          <div className="mb-6">
            <span className="text-sm text-theme-secondary">Signing:</span>
            <p className="font-medium text-theme-primary">{attestationName}</p>
          </div>

          <div className="mb-4">
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Select Signing Key
            </label>

            {loadingKeys ? (
              <div className="flex justify-center py-4">
                <LoadingSpinner size="md" />
              </div>
            ) : signingKeys.length === 0 ? (
              <div className="text-center py-4 text-theme-muted">
                <p>No signing keys available</p>
                <p className="text-sm mt-1">A default key will be used if available</p>
              </div>
            ) : (
              <div className="space-y-2 max-h-64 overflow-y-auto">
                <button
                  onClick={() => setSelectedKeyId(null)}
                  className={`w-full p-3 rounded-lg border text-left transition-colors ${
                    selectedKeyId === null
                      ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                      : 'border-theme hover:border-theme-border-hover'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <span className="font-medium text-theme-primary">Use Default Key</span>
                    {defaultKey && (
                      <Badge variant="success" size="sm">
                        {defaultKey.name}
                      </Badge>
                    )}
                  </div>
                </button>

                {signingKeys.map((key) => (
                  <button
                    key={key.id}
                    onClick={() => setSelectedKeyId(key.id)}
                    className={`w-full p-3 rounded-lg border text-left transition-colors ${
                      selectedKeyId === key.id
                        ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                        : 'border-theme hover:border-theme-border-hover'
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="font-medium text-theme-primary">{key.name}</p>
                        <div className="flex items-center gap-2 mt-1">
                          <span className="text-xs text-theme-secondary uppercase">{key.key_type}</span>
                          <code className="text-xs text-theme-muted">
                            {key.fingerprint.substring(0, 16)}...
                          </code>
                        </div>
                      </div>
                      {key.is_default && (
                        <Badge variant="info" size="sm">
                          Default
                        </Badge>
                      )}
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="p-4 bg-theme-info/10 rounded-lg text-sm text-theme-primary">
            <div className="flex items-start gap-2">
              <CheckCircle className="w-5 h-5 text-theme-info flex-shrink-0 mt-0.5" />
              <div>
                <p className="font-medium">Signing creates a cryptographic signature</p>
                <p className="text-theme-secondary mt-1">
                  This proves the attestation was created by a trusted party and hasn't been tampered with.
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="border-t border-theme px-6 py-4 flex justify-end gap-3">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleSign} disabled={signing}>
            {signing ? 'Signing...' : 'Sign Attestation'}
          </Button>
        </div>
      </div>
    </div>
  );
};
