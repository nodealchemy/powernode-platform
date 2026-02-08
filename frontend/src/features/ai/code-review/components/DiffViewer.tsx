import React, { useState, useEffect } from 'react';
import { MessageSquare, CheckCircle, Plus } from 'lucide-react';
import { codeReviewApi, CodeReviewComment } from '../services/codeReviewApi';

interface DiffLine {
  type: 'add' | 'remove' | 'context';
  content: string;
  lineNumber: number;
}

interface DiffFile {
  path: string;
  lines: DiffLine[];
}

interface DiffAnalysis {
  files: DiffFile[];
}

interface DiffViewerProps {
  reviewId: string;
  diffAnalysis: DiffAnalysis;
  comments?: CodeReviewComment[];
  onResolve?: (commentId: string) => void;
}

const SEVERITY_COLORS: Record<string, string> = {
  critical: 'border-theme-danger bg-theme-error/5',
  warning: 'border-theme-warning bg-theme-warning/5',
  info: 'border-theme-info bg-theme-info/5'
};

export const DiffViewer: React.FC<DiffViewerProps> = ({
  reviewId,
  diffAnalysis,
  comments: externalComments,
  onResolve
}) => {
  const [activeFile, setActiveFile] = useState(0);
  const [comments, setComments] = useState<CodeReviewComment[]>(externalComments || []);
  const [hoveredLine, setHoveredLine] = useState<number | null>(null);

  useEffect(() => {
    if (!externalComments) {
      const loadComments = async () => {
        try {
          const data = await codeReviewApi.getComments(reviewId);
          setComments(data);
        } catch {
          // Silently handle
        }
      };
      loadComments();
    }
  }, [reviewId, externalComments]);

  const handleResolve = async (commentId: string) => {
    try {
      await codeReviewApi.resolveComment(reviewId, commentId);
      setComments(prev => prev.map(c => c.id === commentId ? { ...c, resolved: true } : c));
      onResolve?.(commentId);
    } catch {
      // Error handled silently
    }
  };

  if (!diffAnalysis?.files?.length) {
    return (
      <div className="text-sm text-theme-secondary p-4">No diff data available</div>
    );
  }

  const currentFile = diffAnalysis.files[activeFile];
  const fileComments = comments.filter(c => c.file_path === currentFile?.path);

  return (
    <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
      {/* File tabs */}
      <div className="flex overflow-x-auto border-b border-theme bg-theme-background">
        {diffAnalysis.files.map((file, idx) => {
          const fileCommentCount = comments.filter(c => c.file_path === file.path && !c.resolved).length;
          return (
            <button
              key={file.path}
              type="button"
              onClick={() => setActiveFile(idx)}
              className={`px-4 py-2 text-xs font-mono whitespace-nowrap border-b-2 transition-colors ${
                idx === activeFile
                  ? 'border-theme-primary text-theme-primary bg-theme-surface'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              {file.path}
              {fileCommentCount > 0 && (
                <span className="ml-2 px-1.5 py-0.5 text-xs rounded-full bg-theme-warning/20 text-theme-warning">
                  {fileCommentCount}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* Diff content */}
      <div className="overflow-x-auto">
        <table className="w-full text-xs font-mono">
          <tbody>
            {currentFile?.lines.map((line, idx) => {
              const lineComments = fileComments.filter(
                c => line.lineNumber >= c.line_start && line.lineNumber <= c.line_end
              );

              return (
                <React.Fragment key={idx}>
                  <tr
                    className={`group ${
                      line.type === 'add'
                        ? 'bg-theme-success/10'
                        : line.type === 'remove'
                        ? 'bg-theme-error/10'
                        : ''
                    }`}
                    onMouseEnter={() => setHoveredLine(line.lineNumber)}
                    onMouseLeave={() => setHoveredLine(null)}
                  >
                    <td className="w-12 px-2 py-0.5 text-right text-theme-secondary select-none border-r border-theme">
                      {line.lineNumber}
                    </td>
                    <td className="w-6 px-1 py-0.5 text-center select-none">
                      {line.type === 'add' && <span className="text-theme-success">+</span>}
                      {line.type === 'remove' && <span className="text-theme-danger">-</span>}
                    </td>
                    <td className="px-4 py-0.5 whitespace-pre text-theme-primary">
                      {line.content}
                      {hoveredLine === line.lineNumber && (
                        <button
                          type="button"
                          className="inline-flex ml-2 opacity-0 group-hover:opacity-100 transition-opacity"
                          title="Add comment"
                        >
                          <Plus className="h-3 w-3 text-theme-info" />
                        </button>
                      )}
                    </td>
                  </tr>

                  {/* Inline comments */}
                  {lineComments.map(comment => (
                    <tr key={comment.id}>
                      <td colSpan={3} className="px-4 py-2">
                        <div className={`p-3 rounded-md border-l-4 ${SEVERITY_COLORS[comment.severity] || SEVERITY_COLORS.info}`}>
                          <div className="flex items-center justify-between mb-1">
                            <div className="flex items-center gap-2">
                              <MessageSquare className="h-3 w-3" />
                              <span className="text-xs font-medium capitalize">{comment.comment_type}</span>
                              <span className="text-xs text-theme-secondary">{comment.category}</span>
                            </div>
                            {!comment.resolved && (
                              <button
                                type="button"
                                onClick={() => handleResolve(comment.id)}
                                className="text-xs text-theme-success hover:underline flex items-center gap-1"
                              >
                                <CheckCircle className="h-3 w-3" />
                                Resolve
                              </button>
                            )}
                            {comment.resolved && (
                              <span className="text-xs text-theme-success flex items-center gap-1">
                                <CheckCircle className="h-3 w-3" /> Resolved
                              </span>
                            )}
                          </div>
                          <p className="text-xs text-theme-primary">{comment.content}</p>
                          {comment.suggested_fix && (
                            <div className="mt-2 p-2 bg-theme-background rounded text-xs font-mono text-theme-primary">
                              {comment.suggested_fix}
                            </div>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </React.Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
};
