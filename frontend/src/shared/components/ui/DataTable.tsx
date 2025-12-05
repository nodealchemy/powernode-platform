import React from 'react';
import { ChevronLeft, ChevronRight, Loader2 } from 'lucide-react';
import { Button } from './Button';

export interface DataTableColumn<T = any> {
  key: string;
  header: React.ReactNode;
  render?: (item: T) => React.ReactNode;
  sortable?: boolean;
  width?: string;
}

export interface DataTableEmptyState {
  icon?: React.ComponentType<{ className?: string }>;
  title: string;
  description: string;
  action?: {
    label: string;
    onClick: () => void;
  };
}

export interface DataTablePagination {
  current_page: number;
  total_pages: number;
  total_count: number;
  per_page: number;
}

export interface DataTableProps<T = any> {
  columns: DataTableColumn<T>[];
  data?: T[];
  loading?: boolean;
  pagination?: DataTablePagination;
  onPageChange?: (page: number) => void;
  onRowClick?: (item: T) => void;
  emptyState?: DataTableEmptyState;
  className?: string;
}

export const DataTable = <T extends Record<string, any>>({
  columns,
  data = [],
  loading = false,
  pagination,
  onPageChange,
  onRowClick,
  emptyState,
  className = ''
}: DataTableProps<T>) => {
  const renderCell = (item: T, column: DataTableColumn<T>) => {
    if (!item) return '-';
    if (column.render) {
      return column.render(item);
    }
    return item[column.key] || '-';
  };

  const renderEmptyState = () => {
    if (!emptyState) {
      return (
        <tr>
          <td colSpan={columns.length} className="px-6 py-12 text-center text-theme-muted">
            No data available
          </td>
        </tr>
      );
    }

    const IconComponent = emptyState.icon;

    return (
      <tr>
        <td colSpan={columns.length} className="px-6 py-12">
          <div className="text-center">
            {IconComponent && (
              <IconComponent className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
            )}
            <h3 className="text-lg font-medium text-theme-primary mb-2">
              {emptyState.title}
            </h3>
            <p className="text-theme-muted mb-4">
              {emptyState.description}
            </p>
            {emptyState.action && (
              <Button
                onClick={emptyState.action.onClick}
                variant="primary"
              >
                {emptyState.action.label}
              </Button>
            )}
          </div>
        </td>
      </tr>
    );
  };

  const renderPagination = () => {
    if (!pagination || !onPageChange) return null;

    const { current_page, total_pages, total_count } = pagination;

    // Don't render pagination if there are no results
    if (total_count === 0) return null;

    const hasNextPage = current_page < total_pages;
    const hasPrevPage = current_page > 1;

    return (
      <div className="flex items-center justify-between px-6 py-3 bg-theme-surface">
        <div className="text-sm text-theme-muted">
          Showing {((current_page - 1) * pagination.per_page) + 1} to{' '}
          {Math.min(current_page * pagination.per_page, pagination.total_count)} of{' '}
          {pagination.total_count} results
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => onPageChange(current_page - 1)}
            disabled={!hasPrevPage}
          >
            <ChevronLeft className="h-4 w-4" />
            Previous
          </Button>
          <span className="text-sm text-theme-muted">
            Page {current_page} of {total_pages}
          </span>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onPageChange(current_page + 1)}
            disabled={!hasNextPage}
          >
            Next
            <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>
    );
  };

  return (
    <div className={`bg-theme-surface border border-theme rounded-lg overflow-hidden ${className}`}>
      <div className="overflow-x-auto">
        <table className="min-w-full border-separate border-spacing-y-1">
          <thead className="bg-theme-background">
            <tr>
              {columns.map((column) => (
                <th
                  key={column.key}
                  className="px-6 py-4 text-left text-xs font-semibold text-theme-secondary uppercase tracking-wider"
                  style={column.width ? { width: column.width } : undefined}
                >
                  {column.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="bg-theme-surface space-y-1">
            {loading ? (
              <tr>
                <td colSpan={columns.length} className="px-6 py-12 text-center">
                  <div className="flex items-center justify-center">
                    <Loader2 className="h-6 w-6 animate-spin text-theme-primary" />
                    <span className="ml-2 text-theme-muted">Loading...</span>
                  </div>
                </td>
              </tr>
            ) : !data || data.length === 0 ? (
              renderEmptyState()
            ) : (
              data.map((item, index) => (
                <tr
                  key={item.id || index}
                  className={`bg-theme-background hover:bg-theme-surface-hover transition-colors rounded-lg ${
                    onRowClick ? 'cursor-pointer' : ''
                  }`}
                  onClick={() => onRowClick && onRowClick(item)}
                >
                  {columns.map((column) => (
                    <td
                      key={column.key}
                      className="px-6 py-6 whitespace-nowrap text-sm text-theme-primary first:rounded-l-lg last:rounded-r-lg"
                      style={column.width ? { width: column.width } : undefined}
                    >
                      {renderCell(item, column)}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      {renderPagination()}
    </div>
  );
};