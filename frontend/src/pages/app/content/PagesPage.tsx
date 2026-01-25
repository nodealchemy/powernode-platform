import React, { useState, useEffect, useCallback } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState, AppDispatch } from '@/shared/services';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { pagesApi, Page } from '@/features/content/pages/services/pagesApi';
import { PageEditor } from '@/features/content/pages/components/PageEditor';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { Plus, RefreshCw, Edit2, Eye, EyeOff, Copy, Trash2 } from 'lucide-react';

export const PagesPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { user } = useSelector((state: RootState) => state.auth);
  const { confirm, ConfirmationDialog } = useConfirmation();
  usePageWebSocket({ pageType: 'content' });
  const [pages, setPages] = useState<Page[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedPage, setSelectedPage] = useState<Page | null>(null);
  const [showEditor, setShowEditor] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [filters, setFilters] = useState({
    search: '',
    status: 'all' as 'all' | 'draft' | 'published',
    currentPage: 1
  });
  const [totalPages, setTotalPages] = useState(1);

  // Check if user has page management permissions
  const canManagePages = hasPermissions(user, ['page.create', 'page.update', 'page.delete']);

  const loadPages = useCallback(async () => {
    try {
      setLoading(true);
      const response = await pagesApi.getPages({
        page: filters.currentPage,
        per_page: 10,
        status: filters.status !== 'all' ? filters.status : undefined,
        search: filters.search || undefined
      });
      setPages(response.data);
      setTotalPages(response.meta.total_pages);
    } catch (_error: unknown) {
      dispatch(addNotification({
        type: 'error',
        message: 'Failed to load pages'
      }));
    } finally {
      setLoading(false);
    }
  }, [filters.currentPage, filters.status, filters.search, dispatch]);


  const handleCreatePage = () => {
    setSelectedPage(null);
    setIsCreating(true);
    setShowEditor(true);
  };

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadPages,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading,
      size: 'sm'
    },
    ...(canManagePages ? [{
      id: 'create-page',
      label: 'Create Page',
      onClick: handleCreatePage,
      variant: 'primary' as const,
      icon: Plus,
      size: 'sm' as const
    }] : [])
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Pages' }
  ];

  useEffect(() => {
    if (canManagePages) {
      // Load the pages list (for admin users)
      loadPages();
    }
  }, [canManagePages, filters, loadPages]);

  const showSuccess = (message: string) => {
    dispatch(addNotification({
      type: 'success',
      message
    }));
  };

  const showError = (message: string) => {
    dispatch(addNotification({
      type: 'error',
      message
    }));
  };

  const handleViewPage = async (page: Page) => {
    // Open the public page in a new tab
    window.open(`/pages/${page.slug}`, '_blank');
  };

  const handleEditPage = async (page: Page) => {
    try {
      // Fetch the full page data including content
      const response = await pagesApi.getPage(page.id);
      setSelectedPage(response.data);
      setIsCreating(false);
      setShowEditor(true);
    } catch (_error) {
      showError('Failed to load page for editing');
    }
  };

  const handleCloseEditor = () => {
    setShowEditor(false);
    setSelectedPage(null);
    setIsCreating(false);
    loadPages(); // Refresh the list
  };


  const handlePublishToggle = async (page: Page) => {
    try {
      if (page.status === 'published') {
        await pagesApi.unpublishPage(page.id);
        showSuccess(`"${page.title}" has been unpublished`);
      } else {
        await pagesApi.publishPage(page.id);
        showSuccess(`"${page.title}" has been published`);
      }
      loadPages();
    } catch (_error) {
      showError(`Failed to ${page.status === 'published' ? 'unpublish' : 'publish'} page`);
    }
  };

  const handleDuplicatePage = async (page: Page) => {
    try {
      await pagesApi.duplicatePage(page.id);
      showSuccess(`"${page.title}" has been duplicated`);
      loadPages();
    } catch (_error) {
      showError('Failed to duplicate page');
    }
  };

  const handleDeletePage = (page: Page) => {
    confirm({
      title: 'Delete Page',
      message: `Are you sure you want to delete "${page.title}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await pagesApi.deletePage(page.id);
          showSuccess(`"${page.title}" has been deleted`);
          loadPages();
        } catch (_error) {
          showError('Failed to delete page');
        }
      }
    });
  };

  const getStatusBadge = (status: string | undefined) => {
    const colorClass = pagesApi.getStatusColor(status);
    
    let colorClassValue: string;
    switch (colorClass) {
      case 'green':
        colorClassValue = 'bg-theme-success text-theme-success';
        break;
      case 'yellow':
        colorClassValue = 'bg-theme-warning text-theme-warning';
        break;
      case 'gray':
        colorClassValue = 'bg-theme-background-tertiary text-theme-secondary';
        break;
      default:
        colorClassValue = 'bg-theme-background-tertiary text-theme-secondary';
    }

    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${colorClassValue}`}>
        {pagesApi.formatStatus(status)}
      </span>
    );
  };


  if (showEditor) {
    return (
      <PageEditor
        page={selectedPage}
        isCreating={isCreating}
        onClose={handleCloseEditor}
        onSuccess={showSuccess}
        onError={showError}
      />
    );
  }
  
  // Redirect non-admins from the pages list
  if (!canManagePages) {
    return <Navigate to="/app" replace />;
  }

  const getPageDescription = () => {
    if (!canManagePages) return "Access denied";
    return "Manage your website pages and content.";
  };

  const getPageActions = () => {
    if (!canManagePages) return [];
    return pageActions;
  };

  return (
    <PageContainer
      title="Pages"
      description={getPageDescription()}
      breadcrumbs={breadcrumbs}
      actions={getPageActions()}
    >
      {!canManagePages ? (
        <div className="text-center py-12">
          <div className="text-theme-error text-lg font-medium">
            🚫 Access Denied
          </div>
          <p className="text-theme-secondary mt-2">
            You need administrator privileges to manage pages.
          </p>
        </div>
      ) : (
        <>
          {/* Filters */}
          <div className="card-theme p-6">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
            <label className="label-theme">Search</label>
            <input
              type="text"
              placeholder="Search pages..."
              value={filters.search}
              onChange={(e) => setFilters({ ...filters, search: e.target.value, currentPage: 1 })}
              className="input-theme"
            />
          </div>
          <div>
            <label className="label-theme">Status</label>
            <select
              value={filters.status}
              onChange={(e) => setFilters({ ...filters, status: e.target.value as typeof filters.status, currentPage: 1 })}
              className="select-theme"
            >
              <option value="all">All Status</option>
              <option value="draft">Draft</option>
              <option value="published">Published</option>
            </select>
          </div>
          <div className="flex items-end">
            <button
              onClick={loadPages}
              className="btn-theme btn-theme-secondary"
            >
              Refresh
            </button>
          </div>
        </div>
      </div>

      {/* Pages List */}
      <div className="card-theme">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-medium text-theme-primary">Pages List</h3>
        </div>
        
        {loading ? (
          <div className="p-6 text-center">
            <div className="animate-spin h-8 w-8 border-b-2 border-theme-link mx-auto mb-2"></div>
            <p className="text-theme-secondary">Loading pages...</p>
          </div>
        ) : pages.length === 0 ? (
          <div className="p-12 text-center">
            <div className="text-6xl mb-4">📄</div>
            <h3 className="text-lg font-medium text-theme-primary mb-2">No pages yet</h3>
            <p className="text-theme-secondary mb-4">Create your first page to get started.</p>
            <button
              onClick={handleCreatePage}
              className="btn-theme btn-theme-primary"
            >
              Create Page
            </button>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-theme">
              <thead className="bg-theme-background-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Title
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Published
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Word Count
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-theme-surface divide-y divide-theme">
                {pages.map((page) => (
                  <tr 
                    key={page.id} 
                    className="hover:bg-theme-surface-hover transition-colors"
                  >
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary hover:text-theme-link">{page.title}</div>
                        <div className="text-xs text-theme-tertiary mt-1">
                          <a 
                            href={`/pages/${page.slug}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-theme-link hover:text-theme-link-hover underline font-mono inline-flex items-center gap-1"
                            onClick={(e) => e.stopPropagation()}
                          >
                            /pages/{page.slug}
                            <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                            </svg>
                          </a>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {getStatusBadge(page.status)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {pagesApi.formatPublishedDate(page.published_at)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {page.word_count || 0} words
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                      <div 
                        className="flex items-center space-x-1"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <Button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleViewPage(page);
                          }}
                          variant="outline"
                          size="sm"
                          iconOnly
                          title="View public page"
                        >
                          <Eye className="w-4 h-4" />
                        </Button>
                        <Button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleEditPage(page);
                          }}
                          variant="secondary"
                          size="sm"
                          iconOnly
                          title="Edit page"
                        >
                          <Edit2 className="w-4 h-4" />
                        </Button>
                        <Button
                          onClick={(e) => {
                            e.stopPropagation();
                            handlePublishToggle(page);
                          }}
                          variant={page.status === 'published' ? 'warning' : 'success'}
                          size="sm"
                          iconOnly
                          title={page.status === 'published' ? 'Unpublish page' : 'Publish page'}
                        >
                          {page.status === 'published' ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </Button>
                        <Button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleDuplicatePage(page);
                          }}
                          variant="outline"
                          size="sm"
                          iconOnly
                          title="Duplicate page"
                        >
                          <Copy className="w-4 h-4" />
                        </Button>
                        <Button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleDeletePage(page);
                          }}
                          variant="danger"
                          size="sm"
                          iconOnly
                          title="Delete page"
                        >
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="px-6 py-4 border-t border-theme">
            <div className="flex justify-between items-center">
              <div className="text-sm text-theme-secondary">
                Page {filters.currentPage} of {totalPages}
              </div>
              <div className="space-x-2">
                <button
                  onClick={() => setFilters({ ...filters, currentPage: filters.currentPage - 1 })}
                  disabled={filters.currentPage === 1}
                  className="btn-theme btn-theme-secondary btn-theme-sm disabled:opacity-50"
                >
                  Previous
                </button>
                <button
                  onClick={() => setFilters({ ...filters, currentPage: filters.currentPage + 1 })}
                  disabled={filters.currentPage === totalPages}
                  className="btn-theme btn-theme-secondary btn-theme-sm disabled:opacity-50"
                >
                  Next
                </button>
              </div>
            </div>
          </div>
        )}
          </div>
        </>
      )}
      {ConfirmationDialog}
    </PageContainer>
  );
};