import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { FileUpload } from '../components/FileUpload';
import { filesApi } from '../services/filesApi';

// Mock the files API
jest.mock('../services/filesApi');

// Mock global notifications - component uses showNotification
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
  }),
}));

const mockFilesApi = jest.mocked(filesApi);

describe('FileUpload Integration Tests', () => {
  const mockOnUploadComplete = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('File Upload Flow', () => {
    it('completes full upload workflow successfully', async () => {
      const user = userEvent.setup();

      mockFilesApi.uploadFile.mockResolvedValue({
        id: 'test-file-id',
        filename: 'test-document.pdf',
        file_size: 1024000,
        content_type: 'application/pdf',
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private',
        storage_key: 'uploads/test-document.pdf',
        version: 1,
        processing_status: 'completed',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });

      render(
        <FileUpload
          onUploadComplete={mockOnUploadComplete}
          category="user_upload"
          visibility="private"
          multiple={false}
        />
      );

      // Create a test file
      const file = new File(['test content'], 'test-document.pdf', {
        type: 'application/pdf',
      });

      // Find file input by aria-label
      const input = screen.getByLabelText(/select file/i) as HTMLInputElement;
      await user.upload(input, file);

      // Wait for upload to complete
      await waitFor(() => {
        expect(mockFilesApi.uploadFile).toHaveBeenCalledWith(
          file,
          expect.objectContaining({
            category: 'user_upload',
            visibility: 'private',
          })
        );
      });

      // Verify upload completion callback was called
      await waitFor(() => {
        expect(mockOnUploadComplete).toHaveBeenCalledWith(
          expect.objectContaining({
            id: 'test-file-id',
            filename: 'test-document.pdf',
          })
        );
      });

      // Verify success state - component shows uploaded file with success icon
      await waitFor(() => {
        expect(screen.getByText('test-document.pdf')).toBeInTheDocument();
      });
    });

    it('handles upload errors gracefully', async () => {
      const user = userEvent.setup();
      const errorMessage = 'File size exceeds quota limit';

      mockFilesApi.uploadFile.mockRejectedValue(new Error(errorMessage));

      render(
        <FileUpload
          onUploadComplete={mockOnUploadComplete}
          maxSizeMB={100}
        />
      );

      const file = new File(['test content'], 'test.txt', { type: 'text/plain' });
      const input = screen.getByLabelText(/select file/i) as HTMLInputElement;

      await user.upload(input, file);

      await waitFor(() => {
        expect(screen.getByText(new RegExp(errorMessage, 'i'))).toBeInTheDocument();
      });

      expect(mockOnUploadComplete).not.toHaveBeenCalled();
    });

    it('validates file size before upload', async () => {
      const user = userEvent.setup();

      render(
        <FileUpload
          onUploadComplete={mockOnUploadComplete}
          maxSizeMB={1}
        />
      );

      // Create a file larger than max size (1MB)
      const largeContent = 'a'.repeat(2 * 1024 * 1024); // 2MB
      const file = new File([largeContent], 'large-file.txt', { type: 'text/plain' });

      const input = screen.getByLabelText(/select file/i) as HTMLInputElement;
      await user.upload(input, file);

      // Component shows validation error via notification (not inline)
      // The file should not be uploaded
      expect(mockFilesApi.uploadFile).not.toHaveBeenCalled();
      expect(mockOnUploadComplete).not.toHaveBeenCalled();
    });

    it('shows upload progress during file upload', async () => {
      const user = userEvent.setup();

      // Mock upload with progress
      mockFilesApi.uploadFile.mockImplementation(
        (file: File, options?: import('../services/filesApi').UploadOptions) => {
          // Simulate progress updates
          setTimeout(() => options?.onProgress?.({ loaded: 50000, total: 100000, percentage: 50 }), 50);
          return new Promise((resolve) => {
            setTimeout(() => {
              options?.onProgress?.({ loaded: 100000, total: 100000, percentage: 100 });
              resolve({
                id: 'test-id',
                filename: file.name,
                file_size: file.size,
                content_type: file.type,
                file_type: 'document',
                category: 'user_upload',
                visibility: 'private',
                storage_key: 'uploads/test.txt',
                version: 1,
                processing_status: 'completed',
                created_at: new Date().toISOString(),
                updated_at: new Date().toISOString(),
              });
            }, 100);
          });
        }
      );

      render(<FileUpload onUploadComplete={mockOnUploadComplete} />);

      const file = new File(['content'], 'test.txt', { type: 'text/plain' });
      const input = screen.getByLabelText(/select file/i) as HTMLInputElement;

      await user.upload(input, file);

      // Check for progress indicator - component shows progressbar role
      await waitFor(() => {
        const progressbar = screen.queryByRole('progressbar');
        const percentageText = screen.queryByText(/50%|100%/);
        expect(progressbar || percentageText).toBeTruthy();
      }, { timeout: 500 });
    });
  });

  describe('Multiple File Upload', () => {
    it('uploads multiple files', async () => {
      const user = userEvent.setup();

      mockFilesApi.uploadFile.mockImplementation((file) =>
        Promise.resolve({
          id: `file-${file.name}`,
          filename: file.name,
          file_size: file.size,
          content_type: file.type,
          file_type: 'document',
          category: 'user_upload',
          visibility: 'private',
          storage_key: `uploads/${file.name}`,
          version: 1,
          processing_status: 'completed',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
      );

      render(
        <FileUpload
          onUploadComplete={mockOnUploadComplete}
          multiple={true}
        />
      );

      const files = [
        new File(['content1'], 'file1.txt', { type: 'text/plain' }),
        new File(['content2'], 'file2.txt', { type: 'text/plain' }),
        new File(['content3'], 'file3.txt', { type: 'text/plain' }),
      ];

      // Multiple files requires multiple aria-label
      const input = screen.getByLabelText(/choose files/i) as HTMLInputElement;
      await user.upload(input, files);

      // Wait for uploads to complete - component processes files sequentially
      await waitFor(() => {
        expect(mockFilesApi.uploadFile).toHaveBeenCalledTimes(3);
      }, { timeout: 10000 });

      // Verify all files were uploaded (at least one callback)
      await waitFor(() => {
        expect(mockOnUploadComplete).toHaveBeenCalled();
      }, { timeout: 10000 });
    }, 15000);

  });

  describe('Drag and Drop Upload', () => {
    it('handles drag and drop file upload', async () => {
      mockFilesApi.uploadFile.mockResolvedValue({
        id: 'dropped-file',
        filename: 'dropped.txt',
        file_size: 100,
        content_type: 'text/plain',
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private',
        storage_key: 'uploads/dropped.txt',
        version: 1,
        processing_status: 'completed',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });

      render(<FileUpload onUploadComplete={mockOnUploadComplete} />);

      const dropZone = screen.getByText(/drag.*drop|drop.*here/i).closest('div');
      expect(dropZone).toBeInTheDocument();

      const file = new File(['dropped content'], 'dropped.txt', { type: 'text/plain' });

      // Simulate drag and drop
      fireEvent.dragEnter(dropZone!);
      fireEvent.dragOver(dropZone!);

      const dataTransfer = {
        files: [file],
        types: ['Files'],
      };

      fireEvent.drop(dropZone!, { dataTransfer });

      await waitFor(() => {
        expect(mockFilesApi.uploadFile).toHaveBeenCalledWith(
          file,
          expect.objectContaining({
            category: 'user_upload',
            visibility: 'private',
          })
        );
      });

      await waitFor(() => {
        expect(mockOnUploadComplete).toHaveBeenCalled();
      });
    });

    it('shows drag over state visual feedback', async () => {
      render(<FileUpload onUploadComplete={mockOnUploadComplete} />);

      // The drop zone is the div containing the drag/drop text
      const dropZone = screen.getByText(/drag.*drop|drop.*here/i).closest('div');
      expect(dropZone).toBeInTheDocument();

      // Simulate drag over (dragOver is what sets isDragging in the component)
      fireEvent.dragOver(dropZone!);

      // Wait for state update and check visual feedback
      await waitFor(() => {
        expect(dropZone).toHaveClass('border-theme-info');
      });

      fireEvent.dragLeave(dropZone!);

      // Visual feedback should be removed
      await waitFor(() => {
        expect(dropZone).not.toHaveClass('border-theme-info');
      });
    });
  });

  describe('File Type Validation', () => {
    it('accepts allowed file types', async () => {
      const user = userEvent.setup();

      mockFilesApi.uploadFile.mockResolvedValue({
        id: 'allowed-file',
        filename: 'document.pdf',
        file_size: 1000,
        content_type: 'application/pdf',
        file_type: 'document',
        category: 'user_upload',
        visibility: 'private',
        storage_key: 'uploads/document.pdf',
        version: 1,
        processing_status: 'completed',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });

      render(
        <FileUpload
          onUploadComplete={mockOnUploadComplete}
          accept="application/pdf,image/jpeg,image/png"
        />
      );

      const file = new File(['content'], 'document.pdf', { type: 'application/pdf' });
      const input = screen.getByLabelText(/select file/i) as HTMLInputElement;

      await user.upload(input, file);

      await waitFor(() => {
        expect(mockFilesApi.uploadFile).toHaveBeenCalled();
      });
    });

    it('rejects disallowed file types', async () => {
      const user = userEvent.setup();

      render(
        <FileUpload
          onUploadComplete={mockOnUploadComplete}
          accept="application/pdf"
        />
      );

      const file = new File(['content'], 'document.txt', { type: 'text/plain' });
      const input = screen.getByLabelText(/select file/i) as HTMLInputElement;

      await user.upload(input, file);

      // File type validation happens client-side via validateFile
      // The notification is shown, file is not uploaded
      expect(mockFilesApi.uploadFile).not.toHaveBeenCalled();
    });
  });

  describe('Upload Cancellation', () => {
    it('allows cancelling ongoing upload', async () => {
      const user = userEvent.setup();

      mockFilesApi.uploadFile.mockImplementation((_file, options) => {
        // Simulate slow upload
        return new Promise((resolve) => {
          setTimeout(() => {
            options?.onProgress?.({ loaded: 25000, total: 100000, percentage: 25 });
          }, 50);
          setTimeout(() => {
            resolve({
              id: 'test-id',
              filename: 'test.txt',
              file_size: 100,
              content_type: 'text/plain',
              file_type: 'document',
              category: 'user_upload',
              visibility: 'private',
              storage_key: 'uploads/test.txt',
              version: 1,
              processing_status: 'completed',
              created_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            });
          }, 2000); // Long delay to allow cancel
        });
      });

      render(<FileUpload onUploadComplete={mockOnUploadComplete} />);

      const file = new File(['content'], 'test.txt', { type: 'text/plain' });
      const input = screen.getByLabelText(/select file/i) as HTMLInputElement;

      await user.upload(input, file);

      // Wait for upload to start and cancel button to appear
      await waitFor(() => {
        expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
      });

      // Click cancel button
      const cancelButton = screen.getByRole('button', { name: /cancel/i });
      await user.click(cancelButton);

      // Should show cancelled state
      await waitFor(() => {
        expect(screen.getByText(/upload cancelled/i)).toBeInTheDocument();
      });
    });
  });
});
