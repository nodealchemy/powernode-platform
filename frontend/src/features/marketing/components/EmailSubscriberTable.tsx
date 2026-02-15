import React, { useState } from 'react';
import { Search, UserPlus, Trash2 } from 'lucide-react';
import { useSubscribers } from '../hooks/useEmailLists';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';
import type { SubscriberStatus } from '../types';

interface EmailSubscriberTableProps {
  listId: string;
}

const STATUS_COLORS: Record<SubscriberStatus, string> = {
  active: 'text-theme-success',
  unsubscribed: 'text-theme-error',
  bounced: 'text-theme-warning',
  pending: 'text-theme-secondary',
};

export const EmailSubscriberTable: React.FC<EmailSubscriberTableProps> = ({ listId }) => {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<SubscriberStatus | ''>('');
  const [page, setPage] = useState(1);
  const [showAddForm, setShowAddForm] = useState(false);
  const [newEmail, setNewEmail] = useState('');
  const [newFirstName, setNewFirstName] = useState('');
  const [newLastName, setNewLastName] = useState('');

  const { subscribers, pagination, loading, error, refresh, addSubscriber, removeSubscriber } = useSubscribers({
    listId,
    page,
    perPage: 20,
    status: statusFilter || undefined,
    search: search || undefined,
  });

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await addSubscriber({
        email: newEmail,
        first_name: newFirstName || undefined,
        last_name: newLastName || undefined,
      });
      setShowAddForm(false);
      setNewEmail('');
      setNewFirstName('');
      setNewLastName('');
    } catch (err) {
      logger.error('Failed to add subscriber:', err);
    }
  };

  const handleRemove = async (subscriberId: string) => {
    try {
      await removeSubscriber(subscriberId);
    } catch (err) {
      logger.error('Failed to remove subscriber:', err);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium text-theme-primary">Subscribers</h3>
        <button onClick={() => setShowAddForm(!showAddForm)} className="btn-theme btn-theme-secondary btn-theme-sm">
          <UserPlus className="w-4 h-4 mr-1 inline" /> Add Subscriber
        </button>
      </div>

      {/* Add subscriber form */}
      {showAddForm && (
        <form onSubmit={handleAdd} className="card-theme p-4 flex flex-wrap gap-3 items-end">
          <div>
            <label className="block text-xs text-theme-secondary mb-1">Email</label>
            <input
              type="email"
              required
              value={newEmail}
              onChange={(e) => setNewEmail(e.target.value)}
              className="input-theme"
              placeholder="email@example.com"
            />
          </div>
          <div>
            <label className="block text-xs text-theme-secondary mb-1">First Name</label>
            <input
              type="text"
              value={newFirstName}
              onChange={(e) => setNewFirstName(e.target.value)}
              className="input-theme"
              placeholder="First name"
            />
          </div>
          <div>
            <label className="block text-xs text-theme-secondary mb-1">Last Name</label>
            <input
              type="text"
              value={newLastName}
              onChange={(e) => setNewLastName(e.target.value)}
              className="input-theme"
              placeholder="Last name"
            />
          </div>
          <button type="submit" className="btn-theme btn-theme-primary btn-theme-sm">Add</button>
          <button type="button" onClick={() => setShowAddForm(false)} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
        </form>
      )}

      {/* Filters */}
      <div className="flex gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
          <input
            type="text"
            placeholder="Search subscribers..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
            className="input-theme pl-10 w-full"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value as SubscriberStatus | ''); setPage(1); }}
          className="input-theme"
        >
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="unsubscribed">Unsubscribed</option>
          <option value="bounced">Bounced</option>
          <option value="pending">Pending</option>
        </select>
      </div>

      {loading ? (
        <div className="flex justify-center py-8"><LoadingSpinner /></div>
      ) : error ? (
        <div className="card-theme p-4 text-center">
          <p className="text-theme-error">{error}</p>
          <button onClick={refresh} className="btn-theme btn-theme-secondary mt-2">Retry</button>
        </div>
      ) : subscribers.length === 0 ? (
        <div className="card-theme p-8 text-center">
          <p className="text-theme-secondary">No subscribers found.</p>
        </div>
      ) : (
        <div className="card-theme overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-theme-border">
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Email</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase hidden md:table-cell">Name</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Status</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase hidden lg:table-cell">Subscribed</th>
                <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme-border">
              {subscribers.map(sub => (
                <tr key={sub.id} className="hover:bg-theme-surface-hover">
                  <td className="px-4 py-3 text-sm text-theme-primary">{sub.email}</td>
                  <td className="px-4 py-3 text-sm text-theme-secondary hidden md:table-cell">
                    {[sub.first_name, sub.last_name].filter(Boolean).join(' ') || '-'}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`text-xs font-medium capitalize ${STATUS_COLORS[sub.status]}`}>
                      {sub.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-xs text-theme-tertiary hidden lg:table-cell">
                    {new Date(sub.subscribed_at).toLocaleDateString()}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <button
                      onClick={() => handleRemove(sub.id)}
                      className="p-1 rounded hover:bg-theme-surface-hover text-theme-error"
                      title="Remove subscriber"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Pagination */}
      {pagination && pagination.total_pages > 1 && (
        <div className="flex items-center justify-between">
          <p className="text-sm text-theme-secondary">
            Page {page} of {pagination.total_pages} ({pagination.total_count} total)
          </p>
          <div className="flex gap-2">
            <button
              disabled={page <= 1}
              onClick={() => setPage(p => p - 1)}
              className="btn-theme btn-theme-secondary btn-theme-sm disabled:opacity-50"
            >
              Previous
            </button>
            <button
              disabled={page >= pagination.total_pages}
              onClick={() => setPage(p => p + 1)}
              className="btn-theme btn-theme-secondary btn-theme-sm disabled:opacity-50"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
