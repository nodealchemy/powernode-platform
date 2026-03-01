import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import MDEditor, { commands, ICommand } from '@uiw/react-md-editor';
import '@uiw/react-md-editor/markdown-editor.css';
import '@uiw/react-markdown-preview/markdown.css';
import { Page, PageFormData, pagesApi } from '@/features/content/pages/services/pagesApi';
import { useTheme } from '@/shared/hooks/ThemeContext';
import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';
import { ImageGalleryModal } from './ImageGalleryModal';

interface PageEditorProps {
  page?: Page | null;
  isCreating: boolean;
  onClose: () => void;
  onSuccess: (message: string) => void;
  onError: (message: string) => void;
}

export const PageEditor: React.FC<PageEditorProps> = ({
  page,
  isCreating,
  onClose,
  onSuccess,
  onError
}) => {
  const { theme } = useTheme();
  const [formData, setFormData] = useState<PageFormData>({
    title: '',
    content: '',
    meta_description: '',
    meta_keywords: '',
    status: 'draft'
  });
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState<'editor' | 'preview' | 'seo'>('editor');
  const [isImageGalleryOpen, setIsImageGalleryOpen] = useState(false);

  // Track cursor position for image insertion
  const cursorPositionRef = useRef<number | null>(null);
  const editorContainerRef = useRef<HTMLDivElement>(null);

  // Get cursor position from textarea inside MDEditor
  const getCursorPosition = useCallback((): number | null => {
    const textarea = editorContainerRef.current?.querySelector('textarea');
    if (textarea) {
      return textarea.selectionStart;
    }
    return null;
  }, []);

  // Open image gallery and capture cursor position
  const handleOpenImageGallery = useCallback(() => {
    cursorPositionRef.current = getCursorPosition();
    setIsImageGalleryOpen(true);
  }, [getCursorPosition]);

  // Custom image command that opens our gallery modal
  const customImageCommand: ICommand = useMemo(() => ({
    name: 'image',
    keyCommand: 'image',
    buttonProps: { 'aria-label': 'Add image', title: 'Add image' },
    icon: (
      <svg width="13" height="13" viewBox="0 0 20 20">
        <path
          fill="currentColor"
          d="M15 9c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm4-7H1c-.55 0-1 .45-1 1v14c0 .55.45 1 1 1h18c.55 0 1-.45 1-1V3c0-.55-.45-1-1-1zm-1 13l-6-5-2 2-4-5-4 8V4h16v11z"
        />
      </svg>
    ),
    execute: () => {
      handleOpenImageGallery();
    },
  }), [handleOpenImageGallery]);

  // Custom toolbar commands - replace default image command with our custom one
  const editorCommands = useMemo(() => [
    commands.bold,
    commands.italic,
    commands.strikethrough,
    commands.hr,
    commands.group([commands.title1, commands.title2, commands.title3, commands.title4, commands.title5, commands.title6], {
      name: 'title',
      groupName: 'title',
      buttonProps: { 'aria-label': 'Insert title' }
    }),
    commands.divider,
    commands.link,
    commands.quote,
    commands.code,
    commands.codeBlock,
    customImageCommand,
    commands.divider,
    commands.unorderedListCommand,
    commands.orderedListCommand,
    commands.checkedListCommand,
  ], [customImageCommand]);

  // Handle image insertion from gallery
  const handleImageSelect = useCallback((imageUrl: string, altText: string) => {
    const imageMarkdown = `![${altText}](${imageUrl})`;
    const content = formData.content || '';
    const cursorPos = cursorPositionRef.current;

    let newContent: string;

    if (cursorPos !== null && cursorPos >= 0 && cursorPos <= content.length) {
      // Insert at cursor position with proper spacing
      const before = content.slice(0, cursorPos);
      const after = content.slice(cursorPos);

      // Add newlines for spacing if needed
      const needsNewlineBefore = before.length > 0 && !before.endsWith('\n\n');
      const needsNewlineAfter = after.length > 0 && !after.startsWith('\n');

      newContent = before
        + (needsNewlineBefore && before.length > 0 ? '\n\n' : '')
        + imageMarkdown
        + (needsNewlineAfter && after.length > 0 ? '\n\n' : '')
        + after;
    } else {
      // Fallback: append at end
      newContent = content
        ? `${content}\n\n${imageMarkdown}`
        : imageMarkdown;
    }

    setFormData(prev => ({
      ...prev,
      content: newContent
    }));

    // Reset cursor position
    cursorPositionRef.current = null;
  }, [formData.content]);

  useEffect(() => {
    if (page) {
      setFormData({
        title: page.title,
        content: page.content,
        meta_description: page.meta_description || '',
        meta_keywords: page.meta_keywords || '',
        status: page.status === 'published' ? 'published' : 'draft'
      });
    }
  }, [page]);

  // Generate preview slug from title
  const previewSlug = pagesApi.generateSlug(formData.title || '');

  // Extract excerpt from content (first 200 chars)
  const contentExcerpt = (formData.content || '').replace(/[#*`]/g, '').slice(0, 200);

  const handleSave = async (newStatus?: 'draft' | 'published') => {
    if (!formData.title?.trim()) {
      onError('Title is required');
      return;
    }

    if (!formData.content?.trim()) {
      onError('Content is required');
      return;
    }

    try {
      setSaving(true);
      const dataToSave = {
        ...formData,
        status: newStatus || formData.status
      };

      if (isCreating) {
        await pagesApi.createPage(dataToSave);
        onSuccess(`Page "${formData.title}" has been created successfully`);
      } else if (page) {
        await pagesApi.updatePage(page.id, dataToSave);
        onSuccess(`Page "${formData.title}" has been updated successfully`);
      }
      
      onClose();
    } catch (error) {
      const httpError = error as { response?: { data?: { error?: string } } };
      onError(httpError.response?.data?.error || 'Failed to save page');
    } finally {
      setSaving(false);
    }
  };

  const handleSaveAndPublish = () => {
    handleSave('published');
  };

  const handleSaveAsDraft = () => {
    handleSave('draft');
  };

  return (
    <div className="min-h-screen bg-theme-background-secondary">
      {/* Header */}
      <div className="card-theme border-b border-theme">
        <div className="px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-xl font-bold text-theme-primary">
                {isCreating ? 'Create New Page' : `Edit "${page?.title}"`}
              </h1>
              <p className="text-sm text-theme-secondary mt-1">
                {previewSlug && `Preview URL: /${previewSlug}`}
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <button
                onClick={onClose}
                className="btn-theme btn-theme-secondary"
                disabled={saving}
              >
                Cancel
              </button>
              <button
                onClick={handleSaveAsDraft}
                className="btn-theme btn-theme-secondary"
                disabled={saving || !formData.title?.trim() || !formData.content?.trim()}
              >
                {saving ? 'Saving...' : 'Save Draft'}
              </button>
              <button
                onClick={handleSaveAndPublish}
                className="btn-theme btn-theme-primary"
                disabled={saving || !formData.title?.trim() || !formData.content?.trim()}
              >
                {saving ? 'Publishing...' : 'Save & Publish'}
              </button>
            </div>
          </div>

          {/* Tabs */}
          <div className="flex space-x-8 mt-4 -mb-px overflow-x-auto scrollbar-hide">
            {(['editor', 'preview', 'seo'] as const).map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`py-2 px-1 border-b-2 font-medium text-sm capitalize ${
                  activeTab === tab
                    ? 'border-theme-focus text-theme-link'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                }`}
              >
                {tab === 'seo' ? 'SEO' : tab}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        {activeTab === 'editor' && (
          <div className="space-y-6">
            {/* Title */}
            <div className="card-theme p-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">
                    Page Title *
                  </label>
                  <input
                    type="text"
                    value={formData.title}
                    onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                    className="input-theme"
                    placeholder="Enter page title"
                  />
                </div>
                <div>
                  <label className="label-theme">
                    Status
                  </label>
                  <select
                    value={formData.status}
                    onChange={(e) => setFormData({ ...formData, status: e.target.value as 'draft' | 'published' })}
                    className="select-theme"
                  >
                    <option value="draft">Draft</option>
                    <option value="published">Published</option>
                  </select>
                </div>
              </div>
              {previewSlug && (
                <div className="mt-4 p-3 bg-theme-background-secondary rounded-lg">
                  <p className="text-sm text-theme-secondary">
                    <strong>URL Preview:</strong> /{previewSlug}
                  </p>
                </div>
              )}
            </div>

            {/* Content Editor */}
            <div className="card-theme">
              <div className="px-6 py-4 border-b border-theme">
                <h3 className="text-lg font-medium text-theme-primary">Content</h3>
                <p className="text-sm text-theme-secondary mt-1">
                  Write your page content using Markdown. Use the toolbar for formatting help.
                </p>
              </div>
              <div className="p-6">
                <div ref={editorContainerRef} data-color-mode={theme} className="w-full">
                  <MDEditor
                    value={formData.content}
                    onChange={(value) => setFormData({ ...formData, content: value || '' })}
                    height={500}
                    preview="edit"
                    hideToolbar={false}
                    data-color-mode={theme}
                    commands={editorCommands}
                  />
                </div>
                <div className="mt-4 text-sm text-theme-secondary">
                  <strong>Markdown Tips:</strong>
                  <ul className="mt-2 space-y-1">
                    <li>• Use # for headings (# H1, ## H2, ### H3)</li>
                    <li>• Use **bold** and *italic* for emphasis</li>
                    <li>• Use [link text](URL) for links</li>
                    <li>• Use ![alt text](image-url) for images</li>
                    <li>• Use - or * for bullet lists</li>
                    <li>• Use ``` for code blocks</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'preview' && (
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-medium text-theme-primary">Preview</h3>
              <p className="text-sm text-theme-secondary mt-1">
                Preview how your page will look to visitors.
              </p>
            </div>
            <div className="p-6">
              {formData.content ? (
                <MarkdownRenderer
                  content={formData.content}
                  variant="preview"
                  className="w-full"
                />
              ) : (
                <div className="text-center py-12">
                  <p className="text-theme-secondary">No content to preview. Add some content in the editor tab.</p>
                </div>
              )}
            </div>
          </div>
        )}

        {activeTab === 'seo' && (
          <div className="space-y-6">
            <div className="card-theme p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">SEO Settings</h3>
              <div className="space-y-4">
                <div>
                  <label className="label-theme">
                    Meta Description
                  </label>
                  <textarea
                    value={formData.meta_description}
                    onChange={(e) => setFormData({ ...formData, meta_description: e.target.value })}
                    className="input-theme"
                    rows={3}
                    maxLength={160}
                    placeholder="Brief description for search engines (recommended: 120-160 characters)"
                  />
                  <div className="mt-1 text-xs text-theme-tertiary">
                    {formData.meta_description?.length || 0}/160 characters
                  </div>
                </div>
                <div>
                  <label className="label-theme">
                    Meta Keywords
                  </label>
                  <input
                    type="text"
                    value={formData.meta_keywords}
                    onChange={(e) => setFormData({ ...formData, meta_keywords: e.target.value })}
                    className="input-theme"
                    placeholder="keyword1, keyword2, keyword3"
                  />
                  <div className="mt-1 text-xs text-theme-tertiary">
                    Separate keywords with commas
                  </div>
                </div>
              </div>
            </div>

            {/* SEO Preview */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Search Engine Preview</h3>
              <div className="border border-theme rounded-lg p-4 bg-theme-background-secondary">
                <div className="text-theme-link text-lg hover:underline cursor-pointer">
                  {formData.title || 'Page Title'}
                </div>
                <div className="text-theme-success text-sm">
                  yoursite.com/{previewSlug || 'page-slug'}
                </div>
                <div className="text-theme-secondary text-sm mt-2">
                  {formData.meta_description || contentExcerpt || 'No description available.'}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Image Gallery Modal */}
      <ImageGalleryModal
        isOpen={isImageGalleryOpen}
        onClose={() => setIsImageGalleryOpen(false)}
        onImageSelect={handleImageSelect}
        pageId={page?.id}
      />
    </div>
  );
};