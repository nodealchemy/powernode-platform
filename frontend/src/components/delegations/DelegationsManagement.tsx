import React, { useState, useEffect } from 'react';
import { delegationApi, Delegation, DelegationRequest, DELEGATION_PERMISSIONS } from '../../services/delegationApi';
import { CreateDelegationModal } from './CreateDelegationModal';
import { DelegationDetailsModal } from './DelegationDetailsModal';
import { DelegationRequestModal } from './DelegationRequestModal';

export const DelegationsManagement: React.FC = () => {
  const [activeDelegations, setActiveDelegations] = useState<Delegation[]>([]);
  const [pendingRequests, setPendingRequests] = useState<DelegationRequest[]>([]);
  const [selectedDelegation, setSelectedDelegation] = useState<Delegation | null>(null);
  const [selectedRequest, setSelectedRequest] = useState<DelegationRequest | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showDetailsModal, setShowDetailsModal] = useState(false);
  const [showRequestModal, setShowRequestModal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'outgoing' | 'incoming'>('outgoing');

  useEffect(() => {
    loadDelegations();
    loadRequests();
  }, []);

  const loadDelegations = async () => {
    try {
      setLoading(true);
      const data = await delegationApi.getDelegations();
      setActiveDelegations(data.delegations || []);
    } catch (error) {
      console.error('Failed to load delegations:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadRequests = async () => {
    try {
      const data = await delegationApi.getDelegationRequests('pending');
      setPendingRequests(data.requests || []);
    } catch (error) {
      console.error('Failed to load delegation requests:', error);
    }
  };

  const handleCreateDelegation = async (data: any) => {
    try {
      await delegationApi.createDelegation(data);
      loadDelegations();
      setShowCreateModal(false);
    } catch (error) {
      console.error('Failed to create delegation:', error);
    }
  };

  const handleRevokeDelegation = async (delegationId: string) => {
    if (window.confirm('Are you sure you want to revoke this delegation?')) {
      try {
        await delegationApi.revokeDelegation(delegationId);
        loadDelegations();
        setShowDetailsModal(false);
      } catch (error) {
        console.error('Failed to revoke delegation:', error);
      }
    }
  };

  const handleApproveRequest = async (requestId: string, note?: string) => {
    try {
      await delegationApi.approveDelegationRequest(requestId, note);
      loadRequests();
      loadDelegations();
      setShowRequestModal(false);
    } catch (error) {
      console.error('Failed to approve request:', error);
    }
  };

  const handleRejectRequest = async (requestId: string, reason: string) => {
    try {
      await delegationApi.rejectDelegationRequest(requestId, reason);
      loadRequests();
      setShowRequestModal(false);
    } catch (error) {
      console.error('Failed to reject request:', error);
    }
  };

  const getStatusBadge = (status: string) => {
    const statusClasses = {
      active: 'bg-theme-success bg-opacity-10 text-theme-success',
      pending: 'bg-theme-warning bg-opacity-10 text-theme-warning',
      expired: 'bg-theme-error bg-opacity-10 text-theme-error',
      revoked: 'bg-theme-surface text-theme-tertiary',
    };

    return (
      <span className={`text-xs px-2 py-1 rounded-full ${statusClasses[status as keyof typeof statusClasses] || statusClasses.pending}`}>
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    );
  };

  const formatDate = (date: string) => {
    return new Date(date).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-theme-secondary">Loading delegations...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Account Delegations</h2>
            <p className="text-theme-secondary mt-1">Manage cross-account access and delegations</p>
          </div>
          <button 
            onClick={() => setShowCreateModal(true)}
            className="btn-theme btn-theme-primary"
          >
            Create Delegation
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="flex space-x-1 mb-6 border-b border-theme">
          <button
            onClick={() => setActiveTab('outgoing')}
            className={`px-4 py-2 font-medium text-sm transition-colors ${
              activeTab === 'outgoing'
                ? 'text-theme-primary border-b-2 border-theme-interactive-primary'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Outgoing Delegations
            {activeDelegations.filter(d => d.sourceAccountId === 'current').length > 0 && (
              <span className="ml-2 bg-theme-surface px-2 py-0.5 rounded-full text-xs">
                {activeDelegations.filter(d => d.sourceAccountId === 'current').length}
              </span>
            )}
          </button>
          <button
            onClick={() => setActiveTab('incoming')}
            className={`px-4 py-2 font-medium text-sm transition-colors ${
              activeTab === 'incoming'
                ? 'text-theme-primary border-b-2 border-theme-interactive-primary'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Incoming Access
            {activeDelegations.filter(d => d.targetAccountId === 'current').length > 0 && (
              <span className="ml-2 bg-theme-surface px-2 py-0.5 rounded-full text-xs">
                {activeDelegations.filter(d => d.targetAccountId === 'current').length}
              </span>
            )}
          </button>
        </div>

        {/* Pending Requests Alert */}
        {pendingRequests.length > 0 && (
          <div className="mb-6 bg-theme-warning bg-opacity-10 border border-theme-warning border-opacity-30 rounded-lg p-4">
            <div className="flex items-start space-x-3">
              <span className="text-theme-warning text-xl">⚠️</span>
              <div className="flex-1">
                <h3 className="font-medium text-theme-warning">Pending Delegation Requests</h3>
                <p className="text-sm text-theme-warning opacity-80 mt-1">
                  You have {pendingRequests.length} pending delegation request{pendingRequests.length > 1 ? 's' : ''} awaiting your review.
                </p>
                <div className="mt-3 space-y-2">
                  {pendingRequests.slice(0, 3).map((request) => (
                    <button
                      key={request.id}
                      onClick={() => {
                        setSelectedRequest(request);
                        setShowRequestModal(true);
                      }}
                      className="block w-full text-left bg-theme-surface rounded-lg p-3 hover:bg-theme-surface-hover transition-colors"
                    >
                      <div className="flex items-center justify-between">
                        <div>
                          <span className="font-medium text-theme-primary">{request.requestedByName}</span>
                          <span className="text-theme-secondary text-sm ml-2">from {request.delegation.sourceAccountName}</span>
                        </div>
                        <span className="text-theme-link text-sm">Review →</span>
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        )}

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Active Delegations */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">
              {activeTab === 'outgoing' ? 'Active Delegations' : 'Granted Access'}
            </h3>
            <div className="space-y-3">
              {activeDelegations
                .filter(d => d.status === 'active')
                .filter(d => activeTab === 'outgoing' ? d.sourceAccountId === 'current' : d.targetAccountId === 'current')
                .map((delegation) => (
                  <div
                    key={delegation.id}
                    className="bg-theme-background rounded-lg p-4 border border-theme hover:border-theme-focus transition-colors cursor-pointer"
                    onClick={() => {
                      setSelectedDelegation(delegation);
                      setShowDetailsModal(true);
                    }}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <h4 className="font-medium text-theme-primary">{delegation.name}</h4>
                      {getStatusBadge(delegation.status)}
                    </div>
                    <p className="text-sm text-theme-secondary mb-3">
                      {delegation.description}
                    </p>
                    <div className="flex items-center justify-between text-sm">
                      <div className="flex items-center space-x-4">
                        <span className="text-theme-tertiary">
                          {delegation.users.length} user{delegation.users.length !== 1 ? 's' : ''}
                        </span>
                        <span className="text-theme-tertiary">
                          {delegation.permissions.length} permission{delegation.permissions.length !== 1 ? 's' : ''}
                        </span>
                      </div>
                      <span className="text-theme-link hover:text-theme-link-hover">
                        Manage →
                      </span>
                    </div>
                    {delegation.expiresAt && (
                      <div className="mt-2 pt-2 border-t border-theme">
                        <span className="text-xs text-theme-tertiary">
                          Expires: {formatDate(delegation.expiresAt)}
                        </span>
                      </div>
                    )}
                  </div>
                ))}

              {activeDelegations.filter(d => d.status === 'active').length === 0 && (
                <div className="bg-theme-background rounded-lg p-8 text-center border border-theme">
                  <span className="text-4xl">🔐</span>
                  <p className="text-theme-secondary mt-2">No active delegations</p>
                  <p className="text-theme-tertiary text-sm mt-1">
                    Create a delegation to grant access to other accounts
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Expired/Revoked Delegations */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Inactive Delegations</h3>
            <div className="space-y-3">
              {activeDelegations
                .filter(d => d.status !== 'active' && d.status !== 'pending')
                .filter(d => activeTab === 'outgoing' ? d.sourceAccountId === 'current' : d.targetAccountId === 'current')
                .map((delegation) => (
                  <div
                    key={delegation.id}
                    className="bg-theme-background rounded-lg p-4 border border-theme opacity-75"
                  >
                    <div className="flex items-center justify-between mb-2">
                      <h4 className="font-medium text-theme-primary">{delegation.name}</h4>
                      {getStatusBadge(delegation.status)}
                    </div>
                    <p className="text-sm text-theme-secondary">
                      {delegation.description}
                    </p>
                    <div className="mt-2 text-xs text-theme-tertiary">
                      {delegation.status === 'expired' ? 'Expired' : 'Revoked'} on {formatDate(delegation.updatedAt)}
                    </div>
                  </div>
                ))}

              {activeDelegations.filter(d => d.status !== 'active' && d.status !== 'pending').length === 0 && (
                <div className="bg-theme-background rounded-lg p-8 text-center border border-theme">
                  <span className="text-4xl">📋</span>
                  <p className="text-theme-secondary mt-2">No inactive delegations</p>
                  <p className="text-theme-tertiary text-sm mt-1">
                    Expired and revoked delegations will appear here
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Permissions Reference */}
        <div className="mt-8 pt-6 border-t border-theme">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Available Permissions</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {DELEGATION_PERMISSIONS.map((permission) => (
              <div key={permission.key} className="bg-theme-background rounded-lg p-3">
                <h4 className="font-medium text-theme-primary text-sm">{permission.label}</h4>
                <p className="text-xs text-theme-secondary mt-1">{permission.description}</p>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Modals */}
      {showCreateModal && (
        <CreateDelegationModal
          onClose={() => setShowCreateModal(false)}
          onCreate={handleCreateDelegation}
        />
      )}

      {showDetailsModal && selectedDelegation && (
        <DelegationDetailsModal
          delegation={selectedDelegation}
          onClose={() => {
            setShowDetailsModal(false);
            setSelectedDelegation(null);
          }}
          onRevoke={handleRevokeDelegation}
          onUpdate={loadDelegations}
        />
      )}

      {showRequestModal && selectedRequest && (
        <DelegationRequestModal
          request={selectedRequest}
          onClose={() => {
            setShowRequestModal(false);
            setSelectedRequest(null);
          }}
          onApprove={handleApproveRequest}
          onReject={handleRejectRequest}
        />
      )}
    </div>
  );
};

export default DelegationsManagement;