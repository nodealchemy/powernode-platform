import { useState, useEffect } from 'react';
import {
  X, GitCommit, User, Clock, FileText, ExternalLink,
  Copy, Check, AlertCircle, Loader2, Plus, Minus, Shield, ShieldCheck,
  ChevronDown, ChevronRight
} from 'lucide-react';
import { GitCommitDetail, GitCommitFile } from '../types';
import { gitProvidersApi } from '../services/gitProvidersApi';

interface CommitDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  repositoryId: string;
  sha: string;
  repositoryName?: string;
}

/**
 * FileChangeItem - Displays a single file change with expandable diff
 */
function FileChangeItem({ file, defaultExpanded = false }: { file: GitCommitFile; defaultExpanded?: boolean }) {
  const [expanded, setExpanded] = useState(defaultExpanded);

  const statusConfig: Record<string, { bg: string; text: string; label: string }> = {
    added: { bg: 'bg-theme-success/10', text: 'text-theme-success', label: 'Added' },
    removed: { bg: 'bg-theme-danger/10', text: 'text-theme-danger', label: 'Deleted' },
    modified: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', label: 'Modified' },
    renamed: { bg: 'bg-theme-interactive-primary/10', text: 'text-theme-interactive-primary', label: 'Renamed' },
    copied: { bg: 'bg-theme-info/10', text: 'text-theme-info', label: 'Copied' },
  };

  const config = statusConfig[file.status] || statusConfig.modified;
  const hasPatch = file.patch && file.patch.trim().length > 0;

  return (
    <div className="border border-theme rounded-lg overflow-hidden">
      {/* File header */}
      <div
        className={`flex items-center justify-between px-4 py-3 bg-theme-surface-secondary ${hasPatch ? 'cursor-pointer hover:bg-theme-surface-tertiary' : ''}`}
        onClick={() => hasPatch && setExpanded(!expanded)}
      >
        <div className="flex items-center gap-3 min-w-0 flex-1">
          {hasPatch ? (
            <button className="text-theme-secondary hover:text-theme-primary flex-shrink-0">
              {expanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
            </button>
          ) : (
            <FileText className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
          )}
          <span className="font-mono text-sm text-theme-primary truncate">
            {file.previous_filename ? (
              <>
                <span className="text-theme-tertiary">{file.previous_filename}</span>
                <span className="text-theme-secondary mx-2">→</span>
                {file.filename}
              </>
            ) : (
              file.filename
            )}
          </span>
          <span className={`px-2 py-0.5 text-xs font-medium rounded flex-shrink-0 ${config.bg} ${config.text}`}>
            {config.label}
          </span>
        </div>
        <div className="flex items-center gap-3 text-sm flex-shrink-0 ml-4">
          {file.additions > 0 && (
            <span className="text-theme-success flex items-center gap-1">
              <Plus className="w-3 h-3" />
              {file.additions}
            </span>
          )}
          {file.deletions > 0 && (
            <span className="text-theme-danger flex items-center gap-1">
              <Minus className="w-3 h-3" />
              {file.deletions}
            </span>
          )}
        </div>
      </div>

      {/* Patch content */}
      {expanded && hasPatch && (
        <div className="overflow-x-auto bg-theme-surface border-t border-theme">
          <pre className="p-4 text-xs font-mono leading-relaxed">
            {file.patch?.split('\n').map((line, i) => {
              let lineClass = 'text-theme-secondary';
              let bgClass = '';
              if (line.startsWith('+') && !line.startsWith('+++')) {
                lineClass = 'text-theme-success';
                bgClass = 'bg-theme-success/10';
              } else if (line.startsWith('-') && !line.startsWith('---')) {
                lineClass = 'text-theme-danger';
                bgClass = 'bg-theme-danger/10';
              } else if (line.startsWith('@@')) {
                lineClass = 'text-theme-info';
                bgClass = 'bg-theme-info/10';
              }
              return (
                <div key={i} className={`${bgClass} ${lineClass} px-2 -mx-2`}>
                  {line || ' '}
                </div>
              );
            })}
          </pre>
        </div>
      )}
    </div>
  );
}

/**
 * CommitDetailModal - Shows comprehensive commit information in unified view
 * Displays commit info, stats, and file changes with inline diffs
 */
export function CommitDetailModal({
  isOpen,
  onClose,
  repositoryId,
  sha,
  repositoryName,
}: CommitDetailModalProps) {
  const [commit, setCommit] = useState<GitCommitDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [allExpanded, setAllExpanded] = useState(false);

  useEffect(() => {
    if (isOpen && sha) {
      fetchCommit();
    }
    return () => {
      setCommit(null);
      setError(null);
      setAllExpanded(false);
    };
  }, [isOpen, repositoryId, sha]);

  const fetchCommit = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await gitProvidersApi.getCommit(repositoryId, sha);
      setCommit(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load commit');
    } finally {
      setLoading(false);
    }
  };

  const handleCopySha = async () => {
    await navigator.clipboard.writeText(sha);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleString('en-US', {
      weekday: 'short',
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[60] overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 transition-opacity"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-4xl bg-theme-surface rounded-xl shadow-2xl overflow-hidden">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <GitCommit className="w-5 h-5 text-theme-secondary" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  Commit Details
                </h2>
                {repositoryName && (
                  <p className="text-sm text-theme-secondary">{repositoryName}</p>
                )}
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="flex items-center gap-2 px-3 py-1.5 bg-theme-surface-secondary rounded-lg">
                <code className="text-sm font-mono text-theme-primary">
                  {sha.substring(0, 7)}
                </code>
                <button
                  onClick={handleCopySha}
                  className="text-theme-tertiary hover:text-theme-primary"
                  title="Copy full SHA"
                >
                  {copied ? (
                    <Check className="w-4 h-4 text-theme-success" />
                  ) : (
                    <Copy className="w-4 h-4" />
                  )}
                </button>
              </div>
              <button
                onClick={onClose}
                className="p-2 text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-secondary rounded-lg"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
          </div>

          {/* Content */}
          <div className="p-6 max-h-[75vh] overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="w-8 h-8 animate-spin text-theme-accent" />
              </div>
            ) : error ? (
              <div className="flex flex-col items-center justify-center py-12 text-theme-danger">
                <AlertCircle className="w-12 h-12 mb-4" />
                <p className="text-lg font-medium">Failed to load commit</p>
                <p className="text-sm text-theme-secondary mt-1">{error}</p>
                <button
                  onClick={fetchCommit}
                  className="mt-4 px-4 py-2 bg-theme-accent text-white rounded-lg hover:bg-theme-accent/90"
                >
                  Retry
                </button>
              </div>
            ) : commit ? (
              <div className="space-y-6">
                {/* Commit Message */}
                <div>
                  <h3 className="text-xl font-semibold text-theme-primary">
                    {commit.title}
                  </h3>
                  {commit.body && (
                    <pre className="mt-3 p-4 bg-theme-surface-secondary rounded-lg text-sm text-theme-secondary whitespace-pre-wrap font-mono">
                      {commit.body}
                    </pre>
                  )}
                </div>

                {/* Author & Stats Row */}
                <div className="flex flex-wrap items-center gap-6 pb-4 border-b border-theme">
                  {/* Author */}
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-theme-surface-secondary flex items-center justify-center overflow-hidden">
                      {commit.author.avatar_url ? (
                        <img
                          src={commit.author.avatar_url}
                          alt={commit.author.name}
                          className="w-8 h-8 rounded-full"
                        />
                      ) : (
                        <User className="w-4 h-4 text-theme-secondary" />
                      )}
                    </div>
                    <div>
                      <p className="text-sm font-medium text-theme-primary">
                        {commit.author.name}
                      </p>
                      <p className="text-xs text-theme-tertiary flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {formatDate(commit.authored_date)}
                      </p>
                    </div>
                  </div>

                  {/* Stats */}
                  <div className="flex items-center gap-4 ml-auto">
                    <div className="flex items-center gap-2 text-sm">
                      <FileText className="w-4 h-4 text-theme-tertiary" />
                      <span className="text-theme-secondary">
                        {commit.stats.files_changed} file{commit.stats.files_changed !== 1 ? 's' : ''}
                      </span>
                    </div>
                    <div className="flex items-center gap-1 text-sm text-theme-success">
                      <Plus className="w-4 h-4" />
                      <span>{commit.stats.additions}</span>
                    </div>
                    <div className="flex items-center gap-1 text-sm text-theme-danger">
                      <Minus className="w-4 h-4" />
                      <span>{commit.stats.deletions}</span>
                    </div>
                    {commit.is_verified && (
                      <div className="flex items-center gap-1 text-sm text-theme-success" title="Verified signature">
                        <ShieldCheck className="w-4 h-4" />
                      </div>
                    )}
                    {!commit.is_verified && (
                      <div className="flex items-center gap-1 text-sm text-theme-tertiary" title="Not signed">
                        <Shield className="w-4 h-4" />
                      </div>
                    )}
                  </div>
                </div>

                {/* Parent commits */}
                {commit.parent_shas.length > 0 && (
                  <div className="flex items-center gap-2 text-sm">
                    <span className="text-theme-tertiary">
                      {commit.is_merge ? 'Parents:' : 'Parent:'}
                    </span>
                    {commit.parent_shas.map((parentSha) => (
                      <code
                        key={parentSha}
                        className="px-2 py-0.5 bg-theme-surface-secondary rounded text-xs font-mono text-theme-secondary"
                      >
                        {parentSha.substring(0, 7)}
                      </code>
                    ))}
                    {commit.web_url && (
                      <a
                        href={commit.web_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="ml-auto flex items-center gap-1 text-theme-accent hover:underline"
                      >
                        <ExternalLink className="w-3 h-3" />
                        View on Git
                      </a>
                    )}
                  </div>
                )}

                {/* Files Changed */}
                <div>
                  <div className="flex items-center justify-between mb-3">
                    <h4 className="text-sm font-medium text-theme-secondary">
                      Files Changed ({commit.files.length})
                    </h4>
                    {commit.files.some(f => f.patch) && (
                      <button
                        onClick={() => setAllExpanded(!allExpanded)}
                        className="text-xs text-theme-accent hover:underline"
                      >
                        {allExpanded ? 'Collapse all' : 'Expand all'}
                      </button>
                    )}
                  </div>

                  {commit.files.length === 0 ? (
                    <p className="text-center py-6 text-theme-secondary bg-theme-surface-secondary rounded-lg">
                      No file changes available
                    </p>
                  ) : (
                    <div className="space-y-2">
                      {commit.files.map((file, index) => (
                        <FileChangeItem
                          key={`${file.filename}-${index}`}
                          file={file}
                          defaultExpanded={allExpanded}
                        />
                      ))}
                    </div>
                  )}
                </div>
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}

export default CommitDetailModal;
