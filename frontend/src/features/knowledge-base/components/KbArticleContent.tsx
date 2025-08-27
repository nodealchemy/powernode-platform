import { KbArticle } from '@/shared/services/knowledgeBaseApi';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { 
  DocumentArrowDownIcon,
  PhotoIcon,
  DocumentIcon
} from '@heroicons/react/24/outline';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import rehypeHighlight from 'rehype-highlight';
import rehypeRaw from 'rehype-raw';
import type { Components } from 'react-markdown';

interface KbArticleContentProps {
  article: KbArticle;
}

export function KbArticleContent({ article }: KbArticleContentProps) {
  const components: Components = {
              // Custom components to ensure theme-aware styling
              h1: ({ children }) => (
                <h1 className="text-3xl font-bold text-theme-primary mb-4 mt-8 first:mt-0">
                  {children}
                </h1>
              ),
              h2: ({ children }) => (
                <h2 className="text-2xl font-semibold text-theme-primary mb-3 mt-6">
                  {children}
                </h2>
              ),
              h3: ({ children }) => (
                <h3 className="text-xl font-medium text-theme-primary mb-2 mt-4">
                  {children}
                </h3>
              ),
              p: ({ children }) => (
                <p className="text-theme-secondary mb-4 leading-relaxed">
                  {children}
                </p>
              ),
              a: ({ children, href }) => (
                <a 
                  href={href} 
                  className="text-theme-primary hover:underline"
                  target={href?.startsWith('http') ? '_blank' : '_self'}
                  rel={href?.startsWith('http') ? 'noopener noreferrer' : undefined}
                >
                  {children}
                </a>
              ),
              code: ({ children, className, ...props }) => {
                const isInline = !className || !className.includes('language-');
                if (isInline) {
                  return (
                    <code className="bg-theme-surface text-theme-primary px-1 py-0.5 rounded text-sm font-mono">
                      {children}
                    </code>
                  );
                }
                return (
                  <code className={className} {...props}>
                    {children}
                  </code>
                );
              },
              pre: ({ children }) => (
                <pre className="bg-theme-surface border border-theme rounded-lg p-4 overflow-x-auto">
                  {children}
                </pre>
              ),
              blockquote: ({ children }) => (
                <blockquote className="border-l-4 border-theme-primary pl-4 text-theme-secondary italic my-4">
                  {children}
                </blockquote>
              ),
              ul: ({ children }) => (
                <ul className="list-disc ml-6 mb-4 text-theme-secondary space-y-1">
                  {children}
                </ul>
              ),
              ol: ({ children }) => (
                <ol className="list-decimal ml-6 mb-4 text-theme-secondary space-y-1">
                  {children}
                </ol>
              ),
              li: ({ children }) => (
                <li className="leading-relaxed">
                  {children}
                </li>
              ),
              table: ({ children }) => (
                <div className="overflow-x-auto my-6">
                  <table className="min-w-full border border-theme rounded-lg">
                    {children}
                  </table>
                </div>
              ),
              th: ({ children }) => (
                <th className="bg-theme-surface text-theme-primary font-semibold p-3 text-left border-b border-theme">
                  {children}
                </th>
              ),
              td: ({ children }) => (
                <td className="text-theme-secondary p-3 border-b border-theme last:border-b-0">
                  {children}
                </td>
              ),
              hr: () => (
                <hr className="border-theme my-8" />
              )
            };

  return (
    <div className="space-y-8">
      {/* Article Content */}
      <div className="prose prose-lg max-w-none prose-headings:text-theme-primary prose-p:text-theme-secondary prose-a:text-theme-primary prose-strong:text-theme-primary prose-code:text-theme-primary prose-code:bg-theme-surface prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-pre:bg-theme-surface prose-pre:border prose-pre:border-theme prose-blockquote:border-theme-primary prose-blockquote:text-theme-secondary prose-th:text-theme-primary prose-td:text-theme-secondary prose-hr:border-theme">
        {article.content && (
          <ReactMarkdown
            remarkPlugins={[remarkGfm, remarkBreaks]}
            rehypePlugins={[rehypeHighlight, rehypeRaw]}
            components={components}
          >
            {article.content}
          </ReactMarkdown>
        )}
      </div>

      {/* Attachments */}
      {article.attachments && article.attachments.length > 0 && (
        <div className="border-t border-theme pt-8">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">
            Attachments
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {article.attachments.map(attachment => (
              <AttachmentCard key={attachment.id} attachment={attachment} />
            ))}
          </div>
        </div>
      )}

      {/* Article Tags */}
      {article.tags.length > 0 && (
        <div className="border-t border-theme pt-8">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">
            Tags
          </h3>
          <div className="flex flex-wrap gap-2">
            {article.tags.map((tag, index) => (
              <Badge 
                key={index} 
                variant="secondary" 
                size="sm"
                className="cursor-pointer hover:bg-theme-primary hover:text-white"
              >
                {tag}
              </Badge>
            ))}
          </div>
        </div>
      )}

      {/* Article Actions */}
      <div className="border-t border-theme pt-8">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="sm">
            Share Article
          </Button>
          <Button variant="ghost" size="sm">
            Print
          </Button>
          {article.can_edit && (
            <Button 
              onClick={() => window.location.href = `/app/content/kb/admin/articles/${article.id}/edit`}
              variant="secondary" 
              size="sm"
            >
              Edit Article
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

interface AttachmentCardProps {
  attachment: {
    id: string;
    filename: string;
    content_type: string;
    file_size: string;
    download_count: number;
  };
}

function AttachmentCard({ attachment }: AttachmentCardProps) {
  const isImage = attachment.content_type.startsWith('image/');
  const isDocument = attachment.content_type.includes('pdf') || 
                    attachment.content_type.includes('document') ||
                    attachment.content_type.includes('text');

  const getIcon = () => {
    if (isImage) return PhotoIcon;
    if (isDocument) return DocumentIcon;
    return DocumentArrowDownIcon;
  };

  const Icon = getIcon();

  const handleDownload = async () => {
    try {
      // In a real implementation, you'd make an API call to get the download URL
      // For now, this is a placeholder
    } catch (error) {
      console.error('Failed to download attachment:', error);
    }
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-4">
      <div className="flex items-start gap-3">
        <Icon className="h-6 w-6 text-theme-secondary flex-shrink-0 mt-1" />
        <div className="flex-1 min-w-0">
          <h4 className="font-medium text-theme-primary line-clamp-1">
            {attachment.filename}
          </h4>
          <div className="flex items-center gap-2 mt-1 text-sm text-theme-secondary">
            <span>{attachment.file_size}</span>
            <span>•</span>
            <span>{attachment.download_count} downloads</span>
          </div>
          <Button
            onClick={handleDownload}
            variant="ghost"
            size="sm"
            className="mt-2 -ml-2"
          >
            <DocumentArrowDownIcon className="h-4 w-4 mr-1" />
            Download
          </Button>
        </div>
      </div>
    </div>
  );
}