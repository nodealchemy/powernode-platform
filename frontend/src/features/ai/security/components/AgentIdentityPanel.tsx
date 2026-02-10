import React from 'react';
import { X, Key, ShieldCheck, Clock, Fingerprint } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useAgentIdentity } from '../api/securityExtApi';
import type { IdentityStatus } from '../types/security';

const STATUS_VARIANTS: Record<IdentityStatus, 'success' | 'warning' | 'danger' | 'default'> = {
  active: 'success',
  rotated: 'warning',
  revoked: 'danger',
  expired: 'default',
};

interface AgentIdentityPanelProps {
  identityId: string;
  onClose: () => void;
}

export const AgentIdentityPanel: React.FC<AgentIdentityPanelProps> = ({ identityId, onClose }) => {
  const { data: identity, isLoading } = useAgentIdentity(identityId);

  if (isLoading) {
    return (
      <Card className="p-6">
        <LoadingSpinner size="sm" />
      </Card>
    );
  }

  if (!identity) {
    return null;
  }

  const infoRows: { label: string; value: React.ReactNode; icon: React.ReactNode }[] = [
    {
      label: 'Key Fingerprint',
      value: <span className="font-mono text-xs">{identity.key_fingerprint}</span>,
      icon: <Fingerprint className="h-4 w-4 text-theme-muted" />,
    },
    {
      label: 'Algorithm',
      value: identity.algorithm,
      icon: <Key className="h-4 w-4 text-theme-muted" />,
    },
    {
      label: 'Agent URI',
      value: identity.agent_uri || '--',
      icon: <ShieldCheck className="h-4 w-4 text-theme-muted" />,
    },
    {
      label: 'Expires At',
      value: identity.expires_at ? new Date(identity.expires_at).toLocaleString() : 'Never',
      icon: <Clock className="h-4 w-4 text-theme-muted" />,
    },
    {
      label: 'Last Rotated',
      value: identity.rotated_at ? new Date(identity.rotated_at).toLocaleString() : 'Never',
      icon: <Clock className="h-4 w-4 text-theme-muted" />,
    },
    {
      label: 'Rotation Overlap Until',
      value: identity.rotation_overlap_until ? new Date(identity.rotation_overlap_until).toLocaleString() : '--',
      icon: <Clock className="h-4 w-4 text-theme-muted" />,
    },
  ];

  return (
    <Card className="p-6 border border-theme">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 bg-theme-primary bg-opacity-10 rounded-lg flex items-center justify-center">
            <Key className="h-5 w-5 text-theme-primary" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Identity Details</h3>
            <p className="text-sm text-theme-secondary">Agent: {identity.agent_id}</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <Badge variant={STATUS_VARIANTS[identity.status] || 'default'} size="sm">
            {identity.status}
          </Badge>
          <Button variant="ghost" size="xs" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Info Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        {infoRows.map((row) => (
          <div key={row.label} className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
            <div className="mt-0.5">{row.icon}</div>
            <div>
              <p className="text-xs text-theme-tertiary">{row.label}</p>
              <p className="text-sm text-theme-primary">{row.value}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Revocation Info */}
      {identity.revoked_at && (
        <div className="bg-theme-error bg-opacity-5 border border-theme rounded-lg p-4 mb-6">
          <h4 className="text-sm font-medium text-theme-error mb-1">Revocation Details</h4>
          <p className="text-sm text-theme-secondary">
            Revoked: {new Date(identity.revoked_at).toLocaleString()}
          </p>
          {identity.revocation_reason && (
            <p className="text-sm text-theme-secondary mt-1">
              Reason: {identity.revocation_reason}
            </p>
          )}
        </div>
      )}

      {/* Attestation Claims */}
      {identity.attestation_claims && Object.keys(identity.attestation_claims).length > 0 && (
        <div className="mb-6">
          <h4 className="text-sm font-medium text-theme-primary mb-2">Attestation Claims</h4>
          <div className="bg-theme-bg rounded-lg p-3">
            <pre className="text-xs text-theme-secondary overflow-x-auto whitespace-pre-wrap">
              {JSON.stringify(identity.attestation_claims, null, 2)}
            </pre>
          </div>
        </div>
      )}

      {/* Capabilities */}
      {identity.capabilities && identity.capabilities.length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-theme-primary mb-2">Capabilities</h4>
          <div className="flex flex-wrap gap-2">
            {identity.capabilities.map((cap) => (
              <Badge key={cap} variant="outline" size="xs">
                {cap}
              </Badge>
            ))}
          </div>
        </div>
      )}
    </Card>
  );
};
