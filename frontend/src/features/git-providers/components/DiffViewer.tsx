import { useState } from 'react';
import { ChevronDown, ChevronRight, Plus, Minus, File, Copy, Check } from 'lucide-react';
import { GitFileDiff, GitDiffHunk, GitDiffLine } from '../types';

interface DiffViewerProps {
  files: GitFileDiff[];
  className?: string;
}

interface FileDiffProps {
  file: GitFileDiff;
  defaultExpanded?: boolean;
}

/**
 * Renders a single line of diff with proper styling
 */
function DiffLine({ line }: { line: GitDiffLine }) {
  const bgColor = {
    addition: 'bg-green-50 dark:bg-green-950/30',
    deletion: 'bg-red-50 dark:bg-red-950/30',
    context: 'bg-theme-surface',
    header: 'bg-theme-surface-secondary',
  }[line.type];

  const textColor = {
    addition: 'text-theme-success dark:text-green-400',
    deletion: 'text-theme-danger dark:text-red-400',
    context: 'text-theme-secondary',
    header: 'text-theme-secondary font-medium',
  }[line.type];

  const linePrefix = {
    addition: '+',
    deletion: '-',
    context: ' ',
    header: '',
  }[line.type];

  return (
    <tr className={`${bgColor} border-b border-theme/5`}>
      {/* Old line number */}
      <td className="w-12 px-2 text-right text-xs text-theme-tertiary select-none font-mono border-r border-theme/10">
        {line.old_line_number || ''}
      </td>
      {/* New line number */}
      <td className="w-12 px-2 text-right text-xs text-theme-tertiary select-none font-mono border-r border-theme/10">
        {line.new_line_number || ''}
      </td>
      {/* Line content */}
      <td className={`px-4 py-0.5 font-mono text-sm whitespace-pre ${textColor}`}>
        <span className="select-none mr-2">{linePrefix}</span>
        {line.content}
      </td>
    </tr>
  );
}

/**
 * Renders a diff hunk with its header and lines
 */
function DiffHunk({ hunk, index }: { hunk: GitDiffHunk; index: number }) {
  return (
    <tbody>
      {/* Hunk header */}
      <tr className="bg-blue-50 dark:bg-blue-950/30">
        <td colSpan={3} className="px-4 py-1 text-xs font-mono text-theme-info dark:text-blue-400">
          {hunk.header}
        </td>
      </tr>
      {/* Hunk lines */}
      {hunk.lines.map((line, lineIndex) => (
        <DiffLine key={`${index}-${lineIndex}`} line={line} />
      ))}
    </tbody>
  );
}

/**
 * Renders a single file diff with expandable content
 */
function FileDiff({ file, defaultExpanded = true }: FileDiffProps) {
  const [expanded, setExpanded] = useState(defaultExpanded);
  const [copied, setCopied] = useState(false);

  const statusColor = {
    added: 'text-theme-success dark:text-green-400 bg-green-100 dark:bg-green-900/30',
    removed: 'text-theme-danger dark:text-red-400 bg-red-100 dark:bg-red-900/30',
    modified: 'text-theme-warning dark:text-yellow-400 bg-yellow-100 dark:bg-yellow-900/30',
    renamed: 'text-theme-interactive-primary dark:text-purple-400 bg-purple-100 dark:bg-purple-900/30',
    copied: 'text-theme-info dark:text-blue-400 bg-blue-100 dark:bg-blue-900/30',
  }[file.status] || 'text-theme-secondary bg-theme-surface-secondary';

  const statusLabel = {
    added: 'Added',
    removed: 'Deleted',
    modified: 'Modified',
    renamed: 'Renamed',
    copied: 'Copied',
  }[file.status] || file.status;

  const handleCopyPath = async () => {
    await navigator.clipboard.writeText(file.filename);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="border border-theme rounded-lg overflow-hidden mb-4">
      {/* File header */}
      <div
        className="flex items-center justify-between px-4 py-3 bg-theme-surface-secondary cursor-pointer hover:bg-theme-surface-tertiary"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center gap-3">
          <button className="text-theme-secondary hover:text-theme-primary">
            {expanded ? (
              <ChevronDown className="w-4 h-4" />
            ) : (
              <ChevronRight className="w-4 h-4" />
            )}
          </button>
          <File className="w-4 h-4 text-theme-tertiary" />
          <span className="font-mono text-sm text-theme-primary">
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
          <span className={`px-2 py-0.5 text-xs font-medium rounded ${statusColor}`}>
            {statusLabel}
          </span>
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleCopyPath();
            }}
            className="text-theme-tertiary hover:text-theme-secondary"
            title="Copy path"
          >
            {copied ? (
              <Check className="w-4 h-4 text-theme-success" />
            ) : (
              <Copy className="w-4 h-4" />
            )}
          </button>
        </div>
        <div className="flex items-center gap-4 text-sm">
          {file.additions > 0 && (
            <span className="flex items-center gap-1 text-theme-success dark:text-green-400">
              <Plus className="w-3 h-3" />
              {file.additions}
            </span>
          )}
          {file.deletions > 0 && (
            <span className="flex items-center gap-1 text-theme-danger dark:text-red-400">
              <Minus className="w-3 h-3" />
              {file.deletions}
            </span>
          )}
        </div>
      </div>

      {/* File content */}
      {expanded && (
        <div className="overflow-x-auto">
          {file.is_binary ? (
            <div className="px-4 py-8 text-center text-theme-secondary">
              Binary file not shown
            </div>
          ) : file.is_large ? (
            <div className="px-4 py-8 text-center text-theme-secondary">
              Large diff not shown. View raw patch to see changes.
            </div>
          ) : file.hunks.length === 0 ? (
            <div className="px-4 py-8 text-center text-theme-secondary">
              No changes to display
            </div>
          ) : (
            <table className="w-full border-collapse">
              {file.hunks.map((hunk, index) => (
                <DiffHunk key={index} hunk={hunk} index={index} />
              ))}
            </table>
          )}
        </div>
      )}
    </div>
  );
}

/**
 * DiffViewer - Displays code diffs for commits
 * Supports unified diff view with syntax highlighting for additions/deletions
 */
export function DiffViewer({ files, className = '' }: DiffViewerProps) {
  const [expandAll, setExpandAll] = useState(true);

  const totalAdditions = files.reduce((sum, f) => sum + f.additions, 0);
  const totalDeletions = files.reduce((sum, f) => sum + f.deletions, 0);

  return (
    <div className={className}>
      {/* Summary header */}
      <div className="flex items-center justify-between mb-4 pb-4 border-b border-theme">
        <div className="flex items-center gap-4 text-sm">
          <span className="text-theme-secondary">
            Showing <span className="font-medium text-theme-primary">{files.length}</span> changed files
          </span>
          <span className="flex items-center gap-1 text-theme-success dark:text-green-400">
            <Plus className="w-3 h-3" />
            {totalAdditions} additions
          </span>
          <span className="flex items-center gap-1 text-theme-danger dark:text-red-400">
            <Minus className="w-3 h-3" />
            {totalDeletions} deletions
          </span>
        </div>
        <button
          onClick={() => setExpandAll(!expandAll)}
          className="text-sm text-theme-secondary hover:text-theme-primary"
        >
          {expandAll ? 'Collapse all' : 'Expand all'}
        </button>
      </div>

      {/* File list */}
      {files.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary">
          No file changes to display
        </div>
      ) : (
        <div>
          {files.map((file, index) => (
            <FileDiff
              key={`${file.filename}-${index}`}
              file={file}
              defaultExpanded={expandAll}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export default DiffViewer;
