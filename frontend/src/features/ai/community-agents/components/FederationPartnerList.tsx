import React, { useState, useEffect, useCallback } from 'react';
import {
  Plus,
  Search,
  RefreshCw,
  Globe,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { communityAgentsApi } from '@/shared/services/ai';
import { FederationPartnerCard } from './FederationPartnerCard';
import { cn } from '@/shared/utils/cn';
import type { FederationPartnerSummary, FederationPartnerFilters, FederationStatus, TrustLevel } from '@/shared/services/ai';

interface FederationPartnerListProps {
  onSelectPartner?: (partner: FederationPartnerSummary) => void;
  onCreatePartner?: () => void;
  className?: string;
}

const statusOptions = [
  { value: '', label: 'All Status' },
  { value: 'pending', label: 'Pending' },
  { value: 'pending_verification', label: 'Pending Verification' },
  { value: 'active', label: 'Active' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'revoked', label: 'Revoked' },
];

const trustOptions = [
  { value: '', label: 'All Trust Levels' },
  { value: 'untrusted', label: 'Untrusted' },
  { value: 'basic', label: 'Basic' },
  { value: 'verified', label: 'Verified' },
  { value: 'trusted', label: 'Trusted' },
  { value: 'partner', label: 'Partner' },
];

export const FederationPartnerList: React.FC<FederationPartnerListProps> = ({
  onSelectPartner,
  onCreatePartner,
  className,
}) => {
  const [partners, setPartners] = useState<FederationPartnerSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [trustFilter, setTrustFilter] = useState<string>('');
  const [searchQuery, setSearchQuery] = useState('');
  const [totalCount, setTotalCount] = useState(0);

  const loadPartners = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: FederationPartnerFilters = { per_page: 50 };
      if (statusFilter) filters.status = statusFilter as FederationStatus;
      if (trustFilter) filters.trust_level = trustFilter as TrustLevel;

      const response = await communityAgentsApi.getFederationPartners(filters);
      setPartners(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load federation partners');
    } finally {
      setLoading(false);
    }
  }, [statusFilter, trustFilter]);

  useEffect(() => {
    loadPartners();
  }, [loadPartners]);

  const handleVerify = async (partner: FederationPartnerSummary) => {
    try {
      await communityAgentsApi.verifyFederationKey(partner.id);
      loadPartners();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to verify partner');
    }
  };

  const handleSync = async (partner: FederationPartnerSummary) => {
    try {
      await communityAgentsApi.syncFederationPartner(partner.id);
      loadPartners();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to sync agents');
    }
  };

  // Local filtering by search query
  const filteredPartners = searchQuery
    ? partners.filter(
        (partner) =>
          (partner.name || partner.organization_name).toLowerCase().includes(searchQuery.toLowerCase()) ||
          partner.endpoint_url.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : partners;

  if (loading && partners.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-theme-text-primary">Federation Partners</h2>
          <p className="text-sm text-theme-text-secondary">
            {totalCount} partner{totalCount !== 1 ? 's' : ''} registered
          </p>
        </div>
        <Button variant="primary" onClick={onCreatePartner}>
          <Plus className="w-4 h-4 mr-2" />
          Add Partner
        </Button>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-text-secondary" />
          <Input
            placeholder="Search partners..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select
          value={statusFilter}
          onChange={(value) => setStatusFilter(value)}
          className="w-40"
        >
          {statusOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Select
          value={trustFilter}
          onChange={(value) => setTrustFilter(value)}
          className="w-40"
        >
          {trustOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Button variant="ghost" onClick={loadPartners} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </div>

      {/* Error */}
      {error && (
        <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error">
          {error}
        </div>
      )}

      {/* Partner Grid */}
      {filteredPartners.length === 0 ? (
        <EmptyState
          icon={Globe}
          title="No federation partners found"
          description={
            searchQuery || statusFilter || trustFilter
              ? 'Try adjusting your filters'
              : 'Connect with other organizations to share agents'
          }
          action={
            !searchQuery && !statusFilter && !trustFilter ? (
              <Button variant="primary" onClick={onCreatePartner}>
                <Plus className="w-4 h-4 mr-2" />
                Add Partner
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredPartners.map((partner) => (
            <FederationPartnerCard
              key={partner.id}
              partner={partner}
              onSelect={onSelectPartner}
              onVerify={handleVerify}
              onSync={handleSync}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export default FederationPartnerList;
