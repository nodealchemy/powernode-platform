import React from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';

interface PaginationProps {
  currentPage: number;
  totalPages: number;
  onPageChange: (page: number) => void;
}

const Pagination: React.FC<PaginationProps> = ({
  currentPage,
  totalPages,
  onPageChange
}) => {
  if (totalPages <= 1) return null;

  const generatePageNumbers = () => {
    const pages: (number | string)[] = [];
    const delta = 2; // How many pages to show on each side of current page

    // Always show first page
    pages.push(1);

    // Add ellipsis if there's a gap
    if (currentPage - delta > 2) {
      pages.push('...');
    }

    // Add pages around current page
    const start = Math.max(2, currentPage - delta);
    const end = Math.min(totalPages - 1, currentPage + delta);

    for (let i = start; i <= end; i++) {
      pages.push(i);
    }

    // Add ellipsis if there's a gap
    if (currentPage + delta < totalPages - 1) {
      pages.push('...');
    }

    // Always show last page (if not already included)
    if (totalPages > 1) {
      pages.push(totalPages);
    }

    return pages;
  };

  return (
    <div className="flex items-center justify-center space-x-2">
      {/* Previous button */}
      <button
        onClick={() => onPageChange(currentPage - 1)}
        disabled={currentPage <= 1}
        className="flex items-center px-3 py-2 text-sm font-medium text-theme-secondary bg-theme-surface border border-theme rounded-lg hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-200"
      >
        <ChevronLeft className="w-4 h-4 mr-1" />
        Previous
      </button>

      {/* Page numbers */}
      <div className="flex items-center space-x-1">
        {generatePageNumbers().map((page, index) => (
          <React.Fragment key={index}>
            {typeof page === 'number' ? (
              <button
                onClick={() => onPageChange(page)}
                className={`px-3 py-2 text-sm font-medium rounded-lg transition-colors duration-200 ${
                  currentPage === page
                    ? 'bg-theme-interactive-primary text-white'
                    : 'text-theme-secondary bg-theme-surface border border-theme hover:bg-theme-surface-hover'
                }`}
              >
                {page}
              </button>
            ) : (
              <span className="px-2 py-2 text-sm text-theme-tertiary">
                {page}
              </span>
            )}
          </React.Fragment>
        ))}
      </div>

      {/* Next button */}
      <button
        onClick={() => onPageChange(currentPage + 1)}
        disabled={currentPage >= totalPages}
        className="flex items-center px-3 py-2 text-sm font-medium text-theme-secondary bg-theme-surface border border-theme rounded-lg hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-200"
      >
        Next
        <ChevronRight className="w-4 h-4 ml-1" />
      </button>
    </div>
  );
};

export default Pagination;