import React, { useState, useEffect, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { addNotification } from '@/shared/services/slices/uiSlice';
import MDEditor from '@uiw/react-md-editor';
import '@uiw/react-md-editor/markdown-editor.css';
import '@uiw/react-markdown-preview/markdown.css';
import { Badge } from '@/shared/components/ui/Badge';
import { knowledgeBaseAdminApi, KbCategory } from '@/shared/services/content/knowledgeBaseApi';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { useTheme } from '@/shared/hooks/ThemeContext';
import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';
import {
  ArrowDownTrayIcon as SaveIcon,
  EyeIcon,
  CheckIcon,
  XMarkIcon
} from '@heroicons/react/24/outline';

interface ArticleFormData {
  title: string;
  slug: string;
  content: string;
  excerpt: string;
  category_id: string;
  tags: string[];
  status: 'draft' | 'review' | 'published';
  is_featured: boolean;
  is_public: boolean;
  meta_title: string;
  meta_description: string;
  sort_order: number;
}

export function KnowledgeBaseArticleEditor() {
  const { id: articleId } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const dispatch = useDispatch<AppDispatch>();
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const { theme } = useTheme();
  
  const [activeTab, setActiveTab] = useState<'editor' | 'settings' | 'seo' | 'preview'>('editor');
  const [categories, setCategories] = useState<KbCategory[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);
  
  const [formData, setFormData] = useState<ArticleFormData>({
    title: '',
    slug: '',
    content: '',
    excerpt: '',
    category_id: '',
    tags: [],
    status: 'draft',
    is_featured: false,
    is_public: true,
    meta_title: '',
    meta_description: '',
    sort_order: 0
  });

  const [tagInput, setTagInput] = useState('');

  // Permission checks
  const canManageKb = hasPermissions(currentUser, ['kb.manage']);
  const canEditKb = hasPermissions(currentUser, ['kb.update']) || canManageKb;
  const canPublish = hasPermissions(currentUser, ['kb.publish']) || canManageKb;
  
  const isEditing = !!articleId && articleId !== 'new';
  const isNewArticle = articleId === 'new';

  // Auto-generate slug from title
  const generateSlug = (title: string) => {
    return title
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .trim();
  };

  // Generate preview slug (memoized to prevent re-renders)
  const previewSlug = useMemo(() => {
    return formData.slug || generateSlug(formData.title || '');
  }, [formData.slug, formData.title]);
  
  // Extract excerpt from content (memoized to prevent re-renders)
  const contentExcerpt = useMemo(() => {
    return (formData.excerpt || formData.content || '').replace(/[#*`]/g, '').slice(0, 200);
  }, [formData.excerpt, formData.content]);

  // Load data
  useEffect(() => {
    if (!canEditKb) {
      navigate('/app/content/kb');
      return;
    }

    const loadData = async () => {
      try {
        const response = await knowledgeBaseAdminApi.getCategories({ per_page: 100 });
        setCategories(response.data.data);
      } catch (error) {
        dispatch(addNotification({ type: 'error', message: 'Failed to load categories' }));
        console.error('Categories loading error:', error);
      }
    };

    const loadArticleData = async () => {
      if (!articleId || articleId === 'new') return;
      
      try {
        setIsLoading(true);
        const response = await knowledgeBaseAdminApi.getArticle(articleId);
        const article = response.data.data.article;
        
        setFormData({
          title: article.title || '',
          slug: article.slug || '',
          content: article.content || '',
          excerpt: article.excerpt || '',
          category_id: article.category_id || article.category?.id || '',
          tags: article.tags || [],
          status: (article.status as 'draft' | 'review' | 'published') || 'published',
          is_featured: article.is_featured || false,
          is_public: article.is_public !== undefined ? article.is_public : true,
          meta_title: article.meta_title || article.metadata?.meta_title || '',
          meta_description: article.meta_description || article.metadata?.meta_description || '',
          sort_order: article.sort_order || article.metadata?.sort_order || 0
        });
      } catch (error) {
        dispatch(addNotification({ type: 'error', message: 'Failed to load article' }));
        console.error('Article loading error:', error);
        navigate('/app/content/kb');
      } finally {
        setIsLoading(false);
      }
    };

    loadData();
    
    if (isEditing) {
      loadArticleData();
    }
  }, [canEditKb, isEditing, articleId, navigate]);

  // Functions moved into useEffect to avoid dependency issues

  // Handle form field updates
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const updateField = (field: keyof ArticleFormData, value: any) => {
    setFormData(prev => {
      const updated = { ...prev, [field]: value };
      
      // Auto-generate slug from title if slug is empty
      if (field === 'title' && !prev.slug) {
        updated.slug = generateSlug(value);
      }
      
      // Auto-generate meta title if empty
      if (field === 'title' && !prev.meta_title) {
        updated.meta_title = value;
      }
      
      return updated;
    });
  };

  // Handle tag management
  const addTag = (tag: string) => {
    const trimmedTag = tag.trim();
    if (trimmedTag && !formData.tags.includes(trimmedTag)) {
      updateField('tags', [...formData.tags, trimmedTag]);
    }
  };

  const removeTag = (tagToRemove: string) => {
    updateField('tags', formData.tags.filter(tag => tag !== tagToRemove));
  };

  const handleTagKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && tagInput.trim()) {
      e.preventDefault();
      addTag(tagInput);
      setTagInput('');
    }
  };

  // Auto-save functionality (removed to prevent infinite re-renders)
  // Auto-save disabled for now to prevent page reloading issues

  // Image upload handler - available for future MD editor integration
  // Removed unused function to eliminate TypeScript warning

  // Save article
  const saveArticle = async (newStatus?: ArticleFormData['status']) => {
    if (!formData.title.trim()) {
      dispatch(addNotification({ type: 'error', message: 'Title is required' }));
      return;
    }

    if (!formData.category_id) {
      dispatch(addNotification({ type: 'error', message: 'Category is required' }));
      return;
    }

    try {
      setIsSaving(true);
      const dataToSave = {
        ...formData,
        status: newStatus || formData.status
      };

      let response;
      if (isEditing) {
        response = await knowledgeBaseAdminApi.updateArticle(articleId!, dataToSave);
      } else {
        response = await knowledgeBaseAdminApi.createArticle(dataToSave);
      }

      const article = response.data.data || response.data;
      
      dispatch(addNotification({
        type: 'success',
        message: isEditing ? 'Article updated successfully' : 'Article created successfully'
      }));

      setLastSaved(new Date());
      
      if (isNewArticle) {
        navigate(`/app/content/kb/articles/${article.id}/edit`);
      }
    } catch (error: unknown) {
      const apiError = error as { response?: { data?: { error?: string } } };
      const errorMessage = apiError.response?.data?.error || 'Failed to save article';
      dispatch(addNotification({ type: 'error', message: errorMessage }));
    } finally {
      setIsSaving(false);
    }
  };

  // Actions configuration - available for future toolbar implementation
  const _actions = [
    {
      id: 'save-draft',
      label: isSaving ? 'Saving...' : 'Save Draft',
      onClick: () => saveArticle('draft'),
      variant: 'secondary' as const,
      icon: SaveIcon,
      disabled: isSaving
    }
  ];

  if (canPublish) {
    if (formData.status !== 'published') {
      _actions.push({
        id: 'submit-review',
        label: 'Submit for Review',
        onClick: () => saveArticle('review'),
        variant: 'secondary' as const,
        icon: EyeIcon,
        disabled: isSaving
      });
    }

    if (formData.status === 'review' || formData.status === 'published') {
      _actions.push({
        id: 'publish',
        label: formData.status === 'published' ? 'Update Published' : 'Publish',
        onClick: () => saveArticle('published'),
        variant: 'secondary' as const,
        icon: CheckIcon,
        disabled: isSaving
      });
    }
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-theme-background-secondary">
        <div className="card-theme border-b border-theme">
          <div className="px-6 py-4">
            <h1 className="text-xl font-bold text-theme-primary">
              {isNewArticle ? 'Create Article' : 'Edit Article'}
            </h1>
          </div>
        </div>
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-focus"></div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-theme-background-secondary">
      {/* Header */}
      <div className="card-theme border-b border-theme">
        <div className="px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-xl font-bold text-theme-primary">
                {isNewArticle ? 'Create Article' : `Edit "${formData.title || 'Article'}"`}
              </h1>
              <p className="text-sm text-theme-secondary mt-1">
                {previewSlug && `Preview URL: /kb/articles/${previewSlug}`}
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <button
                onClick={() => navigate('/app/content/kb')}
                className="btn-theme btn-theme-secondary"
                disabled={isSaving}
              >
                Cancel
              </button>
              <button
                onClick={() => saveArticle('draft')}
                className="btn-theme btn-theme-secondary"
                disabled={isSaving || !formData.title?.trim() || !formData.content?.trim()}
              >
                {isSaving ? 'Saving...' : 'Save Draft'}
              </button>
              {canPublish && (
                <button
                  onClick={() => saveArticle('published')}
                  className="btn-theme btn-theme-primary"
                  disabled={isSaving || !formData.title?.trim() || !formData.content?.trim()}
                >
                  {isSaving ? 'Publishing...' : 'Save & Publish'}
                </button>
              )}
            </div>
          </div>

          {/* Tabs */}
          <div className="flex space-x-8 mt-4 -mb-px overflow-x-auto">
            {(['editor', 'settings', 'seo', 'preview'] as const).map((tab) => (
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
            {/* Title and Basic Settings */}
            <div className="card-theme p-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">
                    Article Title *
                  </label>
                  <input
                    type="text"
                    value={formData.title}
                    onChange={(e) => updateField('title', e.target.value)}
                    className="input-theme"
                    placeholder="Enter article title"
                  />
                </div>
                <div>
                  <label className="label-theme">
                    URL Slug
                  </label>
                  <input
                    type="text"
                    value={formData.slug}
                    onChange={(e) => updateField('slug', e.target.value)}
                    className="input-theme font-mono text-sm"
                    placeholder="article-url-slug"
                  />
                </div>
              </div>
              {previewSlug && (
                <div className="mt-4 p-3 bg-theme-background-secondary rounded-lg">
                  <p className="text-sm text-theme-secondary">
                    <strong>URL Preview:</strong> /kb/articles/{previewSlug}
                  </p>
                </div>
              )}
            </div>

            {/* Content Editor */}
            <div className="card-theme">
              <div className="px-6 py-4 border-b border-theme">
                <h3 className="text-lg font-medium text-theme-primary">Content</h3>
                <p className="text-sm text-theme-secondary mt-1">
                  Write your article content using Markdown. Use the toolbar for formatting help.
                </p>
              </div>
              <div className="p-6">
                <div data-color-mode={theme} className="w-full">
                  <MDEditor
                    value={formData.content}
                    onChange={(value) => updateField('content', value || '')}
                    height={500}
                    preview="edit"
                    hideToolbar={false}
                    data-color-mode={theme}
                  />
                </div>
                <div className="mt-4 text-sm text-theme-secondary">
                  <strong>Markdown Tips:</strong>
                  <ul className="mt-2 space-y-1">
                    <li>• Use # for headings (# H1, ## H2, ### H3)</li>
                    <li>• Use **bold** and *italic* for emphasis</li>
                    <li>• Use [link text](URL) for links</li>
                    <li>• Use - or * for bullet lists</li>
                    <li>• Use ``` for code blocks</li>
                  </ul>
                </div>
              </div>
            </div>

            {/* Excerpt */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Article Excerpt</h3>
              <div>
                <label className="label-theme">
                  Brief Summary
                </label>
                <textarea
                  value={formData.excerpt}
                  onChange={(e) => updateField('excerpt', e.target.value)}
                  className="input-theme"
                  rows={3}
                  maxLength={500}
                  placeholder="Brief summary of the article for previews and search results..."
                />
                <div className="mt-1 text-xs text-theme-tertiary">
                  {formData.excerpt.length}/500 characters
                </div>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'settings' && (
          <div className="space-y-6">
            <div className="card-theme p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Article Settings</h3>
              <div className="space-y-6">
                {/* Category and Status */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="label-theme">
                      Category *
                    </label>
                    <select
                      value={formData.category_id}
                      onChange={(e) => updateField('category_id', e.target.value)}
                      className="select-theme"
                    >
                      <option value="">Select a category</option>
                      {categories.map(category => (
                        <option key={category.id} value={category.id}>
                          {category.name}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="label-theme">
                      Status
                    </label>
                    <div className="flex items-center gap-2">
                      <Badge
                        variant={
                          formData.status === 'published' ? 'success' :
                          formData.status === 'review' ? 'primary' :
                          formData.status === 'draft' ? 'warning' : 'secondary'
                        }
                      >
                        {formData.status}
                      </Badge>
                      {lastSaved && (
                        <span className="text-xs text-theme-secondary">
                          Last saved: {lastSaved.toLocaleTimeString()}
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {/* Tags */}
                <div>
                  <label className="label-theme">
                    Tags
                  </label>
                  <div className="space-y-2">
                    <input
                      type="text"
                      value={tagInput}
                      onChange={(e) => setTagInput(e.target.value)}
                      onKeyDown={handleTagKeyPress}
                      className="input-theme"
                      placeholder="Type a tag and press Enter"
                    />
                    {formData.tags.length > 0 && (
                      <div className="flex flex-wrap gap-2">
                        {formData.tags.map(tag => (
                          <span
                            key={tag}
                            className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-surface border border-theme cursor-pointer hover:bg-theme-danger hover:text-white transition-colors"
                            onClick={() => removeTag(tag)}
                          >
                            {tag}
                            <XMarkIcon className="w-3 h-3 ml-1" />
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </div>

                {/* Options */}
                <div className="space-y-4">
                  <div className="flex items-center">
                    <input
                      type="checkbox"
                      id="is_public"
                      checked={formData.is_public}
                      onChange={(e) => updateField('is_public', e.target.checked)}
                      className="h-4 w-4 text-theme-primary focus:ring-theme-primary border-theme rounded"
                    />
                    <label htmlFor="is_public" className="ml-2 text-sm text-theme-primary">
                      Public article (visible to all users)
                    </label>
                  </div>

                  <div className="flex items-center">
                    <input
                      type="checkbox"
                      id="is_featured"
                      checked={formData.is_featured}
                      onChange={(e) => updateField('is_featured', e.target.checked)}
                      className="h-4 w-4 text-theme-primary focus:ring-theme-primary border-theme rounded"
                    />
                    <label htmlFor="is_featured" className="ml-2 text-sm text-theme-primary">
                      Featured article
                    </label>
                  </div>
                </div>

                {/* Sort Order */}
                <div>
                  <label className="label-theme">
                    Sort Order
                  </label>
                  <input
                    type="number"
                    value={formData.sort_order}
                    onChange={(e) => updateField('sort_order', parseInt(e.target.value) || 0)}
                    className="input-theme w-24"
                    placeholder="0"
                  />
                  <div className="mt-1 text-xs text-theme-tertiary">
                    Lower numbers appear first
                  </div>
                </div>
              </div>
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
                    Meta Title
                  </label>
                  <input
                    type="text"
                    value={formData.meta_title}
                    onChange={(e) => updateField('meta_title', e.target.value)}
                    className="input-theme"
                    maxLength={60}
                    placeholder={formData.title || "Enter meta title"}
                  />
                  <div className="mt-1 text-xs text-theme-tertiary">
                    {formData.meta_title.length}/60 characters
                  </div>
                </div>
                <div>
                  <label className="label-theme">
                    Meta Description
                  </label>
                  <textarea
                    value={formData.meta_description}
                    onChange={(e) => updateField('meta_description', e.target.value)}
                    className="input-theme"
                    rows={3}
                    maxLength={160}
                    placeholder={formData.excerpt || "Enter meta description for search engines"}
                  />
                  <div className="mt-1 text-xs text-theme-tertiary">
                    {formData.meta_description.length}/160 characters
                  </div>
                </div>
              </div>
            </div>

            {/* SEO Preview */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Search Engine Preview</h3>
              <div className="border border-theme rounded-lg p-4 bg-theme-background-secondary">
                <div className="text-theme-link text-lg hover:underline cursor-pointer">
                  {formData.meta_title || formData.title || 'Article Title'}
                </div>
                <div className="text-theme-success text-sm">
                  yoursite.com/kb/articles/{previewSlug || 'article-slug'}
                </div>
                <div className="text-theme-secondary text-sm mt-2">
                  {formData.meta_description || contentExcerpt || 'No description available.'}
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
                Preview how your article will look to readers.
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
      </div>
    </div>
  );
};