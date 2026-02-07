import React from 'react';
import { useHostContext } from '../hooks/useHostContext';
import { HostStatusBadge } from './HostStatusBadge';

export const HostSelector: React.FC = () => {
  const { hosts, selectedHostId, selectedHost, selectHost, isLoading } = useHostContext();

  if (isLoading) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-theme-tertiary">Loading hosts...</span>
      </div>
    );
  }

  if (hosts.length === 0) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-theme-tertiary">No hosts configured</span>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-3">
      <label className="text-sm font-medium text-theme-secondary">Host:</label>
      <select
        className="input-theme text-sm min-w-[200px]"
        value={selectedHostId || ''}
        onChange={(e) => selectHost(e.target.value || null)}
      >
        <option value="">Select host...</option>
        {hosts.map((host) => (
          <option key={host.id} value={host.id}>
            {host.name} ({host.environment})
          </option>
        ))}
      </select>
      {selectedHost && <HostStatusBadge status={selectedHost.status} />}
    </div>
  );
};
