import { useState, useEffect } from 'react';
import { knowledgeBaseApi, KbComment } from '@/shared/services/content/knowledgeBaseApi';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { 
  ChatBubbleLeftEllipsisIcon, 
  HandThumbUpIcon, 
  UserIcon,
  ExclamationTriangleIcon
} from '@heroicons/react/24/outline';
import { formatDistanceToNow } from 'date-fns';

interface KbArticleCommentsProps {
  articleId: string;
}

export function KbArticleComments({ articleId }: KbArticleCommentsProps) {
  const { isAuthenticated } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const showSuccess = (message: string) => showNotification(message, 'success');
  const showError = (message: string) => showNotification(message, 'error');
  const [comments, setComments] = useState<KbComment[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [newComment, setNewComment] = useState('');
  const [replyTo, setReplyTo] = useState<string | null>(null);
  const [replyContent, setReplyContent] = useState('');

  useEffect(() => {
    loadComments();
  }, [articleId]);  

  const loadComments = async () => {
    try {
      setIsLoading(true);
      const response = await knowledgeBaseApi.getArticleComments(articleId, { per_page: 50 });
      setComments(response.data.data.comments);
    } catch {
    // Error silently ignored
  } finally {
      setIsLoading(false);
    }
  };

  const handleSubmitComment = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!newComment.trim()) return;
    if (!isAuthenticated) {
      showError('Please sign in to leave a comment');
      return;
    }

    try {
      setIsSubmitting(true);
      
      const response = await knowledgeBaseApi.createComment(articleId, {
        content: newComment.trim()
      });

      setComments(prev => [response.data.data, ...prev]);
      setNewComment('');
      showSuccess('Comment posted successfully');
    } catch {
      showError('Failed to post comment. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleSubmitReply = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!replyContent.trim() || !replyTo) return;
    if (!isAuthenticated) {
      showError('Please sign in to reply');
      return;
    }

    try {
      setIsSubmitting(true);
      
      const response = await knowledgeBaseApi.createComment(articleId, {
        content: replyContent.trim(),
        parent_id: replyTo
      });

      // Add reply to the parent comment
      setComments(prev => prev.map(comment => {
        if (comment.id === replyTo) {
          return {
            ...comment,
            replies: [...(comment.replies || []), response.data.data]
          };
        }
        return comment;
      }));

      setReplyContent('');
      setReplyTo(null);
      showSuccess('Reply posted successfully');
    } catch {
      showError('Failed to post reply. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (isLoading) {
    return (
      <div className="space-y-6">
        <h2 className="text-xl font-semibold text-theme-primary flex items-center gap-2">
          <ChatBubbleLeftEllipsisIcon className="h-6 w-6" />
          Comments
        </h2>
        <div className="flex items-center justify-center h-32">
          <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-theme-primary"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h2 className="text-xl font-semibold text-theme-primary flex items-center gap-2">
        <ChatBubbleLeftEllipsisIcon className="h-6 w-6" />
        Comments ({comments.length})
      </h2>

      {/* Comment Form */}
      {isAuthenticated ? (
        <form onSubmit={handleSubmitComment} className="space-y-4">
          <div>
            <label htmlFor="comment" className="block text-sm font-medium text-theme-primary mb-2">
              Leave a comment
            </label>
            <textarea
              id="comment"
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              placeholder="Share your thoughts or ask a question..."
              rows={4}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent resize-vertical"
            />
          </div>
          <div className="flex items-center justify-between">
            <p className="text-sm text-theme-secondary">
              Comments are reviewed before being published.
            </p>
            <Button
              type="submit"
              disabled={!newComment.trim() || isSubmitting}
              loading={isSubmitting}
            >
              Post Comment
            </Button>
          </div>
        </form>
      ) : (
        <div className="bg-theme-surface rounded-lg border border-theme p-6 text-center">
          <ChatBubbleLeftEllipsisIcon className="h-8 w-8 text-theme-tertiary mx-auto mb-2" />
          <p className="text-theme-secondary mb-4">
            Sign in to join the conversation and leave a comment.
          </p>
          <Button 
            onClick={() => window.location.href = '/auth/login'} 
            variant="primary"
          >
            Sign In
          </Button>
        </div>
      )}

      {/* Comments List */}
      {comments.length > 0 ? (
        <div className="space-y-6">
          {comments.map(comment => (
            <CommentItem 
              key={comment.id} 
              comment={comment}
              onReply={setReplyTo}
              replyTo={replyTo}
              replyContent={replyContent}
              onReplyContentChange={setReplyContent}
              onSubmitReply={handleSubmitReply}
              isSubmitting={isSubmitting}
              isAuthenticated={isAuthenticated}
            />
          ))}
        </div>
      ) : (
        <div className="text-center py-12">
          <ChatBubbleLeftEllipsisIcon className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">
            No comments yet
          </h3>
          <p className="text-theme-secondary">
            Be the first to share your thoughts on this article.
          </p>
        </div>
      )}
    </div>
  );
}

interface CommentItemProps {
  comment: KbComment;
  onReply: (commentId: string) => void;
  replyTo: string | null;
  replyContent: string;
  onReplyContentChange: (content: string) => void;
  onSubmitReply: (e: React.FormEvent) => void;
  isSubmitting: boolean;
  isAuthenticated: boolean;
}

function CommentItem({ 
  comment, 
  onReply, 
  replyTo, 
  replyContent, 
  onReplyContentChange, 
  onSubmitReply, 
  isSubmitting, 
  isAuthenticated 
}: CommentItemProps) {
  const isReplying = replyTo === comment.id;

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6">
      {/* Comment Header */}
      <div className="flex items-start gap-4">
        <div className="bg-theme-primary/10 rounded-full p-2">
          <UserIcon className="h-5 w-5 text-theme-primary" />
        </div>
        
        <div className="flex-1">
          <div className="flex items-center gap-2 mb-2">
            <span className="font-medium text-theme-primary">
              {comment.user_name}
            </span>
            <span className="text-sm text-theme-secondary">
              {formatDistanceToNow(new Date(comment.created_at), { addSuffix: true })}
            </span>
            {comment.status === 'pending' && (
              <div className="flex items-center gap-1 text-xs text-theme-warning">
                <ExclamationTriangleIcon className="h-3 w-3" />
                <span>Pending approval</span>
              </div>
            )}
          </div>

          {/* Comment Content */}
          <div className="text-theme-secondary mb-4 whitespace-pre-wrap">
            {comment.content}
          </div>

          {/* Comment Actions */}
          <div className="flex items-center gap-4 text-sm">
            <button
              className="flex items-center gap-1 text-theme-secondary hover:text-theme-primary transition-colors"
              disabled
            >
              <HandThumbUpIcon className="h-4 w-4" />
              <span>{comment.likes_count}</span>
            </button>

            {isAuthenticated && (
              <button
                onClick={() => onReply(isReplying ? '' : comment.id)}
                className="text-theme-secondary hover:text-theme-primary transition-colors"
              >
                {isReplying ? 'Cancel' : 'Reply'}
              </button>
            )}

            {comment.replies_count > 0 && !comment.replies?.length && (
              <span className="text-theme-secondary">
                {comment.replies_count} {comment.replies_count === 1 ? 'reply' : 'replies'}
              </span>
            )}
          </div>

          {/* Reply Form */}
          {isReplying && (
            <form onSubmit={onSubmitReply} className="mt-4 space-y-3">
              <textarea
                value={replyContent}
                onChange={(e) => onReplyContentChange(e.target.value)}
                placeholder="Write your reply..."
                rows={3}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent resize-vertical"
              />
              <div className="flex items-center gap-2">
                <Button
                  type="submit"
                  size="sm"
                  disabled={!replyContent.trim() || isSubmitting}
                  loading={isSubmitting}
                >
                  Post Reply
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => onReply('')}
                >
                  Cancel
                </Button>
              </div>
            </form>
          )}

          {/* Replies */}
          {comment.replies && comment.replies.length > 0 && (
            <div className="mt-6 space-y-4 border-l-2 border-theme-tertiary pl-4">
              {comment.replies.map(reply => (
                <div key={reply.id} className="bg-theme-background rounded-lg p-4">
                  <div className="flex items-start gap-3">
                    <div className="bg-theme-primary/5 rounded-full p-1.5">
                      <UserIcon className="h-4 w-4 text-theme-primary" />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-2">
                        <span className="font-medium text-theme-primary text-sm">
                          {reply.user_name}
                        </span>
                        <span className="text-xs text-theme-secondary">
                          {formatDistanceToNow(new Date(reply.created_at), { addSuffix: true })}
                        </span>
                        {reply.status === 'pending' && (
                          <div className="flex items-center gap-1 text-xs text-theme-warning">
                            <ExclamationTriangleIcon className="h-3 w-3" />
                            <span>Pending</span>
                          </div>
                        )}
                      </div>
                      <div className="text-theme-secondary text-sm whitespace-pre-wrap">
                        {reply.content}
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}