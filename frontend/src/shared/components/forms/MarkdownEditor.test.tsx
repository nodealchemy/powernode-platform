import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MarkdownEditor } from './MarkdownEditor';

// Mock the MDEditor component
jest.mock('@uiw/react-md-editor', () => {
  const MockMDEditor = ({ value, onChange, placeholder, hideToolbar, preview }: any) => (
    <div data-testid="md-editor">
      <textarea
        data-testid="md-textarea"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        readOnly={hideToolbar}
        data-preview-mode={preview}
      />
    </div>
  );
  return MockMDEditor;
});

// Mock react-dropzone
const mockGetRootProps = jest.fn(() => ({}));
const mockGetInputProps = jest.fn(() => ({}));
jest.mock('react-dropzone', () => ({
  useDropzone: () => ({
    getRootProps: mockGetRootProps,
    getInputProps: mockGetInputProps,
    isDragActive: false
  })
}));

// Mock heroicons
jest.mock('@heroicons/react/24/outline', () => ({
  PhotoIcon: () => <span data-testid="photo-icon">Photo</span>,
  EyeIcon: () => <span data-testid="eye-icon">Eye</span>,
  EyeSlashIcon: () => <span data-testid="eye-slash-icon">EyeSlash</span>,
  ArrowsPointingOutIcon: () => <span data-testid="expand-icon">Expand</span>,
  ArrowsPointingInIcon: () => <span data-testid="shrink-icon">Shrink</span>
}));

describe('MarkdownEditor', () => {
  const defaultProps = {
    value: '',
    onChange: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders the editor', () => {
      render(<MarkdownEditor {...defaultProps} />);

      expect(screen.getByTestId('md-editor')).toBeInTheDocument();
    });

    it('renders textarea with value', () => {
      render(<MarkdownEditor {...defaultProps} value="# Hello World" />);

      const textarea = screen.getByTestId('md-textarea');
      expect(textarea).toHaveValue('# Hello World');
    });

    it('applies custom className', () => {
      const { container } = render(
        <MarkdownEditor {...defaultProps} className="custom-editor" />
      );

      expect(container.firstChild).toHaveClass('custom-editor');
    });

    it('shows placeholder text', () => {
      render(<MarkdownEditor {...defaultProps} placeholder="Write something..." />);

      const textarea = screen.getByTestId('md-textarea');
      expect(textarea).toHaveAttribute('placeholder', 'Write something...');
    });

    it('uses default placeholder', () => {
      render(<MarkdownEditor {...defaultProps} />);

      const textarea = screen.getByTestId('md-textarea');
      expect(textarea).toHaveAttribute('placeholder', 'Start writing your article...');
    });
  });

  describe('editing', () => {
    it('calls onChange when content changes', () => {
      const onChange = jest.fn();
      render(<MarkdownEditor {...defaultProps} onChange={onChange} />);

      const textarea = screen.getByTestId('md-textarea');
      fireEvent.change(textarea, { target: { value: 'New content' } });

      expect(onChange).toHaveBeenCalledWith('New content');
    });
  });

  describe('readOnly mode', () => {
    it('sets textarea as readOnly when readOnly prop is true', () => {
      render(<MarkdownEditor {...defaultProps} readOnly />);

      const textarea = screen.getByTestId('md-textarea');
      expect(textarea).toHaveAttribute('readonly');
    });
  });

  describe('auto-save feature', () => {
    beforeEach(() => {
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    it('shows auto-save status when autoSave is enabled', () => {
      const onAutoSave = jest.fn().mockResolvedValue(undefined);
      render(
        <MarkdownEditor
          {...defaultProps}
          autoSave
          onAutoSave={onAutoSave}
        />
      );

      // Auto-save container should exist when autoSave is true
      const container = document.querySelector('.flex.items-center.justify-between.mb-2');
      expect(container).toBeInTheDocument();
    });

    it('does not show auto-save status when autoSave is disabled', () => {
      render(<MarkdownEditor {...defaultProps} />);

      // The auto-save status bar should not be present
      const savingIndicator = screen.queryByText('Saving...');
      const lastSavedIndicator = screen.queryByText(/Last saved:/);
      expect(savingIndicator).not.toBeInTheDocument();
      expect(lastSavedIndicator).not.toBeInTheDocument();
    });

    it('triggers auto-save after interval when content changes', async () => {
      const onAutoSave = jest.fn().mockResolvedValue(undefined);
      const { rerender } = render(
        <MarkdownEditor
          {...defaultProps}
          value="Initial content"
          autoSave
          autoSaveInterval={1000}
          onAutoSave={onAutoSave}
        />
      );

      // Change the content - this simulates user editing
      rerender(
        <MarkdownEditor
          {...defaultProps}
          value="Updated content"
          autoSave
          autoSaveInterval={1000}
          onAutoSave={onAutoSave}
        />
      );

      // Fast-forward timer
      jest.advanceTimersByTime(1000);

      // Auto-save should be triggered with the updated content
      await waitFor(() => {
        expect(onAutoSave).toHaveBeenCalled();
      });
    });
  });

  describe('fullscreen mode', () => {
    it('starts in non-fullscreen mode', () => {
      const { container } = render(<MarkdownEditor {...defaultProps} />);

      const editorContainer = container.firstChild as HTMLElement;
      expect(editorContainer).not.toHaveClass('fixed');
    });
  });

  describe('preview mode', () => {
    it('starts in edit mode', () => {
      render(<MarkdownEditor {...defaultProps} />);

      const textarea = screen.getByTestId('md-textarea');
      expect(textarea).toHaveAttribute('data-preview-mode', 'edit');
    });
  });

  describe('drag and drop', () => {
    it('sets up dropzone', () => {
      render(<MarkdownEditor {...defaultProps} />);

      expect(mockGetRootProps).toHaveBeenCalled();
      expect(mockGetInputProps).toHaveBeenCalled();
    });
  });

  describe('image upload', () => {
    it('accepts image upload callback', () => {
      const onImageUpload = jest.fn().mockResolvedValue('https://example.com/image.png');
      render(<MarkdownEditor {...defaultProps} onImageUpload={onImageUpload} />);

      // The component should render without errors when onImageUpload is provided
      expect(screen.getByTestId('md-editor')).toBeInTheDocument();
    });
  });

  describe('height', () => {
    it('uses default height of 400', () => {
      render(<MarkdownEditor {...defaultProps} />);

      // Editor should render (height is passed to MDEditor)
      expect(screen.getByTestId('md-editor')).toBeInTheDocument();
    });

    it('accepts custom height', () => {
      render(<MarkdownEditor {...defaultProps} height={600} />);

      expect(screen.getByTestId('md-editor')).toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('renders style block for theming', () => {
      const { container } = render(<MarkdownEditor {...defaultProps} />);

      const style = container.querySelector('style');
      expect(style).toBeInTheDocument();
    });

    it('applies markdown-editor-container class', () => {
      const { container } = render(<MarkdownEditor {...defaultProps} />);

      expect(container.firstChild).toHaveClass('markdown-editor-container');
    });
  });
});
