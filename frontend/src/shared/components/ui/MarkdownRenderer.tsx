import React from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import rehypeHighlight from 'rehype-highlight';
import rehypeRaw from 'rehype-raw';
import type { Components } from 'react-markdown';
import { hasMarkdownFormatting } from '@/shared/utils/markdownUtils';
import { sanitizeMarkdown } from '@/shared/utils/sanitizeHtml';

/**
 * Process markdown content to add advanced visual features
 * Supports callouts, alerts, badges, and enhanced formatting
 */
const processAdvancedFeatures = (content: string): string => {
  if (!content) return content;

  return content
    // Callout syntax: :::info, :::warning, :::success, :::danger, :::note
    // Fixed: Use atomic grouping pattern to prevent backtracking
    .replace(/:::(info|warning|success|danger|note)\n([^]*?)\n:::/g, 
      '<div class="callout callout-$1" data-type="$1">$2</div>')
    
    // Alert syntax: !!! for important alerts
    // Fixed: Simplified pattern to prevent ReDoS
    .replace(/!!!\s*([^\n]*)\n([^]*?)(?:\n\n|$)/g, 
      '<div class="alert alert-info">$2</div>')
    
    // Badge syntax: [[badge:text]] or [[badge:type:text]]
    .replace(/\[\[badge:([^:]+):([^\]]+)\]\]/g, 
      '<span class="badge badge-$1" data-badge="$1">$2</span>')
    .replace(/\[\[badge:([^\]]+)\]\]/g, 
      '<span class="badge" data-badge="primary">$1</span>')
    
    // Card blocks: ~~~ card content ~~~
    // Fixed: Use [^]* instead of [\s\S]*? to prevent backtracking
    .replace(/~~~\s*card\s*\n([^]*?)\n~~~/g, 
      '<div class="card-block" data-card="true">$1</div>')
    
    // Terminal code blocks: ```terminal or ```bash with terminal styling
    // Fixed: Use [^]* instead of [\s\S]*? to prevent backtracking
    .replace(/```(terminal|bash|sh)\n([^]*?)```/g, 
      '<pre class="code-terminal" data-terminal="true"><code>$2</code></pre>')
    
    // Enhanced horizontal rules with decorative elements
    .replace(/---\s*\*\s*---/g, 
      '<hr class="decorated-hr" />')
      
    // Auto-link detection for enhanced link styling
    .replace(/(https?:\/\/[^\s]+)/g, 
      '[$1]($1)');
};

interface MarkdownRendererProps {
  content: string;
  renderedContent?: string;
  variant?: 'admin' | 'public' | 'preview';
  className?: string;
  enableAdvancedFeatures?: boolean;
  tableWrapper?: boolean;
  customComponents?: Partial<Components>;
  maxWidth?: 'none' | 'prose' | 'narrow' | 'wide';
  fontSize?: 'sm' | 'base' | 'lg';
  lineHeight?: 'tight' | 'normal' | 'relaxed';
  enableReadingMode?: boolean;
}

