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
              // Professional business-like styling with enhanced hierarchy
              h1: ({ children }) => (
                <h1 className="text-4xl font-bold text-theme-primary mb-6 mt-10 first:mt-0 pb-3 border-b border-theme">
                  {children}
                </h1>
              ),
              h2: ({ children }) => (
                <h2 className="text-2xl font-semibold text-theme-primary mb-4 mt-8 pb-2 border-b border-theme-light">
                  {children}
                </h2>
              ),
              h3: ({ children }) => (
                <h3 className="text-xl font-medium text-theme-primary mb-3 mt-6">
                  {children}
                </h3>
              ),
              h4: ({ children }) => (
                <h4 className="text-lg font-medium text-theme-primary mb-2 mt-4">
                  {children}
                </h4>
              ),
              h5: ({ children }) => (
                <h5 className="text-base font-semibold text-theme-primary mb-2 mt-3">
                  {children}
                </h5>
              ),
              h6: ({ children }) => (
                <h6 className="text-sm font-semibold text-theme-secondary mb-2 mt-3 uppercase tracking-wider">
                  {children}
                </h6>
              ),
              p: ({ children }) => (
                <p className="text-theme-secondary mb-4 leading-relaxed text-base">
                  {children}
                </p>
              ),
              a: ({ children, href }) => (
                <a 
                  href={href} 
                  className="text-theme-link hover:text-theme-link-hover underline underline-offset-2 decoration-1 hover:decoration-2 transition-all"
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
                    <code className="bg-theme-surface text-theme-primary px-2 py-0.5 rounded-md text-sm font-mono border border-theme font-medium">
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
                <pre className="bg-theme-background border border-theme rounded-lg p-6 overflow-x-auto shadow-sm my-6 relative">
                  <div className="absolute top-2 right-2 text-xs text-theme-tertiary font-mono">
                    CODE
                  </div>
                  {children}
                </pre>
              ),
              blockquote: ({ children }) => (
                <blockquote className="border-l-4 border-theme-primary bg-theme-surface pl-6 pr-4 py-4 text-theme-secondary italic my-6 rounded-r-lg shadow-sm relative">
                  <div className="absolute top-2 left-2 text-theme-primary opacity-30">
                    <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M14.017 21v-7.391c0-5.704 3.731-9.57 8.983-10.609l.995 2.151c-2.432.917-3.995 3.638-3.995 5.849h4v10h-9.983zm-14.017 0v-7.391c0-5.704 3.748-9.57 9-10.609l.996 2.151c-2.433.917-3.996 3.638-3.996 5.849h4v10h-10z"/>
                    </svg>
                  </div>
                  {children}
                </blockquote>
              ),
              ul: ({ children }) => (
                <ul className="ml-0 mb-6 text-theme-secondary space-y-2">
                  {children}
                </ul>
              ),
              ol: ({ children }) => (
                <ol className="ml-0 mb-6 text-theme-secondary space-y-2 counter-reset-none">
                  {children}
                </ol>
              ),
              li: ({ children }) => (
                <li className="leading-relaxed pl-6 relative before:content-['•'] before:absolute before:left-2 before:text-theme-primary before:font-bold before:text-lg">
                  {children}
                </li>
              ),
              table: ({ children }) => (
                <div className="overflow-x-auto my-8 shadow-sm rounded-lg border border-theme">
                  <table className="min-w-full">
                    {children}
                  </table>
                </div>
              ),
              th: ({ children }) => (
                <th className="bg-theme-surface text-theme-primary font-semibold p-4 text-left border-b border-theme text-sm uppercase tracking-wide">
                  {children}
                </th>
              ),
              td: ({ children }) => (
                <td className="text-theme-secondary p-4 border-b border-theme-light last:border-b-0 hover:bg-theme-surface transition-colors">
                  {children}
                </td>
              ),
              hr: () => (
                <hr className="border-theme my-12 border-t-2" />
              ),
              // Strong emphasis
              strong: ({ children }) => (
                <strong className="font-semibold text-theme-primary">
                  {children}
                </strong>
              ),
              // Emphasized text
              em: ({ children }) => (
                <em className="italic text-theme-primary">
                  {children}
                </em>
              )
            };

  return (
    <div className="space-y-10">
      {/* Article Content */}
      <article className="pb-10">
        <div className="max-w-none prose-lg kb-article-content">
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
      </article>

      {/* Attachments */}
      {article.attachments && article.attachments.length > 0 && (
        <section className="border-t border-theme pt-10">
          <h3 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13" />
            </svg>
            Attachments
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {article.attachments.map(attachment => (
              <AttachmentCard 
                key={attachment.id} 
                attachment={{
                  id: attachment.id,
                  filename: attachment.filename,
                  content_type: attachment.content_type,
                  file_size: attachment.file_size || `${attachment.size || 0} bytes`,
                  download_count: attachment.download_count || 0
                }} 
              />
            ))}
          </div>
        </section>
      )}

      {/* Article Tags */}
      {article.tags.length > 0 && (
        <section className="border-t border-theme pt-10">
          <h3 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
            </svg>
            Tags
          </h3>
          <div className="flex flex-wrap gap-3">
            {article.tags.map((tag, index) => (
              <Badge 
                key={index} 
                variant="secondary" 
                size="lg"
                className="cursor-pointer hover:bg-theme-primary hover:text-white transition-all hover:scale-105 font-medium px-3 py-1"
              >
                {tag}
              </Badge>
            ))}
          </div>
        </section>
      )}

      {/* Article Actions */}
      <section className="border-t border-theme pt-10">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <Button variant="ghost" size="sm" className="hover:bg-theme-surface">
              <svg className="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.367 2.684 3 3 0 00-5.367-2.684z" />
              </svg>
              Share Article
            </Button>
            <Button variant="ghost" size="sm" className="hover:bg-theme-surface">
              <svg className="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 17h2a2 2 0 002-2v-4a2 2 0 00-2-2H5a2 2 0 00-2 2v4a2 2 0 002 2h2m2 4h6a2 2 0 002-2v-4a2 2 0 00-2-2H9a2 2 0 00-2 2v4a2 2 0 002 2zm8-12V5a2 2 0 00-2-2H9a2 2 0 00-2 2v4h10z" />
              </svg>
              Print
            </Button>
          </div>
          {article.can_edit && (
            <Button 
              onClick={() => window.location.href = `/app/content/kb/admin/articles/${article.id}/edit`}
              variant="secondary" 
              size="sm"
              className="font-medium"
            >
              <svg className="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
              </svg>
              Edit Article
            </Button>
          )}
        </div>
      </section>
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
    }
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6 hover:shadow-md transition-all hover:border-theme-primary group">
      <div className="flex items-start gap-4">
        <div className="flex-shrink-0 w-12 h-12 bg-theme-background rounded-lg flex items-center justify-center group-hover:bg-theme-primary group-hover:text-white transition-colors">
          <Icon className="h-6 w-6" />
        </div>
        <div className="flex-1 min-w-0">
          <h4 className="font-semibold text-theme-primary line-clamp-2 mb-2">
            {attachment.filename}
          </h4>
          <div className="flex items-center gap-3 mb-4 text-sm text-theme-secondary">
            <span className="font-medium">{attachment.file_size}</span>
            <span className="w-1 h-1 bg-theme-tertiary rounded-full"></span>
            <span>{attachment.download_count} downloads</span>
          </div>
          <Button
            onClick={handleDownload}
            variant="secondary"
            size="sm"
            className="font-medium hover:bg-theme-primary hover:text-white"
          >
            <DocumentArrowDownIcon className="h-4 w-4 mr-2" />
            Download File
          </Button>
        </div>
      </div>
    </div>
  );
}