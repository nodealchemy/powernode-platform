import { render, screen, fireEvent } from '@testing-library/react';
import Pagination from './Pagination';

describe('Pagination', () => {
  const defaultProps = {
    currentPage: 1,
    totalPages: 10,
    onPageChange: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders nothing when totalPages is 1', () => {
      const { container } = render(
        <Pagination currentPage={1} totalPages={1} onPageChange={jest.fn()} />
      );

      expect(container.firstChild).toBeNull();
    });

    it('renders nothing when totalPages is 0', () => {
      const { container } = render(
        <Pagination currentPage={1} totalPages={0} onPageChange={jest.fn()} />
      );

      expect(container.firstChild).toBeNull();
    });

    it('renders pagination controls when totalPages > 1', () => {
      render(<Pagination {...defaultProps} />);

      expect(screen.getByText('Previous')).toBeInTheDocument();
      expect(screen.getByText('Next')).toBeInTheDocument();
    });

    it('renders page numbers', () => {
      render(<Pagination {...defaultProps} totalPages={4} currentPage={2} />);

      expect(screen.getByText('1')).toBeInTheDocument();
      expect(screen.getByText('2')).toBeInTheDocument();
      expect(screen.getByText('3')).toBeInTheDocument();
      expect(screen.getByText('4')).toBeInTheDocument();
    });
  });

  describe('previous button', () => {
    it('is disabled on first page', () => {
      render(<Pagination {...defaultProps} currentPage={1} />);

      const prevButton = screen.getByText('Previous').closest('button');
      expect(prevButton).toBeDisabled();
    });

    it('is enabled when not on first page', () => {
      render(<Pagination {...defaultProps} currentPage={5} />);

      const prevButton = screen.getByText('Previous').closest('button');
      expect(prevButton).not.toBeDisabled();
    });

    it('calls onPageChange with previous page', () => {
      const onPageChange = jest.fn();
      render(<Pagination {...defaultProps} currentPage={5} onPageChange={onPageChange} />);

      fireEvent.click(screen.getByText('Previous'));

      expect(onPageChange).toHaveBeenCalledWith(4);
    });
  });

  describe('next button', () => {
    it('is disabled on last page', () => {
      render(<Pagination {...defaultProps} currentPage={10} />);

      const nextButton = screen.getByText('Next').closest('button');
      expect(nextButton).toBeDisabled();
    });

    it('is enabled when not on last page', () => {
      render(<Pagination {...defaultProps} currentPage={5} />);

      const nextButton = screen.getByText('Next').closest('button');
      expect(nextButton).not.toBeDisabled();
    });

    it('calls onPageChange with next page', () => {
      const onPageChange = jest.fn();
      render(<Pagination {...defaultProps} currentPage={5} onPageChange={onPageChange} />);

      fireEvent.click(screen.getByText('Next'));

      expect(onPageChange).toHaveBeenCalledWith(6);
    });
  });

  describe('page number clicks', () => {
    it('calls onPageChange when clicking page number', () => {
      const onPageChange = jest.fn();
      render(<Pagination {...defaultProps} onPageChange={onPageChange} />);

      fireEvent.click(screen.getByText('3'));

      expect(onPageChange).toHaveBeenCalledWith(3);
    });

    it('calls onPageChange when clicking last page', () => {
      const onPageChange = jest.fn();
      render(<Pagination {...defaultProps} onPageChange={onPageChange} />);

      fireEvent.click(screen.getByText('10'));

      expect(onPageChange).toHaveBeenCalledWith(10);
    });
  });

  describe('ellipsis rendering', () => {
    it('shows ellipsis when there are gaps in page numbers', () => {
      render(<Pagination {...defaultProps} currentPage={5} />);

      const ellipses = screen.getAllByText('...');
      expect(ellipses.length).toBeGreaterThanOrEqual(1);
    });

    it('does not show ellipsis for small number of pages', () => {
      render(<Pagination {...defaultProps} totalPages={4} />);

      expect(screen.queryByText('...')).not.toBeInTheDocument();
    });

    it('shows ellipsis only after first page when on early pages', () => {
      render(<Pagination {...defaultProps} currentPage={1} />);

      // Only one ellipsis at start
      const ellipses = screen.queryAllByText('...');
      expect(ellipses.length).toBe(1);
    });
  });

  describe('current page styling', () => {
    it('highlights current page', () => {
      render(<Pagination {...defaultProps} currentPage={3} />);

      const currentPageButton = screen.getByText('3');
      expect(currentPageButton).toHaveClass('bg-theme-interactive-primary', 'text-white');
    });

    it('does not highlight other pages', () => {
      render(<Pagination {...defaultProps} currentPage={3} />);

      const otherPageButton = screen.getByText('1');
      expect(otherPageButton).not.toHaveClass('bg-theme-interactive-primary');
    });
  });

  describe('edge cases', () => {
    it('handles 2 pages correctly', () => {
      render(<Pagination {...defaultProps} totalPages={2} currentPage={1} />);

      expect(screen.getByText('1')).toBeInTheDocument();
      expect(screen.getByText('2')).toBeInTheDocument();
      expect(screen.queryByText('...')).not.toBeInTheDocument();
    });

    it('handles last page correctly', () => {
      const onPageChange = jest.fn();
      render(<Pagination {...defaultProps} currentPage={10} onPageChange={onPageChange} />);

      const nextButton = screen.getByText('Next').closest('button');
      expect(nextButton).toBeDisabled();
    });

    it('handles middle page correctly', () => {
      render(<Pagination {...defaultProps} currentPage={5} />);

      // Should show pages around current (3, 4, 5, 6, 7)
      expect(screen.getByText('3')).toBeInTheDocument();
      expect(screen.getByText('4')).toBeInTheDocument();
      expect(screen.getByText('5')).toBeInTheDocument();
      expect(screen.getByText('6')).toBeInTheDocument();
      expect(screen.getByText('7')).toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('centers pagination controls', () => {
      const { container } = render(<Pagination {...defaultProps} />);

      expect(container.firstChild).toHaveClass('flex', 'items-center', 'justify-center');
    });

    it('has proper button styling', () => {
      render(<Pagination {...defaultProps} />);

      const prevButton = screen.getByText('Previous').closest('button');
      expect(prevButton).toHaveClass('text-sm', 'font-medium', 'rounded-lg');
    });
  });
});