export const MarkdownRenderer: React.FC<MarkdownRendererProps> = ({
  content,
  renderedContent,
  variant = 'admin',
  className = '',
  enableAdvancedFeatures = true,
  tableWrapper = true,
  customComponents,
  maxWidth = variant === 'public' ? 'prose' : 'wide',
  fontSize = variant === 'public' ? 'lg' : 'base',
  lineHeight = variant === 'public' ? 'relaxed' : 'normal',
  enableReadingMode = variant === 'public'
}) => {
  // Modern markdown components with enhanced UX design
  const getMarkdownComponents = (): Components => {
    const isPublic = variant === 'public';

    return {
      // Enhanced headings with modern typography and optimal spacing
      h1: ({ children }) => (
        <h1 className={`
          ${fontSize === 'lg' ? 'text-4xl md:text-5xl' : fontSize === 'sm' ? 'text-2xl md:text-3xl' : 'text-3xl md:text-4xl'}
          font-bold mb-8 mt-12 first:mt-0 
          ${lineHeight === 'tight' ? 'leading-tight' : lineHeight === 'relaxed' ? 'leading-relaxed' : 'leading-normal'}
          ${isPublic
            ? 'text-white'
            : 'text-theme-primary'
          }
          transition-all duration-300 ease-out
          scroll-margin-top-16 relative
          ${enableReadingMode ? 'max-w-4xl' : ''}
        `}>
          {children}
        </h1>
      ),

      h2: ({ children }) => (
        <h2 className={`
          ${fontSize === 'lg' ? 'text-3xl md:text-4xl' : fontSize === 'sm' ? 'text-xl md:text-2xl' : 'text-2xl md:text-3xl'}
          font-bold mb-6 mt-10 first:mt-0
          ${lineHeight === 'tight' ? 'leading-tight' : lineHeight === 'relaxed' ? 'leading-relaxed' : 'leading-normal'}
          ${isPublic ? 'text-white' : 'text-theme-primary'}
          relative transition-all duration-300 ease-out
          scroll-margin-top-16
          ${enableReadingMode ? 'max-w-4xl' : ''}
          ${isPublic ? 'pl-4 before:absolute before:left-0 before:top-0 before:bottom-0 before:w-1 before:bg-gradient-to-b before:from-blue-400 before:to-blue-300 before:rounded-full before:opacity-80' : ''}
        `}>
          {children}
        </h2>
      ),

      h3: ({ children }) => (
        <h3 className={`
          ${fontSize === 'lg' ? 'text-2xl md:text-3xl' : fontSize === 'sm' ? 'text-lg md:text-xl' : 'text-xl md:text-2xl'}
          font-semibold mb-4 mt-8 first:mt-0
          ${lineHeight === 'tight' ? 'leading-tight' : lineHeight === 'relaxed' ? 'leading-relaxed' : 'leading-normal'}
          ${isPublic ? 'text-white' : 'text-theme-primary'}
          relative transition-all duration-300 ease-out
          scroll-margin-top-16
          ${enableReadingMode ? 'max-w-4xl' : ''}
          ${isPublic ? 'pl-3 before:absolute before:left-0 before:top-0 before:bottom-0 before:w-0.5 before:bg-gradient-to-b before:from-blue-400 before:to-blue-300 before:rounded-full before:opacity-60' : ''}
        `}>
          {children}
        </h3>
      ),

      h4: ({ children }) => (
        <h4 className={`
          text-lg md:text-xl font-semibold mb-2 mt-5 first:mt-0 leading-tight
          ${isPublic ? 'text-white' : 'text-theme-primary'}
          transition-all duration-300 ease-out
        `}>
          {children}
        </h4>
      ),

      h5: ({ children }) => (
        <h5 className={`
          text-base md:text-lg font-semibold mb-2 mt-4 first:mt-0 leading-tight
          ${isPublic ? 'text-white' : 'text-theme-primary'}
          transition-all duration-300 ease-out
        `}>
          {children}
        </h5>
      ),

      h6: ({ children }) => (
        <h6 className={`
          text-sm md:text-base font-medium mb-2 mt-3 first:mt-0 leading-tight
          ${isPublic ? 'text-white/90' : 'text-theme-secondary'}
          uppercase tracking-wide transition-all duration-300 ease-out
        `}>
          {children}
        </h6>
      ),

      // Enhanced paragraph styling with optimal reading width
      p: ({ children }) => (
        <p className={`
          ${fontSize === 'lg' ? 'text-lg md:text-xl' : fontSize === 'sm' ? 'text-sm md:text-base' : 'text-base md:text-lg'}
          ${isPublic ? 'text-white' : 'text-theme-primary'}
          mb-6 transition-all duration-300 ease-out
          ${lineHeight === 'tight' ? 'leading-snug' : lineHeight === 'relaxed' ? 'leading-relaxed' : 'leading-normal'}
          ${enableReadingMode ? 'max-w-prose' : ''}
          ${variant === 'public' ? 'text-opacity-90' : ''}
        `}>
          {children}
        </p>
      ),

      // Modern list styling with improved spacing and proper bullets
      ul: ({ children }) => (
        <ul className={`
          list-disc list-outside ml-6 mb-6 space-y-2
          ${isPublic ? 'text-white' : 'text-theme-primary'}
          ${enableReadingMode ? 'max-w-prose' : ''}
          ${fontSize === 'lg' ? 'text-lg' : fontSize === 'sm' ? 'text-sm' : 'text-base'}
        `}>
          {children}
        </ul>
      ),

      ol: ({ children }) => (
        <ol className={`
          list-decimal list-inside mb-6 space-y-3
          ${isPublic ? 'text-white' : 'text-theme-primary'}
          ${enableReadingMode ? 'max-w-prose' : ''}
          ${fontSize === 'lg' ? 'text-lg' : fontSize === 'sm' ? 'text-sm' : 'text-base'}
        `}>
          {children}
        </ol>
      ),

      li: ({ children }) => (
        <li className={`
          ${lineHeight === 'tight' ? 'leading-snug' : lineHeight === 'relaxed' ? 'leading-relaxed' : 'leading-normal'}
          mb-1 ${isPublic ? 'text-white' : 'text-theme-primary'} transition-all duration-200 ease-out hover:translate-x-1
        `}>
          {children}
        </li>
      ),

      // Glassmorphism blockquotes
      blockquote: ({ children }) => (
        <blockquote className={`
          relative border-l-4 ${isPublic ? 'border-theme-info' : 'border-theme-link'}
          pl-6 pr-6 py-4 my-6 italic
          backdrop-blur-lg rounded-r-xl
          ${isPublic ? 'bg-theme-surface/10' : 'bg-theme-surface/80'}
          shadow-lg ${isPublic ? 'shadow-theme-info/10' : 'shadow-theme-link/10'}
          transition-all duration-300 ease-out hover:shadow-xl ${isPublic ? 'hover:shadow-theme-info/20' : 'hover:shadow-theme-link/20'}
          before:absolute before:inset-0 before:-z-10 before:rounded-r-xl
          before:bg-gradient-to-r before:from-theme-surface/20 before:to-transparent
          before:backdrop-blur-sm dark:before:from-theme-surface/5
        `}>
          <div className={`${isPublic ? 'text-white' : 'text-theme-primary'}`}>
            {children}
          </div>
        </blockquote>
      ),

      // Enhanced code styling
      code: ({ children, className }) => {
        const isInline = !className;
        if (isInline) {
          return (
            <code className={`
              px-2 py-1 rounded-lg text-sm font-mono
              ${isPublic ? 'bg-theme-surface/20 text-white border-theme-surface/30' : 'bg-theme-surface text-theme-primary border border-theme'}
              transition-all duration-200 ease-out hover:scale-105
            `}>
              {children}
            </code>
          );
        }
        return (
          <code className={className} style={{ all: 'inherit' }}>
            {children}
          </code>
        );
      },

      // Modern code blocks with terminal-style design
      pre: ({ children }) => (
        <div className="relative group mb-6">
          {/* Terminal-style dots */}
          <div className="flex items-center space-x-2 px-4 py-2 bg-theme-background-secondary rounded-t-xl border-b border-theme">
            <div className="w-3 h-3 bg-theme-danger rounded-full opacity-80"></div>
            <div className="w-3 h-3 bg-theme-warning rounded-full opacity-80"></div>
            <div className="w-3 h-3 bg-theme-success rounded-full opacity-80"></div>
          </div>
          <pre className={`
            p-4 rounded-b-xl overflow-x-auto
            bg-theme-surface 
            border border-theme
            shadow-lg transition-all duration-300 ease-out
            group-hover:shadow-xl group-hover:shadow-theme-primary/10
            backdrop-blur-sm
          `}>
            {children}
          </pre>
        </div>
      ),

      // Enhanced links
      a: ({ href, children }) => (
        <a
          href={href}
          className={`
            ${isPublic
              ? 'text-theme-info hover:opacity-80'
              : 'text-theme-link hover:text-theme-link-hover'
            }
            underline decoration-2 underline-offset-2
            transition-all duration-200 ease-out
            hover:decoration-4 hover:underline-offset-4
            focus:outline-none focus:ring-2 ${isPublic ? 'focus:ring-theme-info/50' : 'focus:ring-theme-link/50'} focus:rounded
          `}
          target={href?.startsWith('http') ? '_blank' : undefined}
          rel={href?.startsWith('http') ? 'noopener noreferrer' : undefined}
        >
          {children}
        </a>
      ),

      // Enhanced text formatting
      strong: ({ children }) => (
        <strong className={`font-semibold ${isPublic ? 'text-white' : 'text-theme-primary'}`}>
          {children}
        </strong>
      ),

      em: ({ children }) => (
        <em className={`italic ${isPublic ? 'text-white' : 'text-theme-primary'}`}>
          {children}
        </em>
      ),

      // Modern horizontal rule
      hr: () => (
        <div className="my-8 flex items-center">
          <div className="flex-1 h-px bg-gradient-to-r from-transparent via-theme-tertiary to-transparent"></div>
          <div className="mx-4 w-2 h-2 bg-theme-link rounded-full"></div>
          <div className="flex-1 h-px bg-gradient-to-r from-transparent via-theme-tertiary to-transparent"></div>
        </div>
      ),

      // Enhanced table styling with wrapper support
      table: ({ children }) => {
        const tableElement = (
          <table className={`
            w-full border-separate border-spacing-0
            bg-theme-surface shadow-lg border border-theme
            rounded-xl overflow-hidden
            transition-all duration-300 ease-out hover:shadow-xl
            backdrop-filter blur-lg
          `}>
            {children}
          </table>
        );

        return tableWrapper !== false ? (
          <div className="table-wrapper my-6 overflow-x-auto rounded-xl shadow-lg bg-theme-surface border border-theme">
            {tableElement}
          </div>
        ) : (
          <div className="my-6">{tableElement}</div>
        );
      },

      th: ({ children }) => (
        <th className={`
          px-5 py-4 text-left font-semibold text-sm
          bg-gradient-to-br from-theme-info/10 to-theme-info/20
          dark:from-theme-info/20 dark:to-theme-info/30
          text-theme-primary border-b-2 border-theme-info/20
          border-r border-theme/30 last:border-r-0
          uppercase tracking-wide letter-spacing-wide
          transition-all duration-200 ease-out
          relative overflow-hidden
          before:absolute before:inset-0 before:bg-gradient-to-r 
          before:from-transparent before:via-white/5 before:to-transparent
          before:translate-x-[-100%] hover:before:translate-x-[100%]
          before:transition-transform before:duration-700
        `}>
          {children}
        </th>
      ),

      td: ({ children }) => (
        <td className={`
          px-5 py-4 text-theme-primary text-sm leading-relaxed
          border-b border-theme/30 border-r border-theme/20 last:border-r-0
          transition-all duration-200 ease-out
          hover:bg-theme-info/10 dark:hover:bg-theme-info/10
          relative
        `}>
          {children}
        </td>
      ),

      // Enhanced image styling
      img: ({ src, alt }) => (
        <img
          src={src}
          alt={alt}
          className={`
            max-w-full h-auto rounded-xl shadow-lg my-6
            transition-all duration-300 ease-out
            hover:shadow-2xl hover:scale-[1.02]
            border border-slate-200/50 dark:border-slate-700/50
          `}
        />
      )
    };
  };

  // Merge custom components with default components
  const baseComponents = getMarkdownComponents();
  const markdownComponents = customComponents ? { ...baseComponents, ...customComponents } : baseComponents;
  
  // Process content for advanced features
  const processedContent = enableAdvancedFeatures ? processAdvancedFeatures(content) : content;

  // Calculate container classes based on maxWidth prop
  const getContainerClasses = () => {
    const baseClasses = `markdown-renderer ${variant} ${className}`;
    const widthClasses = {
      'none': 'w-full',
      'prose': 'max-w-prose mx-auto px-4',
      'narrow': 'max-w-2xl mx-auto px-4',
      'wide': 'max-w-4xl mx-auto px-4'
    };
    
    return `${baseClasses} ${widthClasses[maxWidth]} ${enableReadingMode ? 'reading-mode' : ''}`;
  };

  return (
    <div className={getContainerClasses()}>
      {renderedContent ? (
        // If backend provides pre-rendered HTML content, use it (with caution)
        <div 
          className={`markdown-content ${variant}`}
          dangerouslySetInnerHTML={{ 
            __html: sanitizeMarkdown(renderedContent) 
          }} 
        />
      ) : content ? (
        hasMarkdownFormatting(content) ? (
          // Render markdown content with modern styling
          <div className={`markdown-content ${variant}`}>
            <ReactMarkdown
              remarkPlugins={[remarkGfm, remarkBreaks]}
              rehypePlugins={[rehypeHighlight, rehypeRaw]}
              components={markdownComponents}
            >
              {processedContent}
            </ReactMarkdown>
          </div>
        ) : (
          // Render plain text with enhanced formatting
          <div className={`
            markdown-content ${variant} whitespace-pre-wrap
            ${fontSize === 'lg' ? 'text-lg' : fontSize === 'sm' ? 'text-sm' : 'text-base'}
            ${lineHeight === 'tight' ? 'leading-tight' : lineHeight === 'relaxed' ? 'leading-relaxed' : 'leading-normal'}
            text-theme-primary
            ${enableReadingMode ? 'prose-style' : ''}
          `}>
            {content}
          </div>
        )
      ) : (
        <div className="text-center py-12 italic text-theme-tertiary">
          No content available
        </div>
      )}
    </div>
  );
};