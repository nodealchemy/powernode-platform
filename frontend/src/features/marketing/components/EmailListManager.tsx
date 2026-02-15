import React, { useState } from 'react';
import { Mail, Plus, Trash2, Upload, Users } from 'lucide-react';
import { useEmailLists } from '../hooks/useEmailLists';
import { EmailSubscriberTable } from './EmailSubscriberTable';
import { EmailListImportModal } from './EmailListImportModal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';
import type { EmailListFormData } from '../types';

export const EmailListManager: React.FC = () => {
  const [search, setSearch] = useState('');
  const [selectedListId, setSelectedListId] = useState<string | null>(null);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [showImportModal, setShowImportModal] = useState(false);
  const [importListId, setImportListId] = useState<string | null>(null);

  const { emailLists, loading, error, refresh, createList, deleteList, importSubscribers } = useEmailLists({
    search: search || undefined,
  });

  const [formData, setFormData] = useState<EmailListFormData>({
    name: '',
    description: '',
    tags: [],
    double_opt_in: true,
  });
  const [saving, setSaving] = useState(false);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      setSaving(true);
      await createList(formData);
      setShowCreateForm(false);
      setFormData({ name: '', description: '', tags: [], double_opt_in: true });
    } catch (err) {
      logger.error('Failed to create email list:', err);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    try {
      await deleteList(id);
      if (selectedListId === id) setSelectedListId(null);
    } catch (err) {
      logger.error('Failed to delete email list:', err);
    }
  };

  const handleImport = async (file: File) => {
    if (!importListId) return;
    try {
      const result = await importSubscribers(importListId, file);
      setShowImportModal(false);
      setImportListId(null);
      return result;
    } catch (err) {
      logger.error('Failed to import subscribers:', err);
      throw err;
    }
  };

  if (loading && emailLists.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner />
      </div>
    );
  }

  if (error) {
    return (
      <div className="card-theme p-6 text-center">
        <p className="text-theme-error">{error}</p>
        <button onClick={refresh} className="btn-theme btn-theme-secondary mt-4">Retry</button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Search */}
      <div className="flex items-center gap-4">
        <input
          type="text"
          placeholder="Search lists..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="input-theme flex-1"
        />
      </div>

      {/* Create Form */}
      {showCreateForm && (
        <form onSubmit={handleCreate} className="card-theme p-6 space-y-4">
          <h3 className="text-lg font-medium text-theme-primary">New Email List</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
              <input
                type="text"
                required
                value={formData.name}
                onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                className="input-theme w-full"
                placeholder="List name"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
              <input
                type="text"
                value={formData.description}
                onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
                className="input-theme w-full"
                placeholder="Optional description"
              />
            </div>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="double-opt-in"
              checked={formData.double_opt_in}
              onChange={(e) => setFormData(prev => ({ ...prev, double_opt_in: e.target.checked }))}
              className="rounded border-theme-border"
            />
            <label htmlFor="double-opt-in" className="text-sm text-theme-secondary">
              Require double opt-in
            </label>
          </div>
          <div className="flex justify-end gap-3">
            <button type="button" onClick={() => setShowCreateForm(false)} className="btn-theme btn-theme-secondary">
              Cancel
            </button>
            <button type="submit" disabled={saving} className="btn-theme btn-theme-primary">
              {saving ? 'Creating...' : 'Create List'}
            </button>
          </div>
        </form>
      )}

      {/* Lists Grid */}
      {emailLists.length === 0 && !showCreateForm ? (
        <div className="card-theme p-12 text-center">
          <Mail className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No email lists yet</h3>
          <p className="text-theme-secondary mb-4">Create your first email list to start collecting subscribers.</p>
          <button onClick={() => setShowCreateForm(true)} className="btn-theme btn-theme-primary">
            <Plus className="w-4 h-4 mr-2 inline" /> Create List
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {emailLists.map(list => (
            <div
              key={list.id}
              className={`card-theme p-4 cursor-pointer transition-colors ${
                selectedListId === list.id ? 'ring-2 ring-theme-primary' : 'hover:bg-theme-surface-hover'
              }`}
              onClick={() => setSelectedListId(selectedListId === list.id ? null : list.id)}
            >
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-3">
                  <div className="p-2 rounded-lg bg-theme-info bg-opacity-10">
                    <Mail className="w-5 h-5 text-theme-info" />
                  </div>
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">{list.name}</h4>
                    {list.description && (
                      <p className="text-xs text-theme-tertiary mt-0.5">{list.description}</p>
                    )}
                  </div>
                </div>
                <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
                  <button
                    onClick={() => { setImportListId(list.id); setShowImportModal(true); }}
                    className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary"
                    title="Import subscribers"
                  >
                    <Upload className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(list.id)}
                    className="p-1 rounded hover:bg-theme-surface-hover text-theme-error"
                    title="Delete list"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
              <div className="flex items-center gap-4 mt-3 pt-3 border-t border-theme-border">
                <div className="flex items-center gap-1">
                  <Users className="w-3.5 h-3.5 text-theme-tertiary" />
                  <span className="text-xs text-theme-secondary">{list.subscriber_count} subscribers</span>
                </div>
                <span className="text-xs text-theme-tertiary">
                  {list.active_subscriber_count} active
                </span>
              </div>
              {list.tags.length > 0 && (
                <div className="flex gap-1 mt-2 flex-wrap">
                  {list.tags.map(tag => (
                    <span key={tag} className="text-[10px] px-1.5 py-0.5 rounded bg-theme-surface text-theme-tertiary">
                      {tag}
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Subscriber Table */}
      {selectedListId && (
        <div className="mt-6">
          <EmailSubscriberTable listId={selectedListId} />
        </div>
      )}

      {/* Import Modal */}
      {showImportModal && importListId && (
        <EmailListImportModal
          onImport={handleImport}
          onClose={() => { setShowImportModal(false); setImportListId(null); }}
        />
      )}
    </div>
  );
};
