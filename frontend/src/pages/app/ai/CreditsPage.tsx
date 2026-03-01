// Credits Management Page - Prepaid AI Credit System
import React, { useState, useEffect } from 'react';
import {
  Coins, ArrowRightLeft, ShoppingCart,
  Search, Filter, DollarSign, TrendingUp, Store, Check, X
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  creditsApi,
  CreditBalance,
  CreditTransaction,
  CreditPack,
  CreditTransfer,
  UsageAnalytics,
  ResellerStats
} from '@/shared/services/ai/CreditsApiService';

// Type guard for API errors
interface ApiErrorResponse {
  response?: {
    data?: {
      error?: string;
    };
  };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) {
    return error.response?.data?.error || fallback;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}

type TabType = 'overview' | 'purchase' | 'transactions' | 'transfers' | 'reseller';

export const CreditsContent: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('overview');
  const [balance, setBalance] = useState<CreditBalance | null>(null);
  const [transactions, setTransactions] = useState<CreditTransaction[]>([]);
  const [transactionCount, setTransactionCount] = useState(0);
  const [packs, setPacks] = useState<CreditPack[]>([]);
  const [transfers] = useState<CreditTransfer[]>([]);
  const [usageAnalytics, setUsageAnalytics] = useState<UsageAnalytics | null>(null);
  const [resellerStats, setResellerStats] = useState<ResellerStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [purchaseLoading, setPurchaseLoading] = useState<string | null>(null);
  const [typeFilter, setTypeFilter] = useState<string>('all');

  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      loadData();
    }
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      setLoading(true);
      const [balanceRes, transactionsRes, packsRes, analyticsRes] = await Promise.all([
        creditsApi.getBalance(),
        creditsApi.getTransactions(),
        creditsApi.getPacks(),
        creditsApi.getUsageAnalytics()
      ]);
      setBalance(balanceRes);
      setTransactions(transactionsRes.transactions || []);
      setTransactionCount(transactionsRes.total_count || 0);
      setPacks(packsRes.packs || []);
      setUsageAnalytics(analyticsRes);

      // Load reseller stats if user is a reseller
      if (balanceRes.is_reseller) {
        try {
          const resellerRes = await creditsApi.getResellerStats();
          setResellerStats(resellerRes);
        } catch {
          // Reseller stats may not be available
        }
      }
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load credits data')
      }));
    } finally {
      setLoading(false);
    }
  };

  const handlePurchase = async (packId: string) => {
    try {
      setPurchaseLoading(packId);
      const purchase = await creditsApi.createPurchase({ pack_id: packId, quantity: 1 });
      await creditsApi.completePurchase(purchase.id, `web_${Date.now()}`);
      dispatch(addNotification({
        type: 'success',
        message: 'Credits purchased successfully'
      }));
      loadData();
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to purchase credits')
      }));
    } finally {
      setPurchaseLoading(null);
    }
  };

  const handleTransferAction = async (transferId: string, action: 'approve' | 'cancel') => {
    try {
      if (action === 'approve') {
        await creditsApi.approveTransfer(transferId);
      } else {
        await creditsApi.cancelTransfer(transferId, 'Cancelled by user');
      }
      dispatch(addNotification({
        type: 'success',
        message: `Transfer ${action === 'approve' ? 'approved' : 'cancelled'}`
      }));
      loadData();
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, `Failed to ${action} transfer`)
      }));
    }
  };

  const handleEnableReseller = async () => {
    try {
      await creditsApi.enableReseller(10);
      dispatch(addNotification({
        type: 'success',
        message: 'Reseller mode enabled'
      }));
      loadData();
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to enable reseller mode')
      }));
    }
  };

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'completed': return 'text-theme-success bg-theme-success/10';
      case 'pending': return 'text-theme-warning bg-theme-warning/10';
      case 'failed': return 'text-theme-danger bg-theme-danger/10';
      case 'cancelled': return 'text-theme-secondary bg-theme-surface';
      case 'approved': return 'text-theme-info bg-theme-info/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const getTransactionTypeColor = (type: string): string => {
    switch (type) {
      case 'purchase': return 'text-theme-success bg-theme-success/10';
      case 'deduction': return 'text-theme-danger bg-theme-danger/10';
      case 'transfer_in': return 'text-theme-info bg-theme-info/10';
      case 'transfer_out': return 'text-theme-warning bg-theme-warning/10';
      case 'refund': return 'text-theme-accent bg-theme-accent/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const tabs = [
    { id: 'overview' as TabType, label: 'Overview', icon: Coins },
    { id: 'purchase' as TabType, label: 'Purchase', icon: ShoppingCart },
    { id: 'transactions' as TabType, label: 'Transactions', icon: DollarSign },
    { id: 'transfers' as TabType, label: 'Transfers', icon: ArrowRightLeft },
    { id: 'reseller' as TabType, label: 'Reseller', icon: Store }
  ];

  const filteredTransactions = typeFilter === 'all'
    ? transactions
    : transactions.filter(t => t.transaction_type === typeFilter);

  return (
    <div className="space-y-6">
      {/* Balance Card */}
      {balance && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Available Balance</p>
                <p className="text-2xl font-bold text-theme-primary">{balance.available.toLocaleString()}</p>
              </div>
              <Coins className="h-8 w-8 text-theme-accent" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">{balance.reserved.toLocaleString()} reserved</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Balance</p>
                <p className="text-2xl font-bold text-theme-primary">{balance.balance.toLocaleString()}</p>
              </div>
              <DollarSign className="h-8 w-8 text-theme-success" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">Lifetime: {balance.lifetime_purchased.toLocaleString()}</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Lifetime Used</p>
                <p className="text-2xl font-bold text-theme-warning">{balance.lifetime_used.toLocaleString()}</p>
              </div>
              <TrendingUp className="h-8 w-8 text-theme-warning" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">
              {balance.last_usage_at ? `Last: ${new Date(balance.last_usage_at).toLocaleDateString()}` : 'No usage yet'}
            </p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Reseller</p>
                <p className="text-2xl font-bold text-theme-primary">{balance.is_reseller ? 'Active' : 'Inactive'}</p>
              </div>
              <Store className="h-8 w-8 text-theme-info" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">
              {balance.last_purchase_at ? `Last purchase: ${new Date(balance.last_purchase_at).toLocaleDateString()}` : 'No purchases'}
            </p>
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex gap-4">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2 border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-accent text-theme-accent'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon size={16} />
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading credits data...</p>
        </div>
      ) : (
        <>
          {/* Overview Tab */}
          {activeTab === 'overview' && (
            <div className="space-y-6">
              {/* Usage Analytics */}
              {usageAnalytics && (
                <div className="bg-theme-surface border border-theme rounded-lg p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Usage Analytics</h3>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    {Object.entries(usageAnalytics).filter(([key]) => typeof usageAnalytics[key as keyof UsageAnalytics] === 'number').slice(0, 6).map(([key, value]) => (
                      <div key={key} className="p-3 bg-theme-bg rounded-lg">
                        <p className="text-xs text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
                        <p className="text-lg font-semibold text-theme-primary">{typeof value === 'number' ? value.toLocaleString() : String(value)}</p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Recent Transactions */}
              <div className="bg-theme-surface border border-theme rounded-lg p-6">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-semibold text-theme-primary">Recent Transactions</h3>
                  <button
                    onClick={() => setActiveTab('transactions')}
                    className="text-sm text-theme-accent hover:underline"
                  >
                    View All ({transactionCount})
                  </button>
                </div>
                {transactions.length === 0 ? (
                  <p className="text-theme-secondary text-center py-4">No transactions yet</p>
                ) : (
                  <div className="space-y-3">
                    {transactions.slice(0, 5).map(tx => (
                      <div key={tx.id} className="flex items-center justify-between p-3 bg-theme-bg rounded-lg">
                        <div className="flex items-center gap-3">
                          <span className={`px-2 py-1 text-xs rounded ${getTransactionTypeColor(tx.transaction_type)}`}>
                            {tx.transaction_type}
                          </span>
                          <span className="text-sm text-theme-primary">{tx.description || 'Transaction'}</span>
                        </div>
                        <div className="text-right">
                          <span className={`text-sm font-medium ${tx.amount >= 0 ? 'text-theme-success' : 'text-theme-danger'}`}>
                            {tx.amount >= 0 ? '+' : ''}{tx.amount.toLocaleString()}
                          </span>
                          <p className="text-xs text-theme-secondary">{new Date(tx.created_at).toLocaleDateString()}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Purchase Tab */}
          {activeTab === 'purchase' && (
            <div className="space-y-4">
              {packs.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <ShoppingCart size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No credit packs available</h3>
                  <p className="text-theme-secondary">Credit packs will appear here when configured</p>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {packs.map(pack => (
                    <div
                      key={pack.id}
                      className={`bg-theme-surface border rounded-lg p-6 transition-colors ${
                        pack.is_featured ? 'border-theme-accent ring-1 ring-theme-accent' : 'border-theme hover:border-theme-accent/50'
                      }`}
                    >
                      {pack.is_featured && (
                        <span className="inline-block px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded mb-3">Featured</span>
                      )}
                      <h3 className="text-lg font-semibold text-theme-primary mb-1">{pack.name}</h3>
                      <p className="text-sm text-theme-secondary mb-4">{pack.description || `${pack.credits.toLocaleString()} credits`}</p>
                      <div className="mb-4">
                        <p className="text-3xl font-bold text-theme-primary">${pack.price_usd.toFixed(2)}</p>
                        <p className="text-xs text-theme-secondary">${pack.effective_price_per_credit.toFixed(4)} per credit</p>
                      </div>
                      <div className="flex items-center justify-between mb-4">
                        <span className="text-sm text-theme-primary">{pack.credits.toLocaleString()} credits</span>
                        {pack.bonus_credits > 0 && (
                          <span className="text-sm text-theme-success">+{pack.bonus_credits.toLocaleString()} bonus</span>
                        )}
                      </div>
                      <button
                        onClick={() => handlePurchase(pack.id)}
                        disabled={purchaseLoading === pack.id}
                        className="w-full btn-theme btn-theme-primary"
                      >
                        {purchaseLoading === pack.id ? 'Processing...' : 'Purchase'}
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Transactions Tab */}
          {activeTab === 'transactions' && (
            <div className="space-y-4">
              {/* Filter */}
              <div className="flex flex-wrap gap-4 mb-4">
                <div className="flex-1 min-w-64">
                  <div className="relative">
                    <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-secondary" />
                    <input
                      type="search"
                      placeholder="Search transactions..."
                      className="w-full pl-10 pr-4 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
                    />
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Filter size={16} className="text-theme-secondary" />
                  <select
                    value={typeFilter}
                    onChange={(e) => setTypeFilter(e.target.value)}
                    className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
                  >
                    <option value="all">All Types</option>
                    <option value="purchase">Purchase</option>
                    <option value="deduction">Deduction</option>
                    <option value="transfer_in">Transfer In</option>
                    <option value="transfer_out">Transfer Out</option>
                    <option value="refund">Refund</option>
                  </select>
                </div>
              </div>

              {filteredTransactions.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <DollarSign size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No transactions</h3>
                  <p className="text-theme-secondary">Credit transactions will appear here</p>
                </div>
              ) : (
                <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
                  <table className="w-full">
                    <thead>
                      <tr className="border-b border-theme bg-theme-bg">
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Type</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Description</th>
                        <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Amount</th>
                        <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Balance After</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Status</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-theme">
                      {filteredTransactions.map(tx => (
                        <tr key={tx.id} className="hover:bg-theme-surface-hover transition-colors">
                          <td className="px-4 py-3">
                            <span className={`px-2 py-1 text-xs rounded ${getTransactionTypeColor(tx.transaction_type)}`}>
                              {tx.transaction_type}
                            </span>
                          </td>
                          <td className="px-4 py-3 text-sm text-theme-primary">{tx.description || '-'}</td>
                          <td className={`px-4 py-3 text-sm text-right font-medium ${tx.amount >= 0 ? 'text-theme-success' : 'text-theme-danger'}`}>
                            {tx.amount >= 0 ? '+' : ''}{tx.amount.toLocaleString()}
                          </td>
                          <td className="px-4 py-3 text-sm text-right text-theme-primary">{tx.balance_after.toLocaleString()}</td>
                          <td className="px-4 py-3">
                            <span className={`px-2 py-1 text-xs rounded ${getStatusColor(tx.status)}`}>{tx.status}</span>
                          </td>
                          <td className="px-4 py-3 text-sm text-theme-secondary">{new Date(tx.created_at).toLocaleString()}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          {/* Transfers Tab */}
          {activeTab === 'transfers' && (
            <div className="space-y-4">
              {transfers.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <ArrowRightLeft size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No transfers</h3>
                  <p className="text-theme-secondary mb-6">Transfer credits between accounts</p>
                  <button className="btn-theme btn-theme-primary">
                    Create Transfer
                  </button>
                </div>
              ) : (
                transfers.map(transfer => (
                  <div key={transfer.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <ArrowRightLeft size={16} className="text-theme-accent" />
                        <span className="font-medium text-theme-primary">{transfer.amount.toLocaleString()} credits</span>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(transfer.status)}`}>
                          {transfer.status}
                        </span>
                      </div>
                      {transfer.status === 'pending' && (
                        <div className="flex gap-2">
                          <button
                            onClick={() => handleTransferAction(transfer.id, 'approve')}
                            className="btn-theme btn-theme-success btn-theme-sm"
                          >
                            <Check size={14} className="mr-1" /> Approve
                          </button>
                          <button
                            onClick={() => handleTransferAction(transfer.id, 'cancel')}
                            className="btn-theme btn-theme-danger btn-theme-sm"
                          >
                            <X size={14} className="mr-1" /> Cancel
                          </button>
                        </div>
                      )}
                    </div>
                    <p className="text-sm text-theme-secondary">
                      {transfer.description || 'Credit transfer'}
                    </p>
                    <p className="text-xs text-theme-secondary mt-1">
                      {new Date(transfer.created_at).toLocaleString()}
                    </p>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Reseller Tab */}
          {activeTab === 'reseller' && (
            <div className="space-y-6">
              {!balance?.is_reseller ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Store size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">Become a Reseller</h3>
                  <p className="text-theme-secondary mb-6">Enable reseller mode to purchase credits at discounted rates and distribute them</p>
                  <button
                    onClick={handleEnableReseller}
                    className="btn-theme btn-theme-primary"
                  >
                    Enable Reseller Mode
                  </button>
                </div>
              ) : resellerStats ? (
                <div className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    {Object.entries(resellerStats).filter(([, value]) => typeof value === 'number').slice(0, 6).map(([key, value]) => (
                      <div key={key} className="bg-theme-surface border border-theme rounded-lg p-4">
                        <p className="text-sm text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
                        <p className="text-2xl font-bold text-theme-primary">{typeof value === 'number' ? value.toLocaleString() : String(value)}</p>
                      </div>
                    ))}
                  </div>
                </div>
              ) : (
                <div className="text-center py-8 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Reseller mode is active. No stats available yet.</p>
                </div>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
};

const CreditsPage: React.FC = () => {
  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Credits' }
  ];

  return (
    <PageContainer
      title="Credits Management"
      description="Manage prepaid AI credits, purchases, transfers, and usage analytics"
      breadcrumbs={breadcrumbs}
    >
      <CreditsContent />
    </PageContainer>
  );
};

export default CreditsPage;
