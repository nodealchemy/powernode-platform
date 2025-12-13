import { render, screen, fireEvent } from '@testing-library/react';
import { DataTable, DataTableColumn, DataTablePagination } from './DataTable';
import { FileText } from 'lucide-react';

describe('DataTable', () => {
  const defaultColumns: DataTableColumn[] = [
    { key: 'name', header: 'Name' },
    { key: 'email', header: 'Email' },
    { key: 'status', header: 'Status' },
  ];

  const defaultData = [
    { id: '1', name: 'John Doe', email: 'john@example.com', status: 'Active' },
    { id: '2', name: 'Jane Smith', email: 'jane@example.com', status: 'Inactive' },
    { id: '3', name: 'Bob Wilson', email: 'bob@example.com', status: 'Pending' },
  ];

  describe('rendering', () => {
    it('renders table with headers', () => {
      render(<DataTable columns={defaultColumns} data={defaultData} />);

      expect(screen.getByText('Name')).toBeInTheDocument();
      expect(screen.getByText('Email')).toBeInTheDocument();
      expect(screen.getByText('Status')).toBeInTheDocument();
    });

    it('renders data rows', () => {
      render(<DataTable columns={defaultColumns} data={defaultData} />);

      expect(screen.getByText('John Doe')).toBeInTheDocument();
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
      expect(screen.getByText('Pending')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(
        <DataTable columns={defaultColumns} data={defaultData} className="custom-class" />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });

    it('renders with column width', () => {
      const columnsWithWidth: DataTableColumn[] = [
        { key: 'name', header: 'Name', width: '200px' },
        { key: 'email', header: 'Email' },
      ];

      render(<DataTable columns={columnsWithWidth} data={defaultData} />);

      const nameHeader = screen.getByText('Name').closest('th');
      expect(nameHeader).toHaveStyle({ width: '200px' });
    });
  });

  describe('custom cell rendering', () => {
    it('uses custom render function', () => {
      const columnsWithRender: DataTableColumn[] = [
        { key: 'name', header: 'Name' },
        {
          key: 'status',
          header: 'Status',
          render: (item) => <span data-testid={`status-${item.id}`}>{item.status.toUpperCase()}</span>,
        },
      ];

      render(<DataTable columns={columnsWithRender} data={defaultData} />);

      expect(screen.getByTestId('status-1')).toHaveTextContent('ACTIVE');
      expect(screen.getByTestId('status-2')).toHaveTextContent('INACTIVE');
    });

    it('displays dash for missing values', () => {
      const dataWithMissing = [
        { id: '1', name: 'John Doe', email: null, status: 'Active' },
      ];

      render(<DataTable columns={defaultColumns} data={dataWithMissing} />);

      // Missing email should show dash
      const cells = screen.getAllByRole('cell');
      const emailCell = cells.find(cell => cell.textContent === '-');
      expect(emailCell).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading indicator when loading', () => {
      render(<DataTable columns={defaultColumns} loading />);

      expect(screen.getByText('Loading...')).toBeInTheDocument();
    });

    it('shows spinner when loading', () => {
      const { container } = render(<DataTable columns={defaultColumns} loading />);

      expect(container.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('does not show data when loading', () => {
      render(<DataTable columns={defaultColumns} data={defaultData} loading />);

      expect(screen.queryByText('John Doe')).not.toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows default empty message when no data', () => {
      render(<DataTable columns={defaultColumns} data={[]} />);

      expect(screen.getByText('No data available')).toBeInTheDocument();
    });

    it('shows custom empty state', () => {
      const emptyState = {
        title: 'No users found',
        description: 'Add your first user to get started',
      };

      render(<DataTable columns={defaultColumns} data={[]} emptyState={emptyState} />);

      expect(screen.getByText('No users found')).toBeInTheDocument();
      expect(screen.getByText('Add your first user to get started')).toBeInTheDocument();
    });

    it('shows empty state icon when provided', () => {
      const emptyState = {
        title: 'No files',
        description: 'Upload a file',
        icon: FileText,
      };

      const { container } = render(
        <DataTable columns={defaultColumns} data={[]} emptyState={emptyState} />
      );

      expect(container.querySelector('svg')).toBeInTheDocument();
    });

    it('shows action button in empty state', () => {
      const onAction = jest.fn();
      const emptyState = {
        title: 'No users',
        description: 'Add a user',
        action: {
          label: 'Add User',
          onClick: onAction,
        },
      };

      render(<DataTable columns={defaultColumns} data={[]} emptyState={emptyState} />);

      const button = screen.getByRole('button', { name: 'Add User' });
      expect(button).toBeInTheDocument();

      fireEvent.click(button);
      expect(onAction).toHaveBeenCalled();
    });
  });

  describe('row click', () => {
    it('calls onRowClick when row is clicked', () => {
      const onRowClick = jest.fn();
      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          onRowClick={onRowClick}
        />
      );

      const row = screen.getByText('John Doe').closest('tr');
      fireEvent.click(row!);

      expect(onRowClick).toHaveBeenCalledWith(defaultData[0]);
    });

    it('shows cursor pointer when onRowClick provided', () => {
      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          onRowClick={jest.fn()}
        />
      );

      const row = screen.getByText('John Doe').closest('tr');
      expect(row).toHaveClass('cursor-pointer');
    });

    it('does not show cursor pointer without onRowClick', () => {
      render(<DataTable columns={defaultColumns} data={defaultData} />);

      const row = screen.getByText('John Doe').closest('tr');
      expect(row).not.toHaveClass('cursor-pointer');
    });
  });

  describe('pagination', () => {
    const pagination: DataTablePagination = {
      current_page: 1,
      total_pages: 5,
      total_count: 50,
      per_page: 10,
    };

    it('renders pagination when provided', () => {
      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          pagination={pagination}
          onPageChange={jest.fn()}
        />
      );

      expect(screen.getByText('Page 1 of 5')).toBeInTheDocument();
    });

    it('shows result count', () => {
      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          pagination={pagination}
          onPageChange={jest.fn()}
        />
      );

      expect(screen.getByText(/Showing 1 to 10 of 50 results/)).toBeInTheDocument();
    });

    it('calls onPageChange for next page', () => {
      const onPageChange = jest.fn();
      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          pagination={pagination}
          onPageChange={onPageChange}
        />
      );

      fireEvent.click(screen.getByText('Next'));

      expect(onPageChange).toHaveBeenCalledWith(2);
    });

    it('calls onPageChange for previous page', () => {
      const onPageChange = jest.fn();
      const paginationPage2 = { ...pagination, current_page: 2 };

      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          pagination={paginationPage2}
          onPageChange={onPageChange}
        />
      );

      fireEvent.click(screen.getByText('Previous'));

      expect(onPageChange).toHaveBeenCalledWith(1);
    });

    it('disables previous button on first page', () => {
      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          pagination={pagination}
          onPageChange={jest.fn()}
        />
      );

      const prevButton = screen.getByText('Previous').closest('button');
      expect(prevButton).toBeDisabled();
    });

    it('disables next button on last page', () => {
      const lastPagePagination = { ...pagination, current_page: 5 };

      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          pagination={lastPagePagination}
          onPageChange={jest.fn()}
        />
      );

      const nextButton = screen.getByText('Next').closest('button');
      expect(nextButton).toBeDisabled();
    });

    it('does not render pagination without onPageChange', () => {
      render(
        <DataTable
          columns={defaultColumns}
          data={defaultData}
          pagination={pagination}
        />
      );

      expect(screen.queryByText('Page 1 of 5')).not.toBeInTheDocument();
    });

    it('does not render pagination when total count is 0', () => {
      const emptyPagination = { ...pagination, total_count: 0 };

      render(
        <DataTable
          columns={defaultColumns}
          data={[]}
          pagination={emptyPagination}
          onPageChange={jest.fn()}
        />
      );

      expect(screen.queryByText('Page 1 of 5')).not.toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('has table styling', () => {
      const { container } = render(
        <DataTable columns={defaultColumns} data={defaultData} />
      );

      expect(container.firstChild).toHaveClass(
        'bg-theme-surface',
        'border',
        'border-theme',
        'rounded-lg'
      );
    });

    it('headers have proper styling', () => {
      render(<DataTable columns={defaultColumns} data={defaultData} />);

      const header = screen.getByText('Name').closest('th');
      expect(header).toHaveClass('text-xs', 'font-semibold', 'uppercase');
    });

    it('rows have hover effect', () => {
      render(<DataTable columns={defaultColumns} data={defaultData} />);

      const row = screen.getByText('John Doe').closest('tr');
      expect(row).toHaveClass('hover:bg-theme-surface-hover');
    });
  });
});
