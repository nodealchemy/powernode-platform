import React, { useState, useEffect } from 'react';
import { X, GitCompare, Search } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { sbomsApi } from '../../services/sbomsApi';

interface Sbom {
  id: string;
  name: string;
  version: string;
  created_at: string;
}

interface CreateDiffModalProps {
  currentSbomId: string;
  currentSbomName: string;
  onClose: () => void;
  onCreateDiff: (compareSbomId: string) => Promise<void>;
}

export const CreateDiffModal: React.FC<CreateDiffModalProps> = ({
  currentSbomId,
  currentSbomName,
  onClose,
  onCreateDiff,
}) => {
  const [sboms, setSboms] = useState<Sbom[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [selectedSbomId, setSelectedSbomId] = useState<string | null>(null);
  const [search, setSearch] = useState('');

  useEffect(() => {
    const fetchSboms = async () => {
      try {
        setLoading(true);
        const result = await sbomsApi.list({ per_page: 100, status: 'completed' });
        setSboms(result.sboms.filter(s => s.id !== currentSbomId));
      } catch {
        // Error handled silently
      } finally {
        setLoading(false);
      }
    };
    fetchSboms();
  }, [currentSbomId]);

  const filteredSboms = sboms.filter(sbom =>
    sbom.name.toLowerCase().includes(search.toLowerCase())
  );

  const handleCreate = async () => {
    if (!selectedSbomId) return;
    try {
      setCreating(true);
      await onCreateDiff(selectedSbomId);
      onClose();
    } finally {
      setCreating(false);
    }
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      <div className="relative z-10 w-full max-w-lg bg-theme-surface rounded-lg shadow-xl mx-4">
        <div className="border-b border-theme px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <GitCompare className="w-5 h-5 text-theme-interactive-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">Compare SBOMs</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover">
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        <div className="p-6">
          <div className="mb-4">
            <span className="text-sm text-theme-secondary">Comparing from:</span>
            <p className="font-medium text-theme-primary">{currentSbomName}</p>
          </div>

          <div className="relative mb-4">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-secondary" />
            <input
              type="text"
              placeholder="Search SBOMs..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
          </div>

          {loading ? (
            <div className="flex justify-center py-8">
              <LoadingSpinner size="md" />
            </div>
          ) : (
            <div className="max-h-64 overflow-y-auto space-y-2">
              {filteredSboms.length === 0 ? (
                <p className="text-center py-4 text-theme-secondary">No SBOMs found</p>
              ) : (
                filteredSboms.map((sbom) => (
                  <button
                    key={sbom.id}
                    onClick={() => setSelectedSbomId(sbom.id)}
                    className={`w-full p-3 rounded-lg border text-left transition-colors ${
                      selectedSbomId === sbom.id
                        ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                        : 'border-theme hover:border-theme-border-hover'
                    }`}
                  >
                    <p className="font-medium text-theme-primary">{sbom.name}</p>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="text-xs text-theme-secondary">v{sbom.version}</span>
                      <span className="text-xs text-theme-muted">•</span>
                      <span className="text-xs text-theme-muted">{formatDate(sbom.created_at)}</span>
                    </div>
                  </button>
                ))
              )}
            </div>
          )}
        </div>

        <div className="border-t border-theme px-6 py-4 flex justify-end gap-3">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleCreate}
            disabled={!selectedSbomId || creating}
          >
            {creating ? 'Creating...' : 'Create Diff'}
          </Button>
        </div>
      </div>
    </div>
  );
};
