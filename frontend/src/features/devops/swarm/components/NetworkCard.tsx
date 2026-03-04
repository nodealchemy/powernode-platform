import React from 'react';
import { ChevronRight, Trash2, RefreshCw } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import type { SwarmNetwork, SwarmNetworkDetail } from '../types';

export interface NetworkExpandedData {
  details: SwarmNetworkDetail | null;
  isLoading: boolean;
  error: string | null;
}

interface NetworkCardProps {
  network: SwarmNetwork;
  isExpanded: boolean;
  expandedData: NetworkExpandedData | null;
  onToggleExpand: () => void;
  onDelete: () => void;
}

export const NetworkCard: React.FC<NetworkCardProps> = ({
  network,
  isExpanded,
  expandedData,
  onToggleExpand,
  onDelete,
}) => {
  return (
    <Card variant="default" padding="md">
      {/* Collapsed header — always visible */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3 flex-1 min-w-0">
          <button
            onClick={onToggleExpand}
            className="p-1 rounded hover:bg-theme-surface transition-transform"
            title={isExpanded ? 'Collapse' : 'Expand'}
          >
            <ChevronRight className={`w-4 h-4 text-theme-tertiary transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
          </button>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-3">
              <h3 className="text-base font-semibold text-theme-primary">{network.name}</h3>
              <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{network.driver}</span>
              <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{network.scope}</span>
            </div>
            <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
              {network.internal && <span>Internal</span>}
              {network.attachable && <span>Attachable</span>}
              {network.ingress && <span>Ingress</span>}
              <span>Created: {new Date(network.created_at).toLocaleDateString()}</span>
            </div>
          </div>
        </div>
        <Button size="xs" variant="danger" onClick={onDelete} disabled={network.ingress}>
          <Trash2 className="w-3.5 h-3.5" />
        </Button>
      </div>

      {/* Expanded section */}
      {isExpanded && (
        <div className="border-t border-theme mt-3 pt-3 space-y-4">
          {expandedData?.isLoading ? (
            <div className="flex items-center justify-center py-6">
              <RefreshCw className="w-5 h-5 animate-spin text-theme-tertiary" />
              <span className="ml-2 text-sm text-theme-secondary">Loading network details...</span>
            </div>
          ) : expandedData?.error ? (
            <div className="text-center py-4">
              <p className="text-sm text-theme-error mb-2">{expandedData.error}</p>
              <Button size="xs" variant="secondary" onClick={onToggleExpand}>Retry</Button>
            </div>
          ) : expandedData?.details ? (
            <>
              {/* IPAM Config */}
              {expandedData.details.ipam_config.length > 0 && (
                <div>
                  <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">
                    IPAM Config {expandedData.details.ipam_driver && `(${expandedData.details.ipam_driver})`}
                  </h4>
                  <div className="grid grid-cols-3 gap-3">
                    {expandedData.details.ipam_config.map((cfg, i) => (
                      <div key={i} className="bg-theme-surface rounded p-2 text-sm space-y-1">
                        {cfg.subnet && (
                          <div><span className="text-theme-tertiary">Subnet: </span><span className="text-theme-primary font-mono">{cfg.subnet}</span></div>
                        )}
                        {cfg.gateway && (
                          <div><span className="text-theme-tertiary">Gateway: </span><span className="text-theme-primary font-mono">{cfg.gateway}</span></div>
                        )}
                        {cfg.ip_range && (
                          <div><span className="text-theme-tertiary">IP Range: </span><span className="text-theme-primary font-mono">{cfg.ip_range}</span></div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Connected Containers */}
              <div>
                <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">
                  Connected Containers ({expandedData.details.containers.length})
                </h4>
                {expandedData.details.containers.length === 0 ? (
                  <p className="text-sm text-theme-tertiary">No containers connected</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="text-left text-xs text-theme-tertiary uppercase tracking-wider">
                          <th className="pb-1 pr-4">Name</th>
                          <th className="pb-1 pr-4">IPv4</th>
                          <th className="pb-1 pr-4">IPv6</th>
                          <th className="pb-1">MAC</th>
                        </tr>
                      </thead>
                      <tbody>
                        {expandedData.details.containers.map((c) => (
                          <tr key={c.id} className="border-t border-theme">
                            <td className="py-1 pr-4 text-theme-primary font-medium">{c.name}</td>
                            <td className="py-1 pr-4 text-theme-secondary font-mono">{c.ipv4_address || '—'}</td>
                            <td className="py-1 pr-4 text-theme-secondary font-mono">{c.ipv6_address || '—'}</td>
                            <td className="py-1 text-theme-secondary font-mono">{c.mac_address || '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>

              {/* Driver Options */}
              {Object.keys(expandedData.details.options).length > 0 && (
                <div>
                  <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Options</h4>
                  <div className="flex flex-wrap gap-1">
                    {Object.entries(expandedData.details.options).map(([k, v]) => (
                      <span key={k} className="px-1.5 py-0.5 rounded bg-theme-surface text-xs text-theme-secondary font-mono">
                        {k}={v}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* Labels */}
              {Object.keys(expandedData.details.labels).length > 0 && (
                <div>
                  <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Labels</h4>
                  <div className="flex flex-wrap gap-1">
                    {Object.entries(expandedData.details.labels).map(([k, v]) => (
                      <span key={k} className="px-1.5 py-0.5 rounded bg-theme-surface text-xs text-theme-secondary font-mono">
                        {k}={v}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* IPv6 + Peers */}
              <div className="flex items-center gap-4 text-sm">
                <span className="text-theme-tertiary">
                  IPv6: <span className={expandedData.details.enable_ipv6 ? 'text-theme-success' : 'text-theme-secondary'}>{expandedData.details.enable_ipv6 ? 'Enabled' : 'Disabled'}</span>
                </span>
                {expandedData.details.peers && expandedData.details.peers.length > 0 && (
                  <span className="text-theme-tertiary">
                    Peers: {expandedData.details.peers.map(p => `${p.name} (${p.ip})`).join(', ')}
                  </span>
                )}
              </div>
            </>
          ) : null}
        </div>
      )}
    </Card>
  );
};
