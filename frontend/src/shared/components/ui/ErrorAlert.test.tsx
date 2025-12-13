import React from 'react';
import { screen, fireEvent } from '@testing-library/react';
import ErrorAlert from './ErrorAlert';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';

describe('ErrorAlert', () => {
  it('renders error message correctly', () => {
    renderWithProviders(<ErrorAlert message="Test error message" />, {
      preloadedState: mockAuthenticatedState
    });
    
    expect(screen.getByText('Test error message')).toBeInTheDocument();
  });

  it('displays error icon', () => {
    renderWithProviders(<ErrorAlert message="Error with icon" />);
    
    // Check for AlertTriangle icon (svg element)
    const icon = document.querySelector('svg');
    expect(icon).toBeInTheDocument();
    expect(icon).toHaveClass('text-theme-error');
  });

  it('applies correct error styling', () => {
    renderWithProviders(<ErrorAlert message="Styled error" />);
    
    const container = screen.getByText('Styled error').closest('.bg-theme-error');
    expect(container).toHaveClass('bg-theme-error', 'bg-opacity-10', 'border-theme-error');
  });

  it('shows close button when onClose is provided', () => {
    const mockOnClose = jest.fn();
    renderWithProviders(<ErrorAlert message="Closable error" onClose={mockOnClose} />);
    
    const closeButton = screen.getByRole('button');
    expect(closeButton).toBeInTheDocument();
  });

  it('hides close button when onClose is not provided', () => {
    renderWithProviders(<ErrorAlert message="Non-closable error" />);
    
    const closeButton = screen.queryByRole('button');
    expect(closeButton).not.toBeInTheDocument();
  });

  it('calls onClose when close button is clicked', () => {
    const mockOnClose = jest.fn();
    renderWithProviders(<ErrorAlert message="Test error" onClose={mockOnClose} />);
    
    const closeButton = screen.getByRole('button');
    fireEvent.click(closeButton);
    
    expect(mockOnClose).toHaveBeenCalledTimes(1);
  });

  it('handles long error messages appropriately', () => {
    const longMessage = 'This is a very long error message that should be displayed properly without breaking the layout or causing any issues with the error alert component styling and responsiveness.';
    
    renderWithProviders(<ErrorAlert message={longMessage} />);
    
    expect(screen.getByText(longMessage)).toBeInTheDocument();
  });

  it('handles empty error messages', () => {
    renderWithProviders(<ErrorAlert message="" />);
    
    // For empty message, just ensure component doesn't crash
    expect(document.querySelector('.bg-theme-error')).toBeInTheDocument();
  });

  it('handles special characters in error messages', () => {
    const specialMessage = 'Error: <script>alert("xss")</script> & "quotes" and symbols!@#$%';
    
    renderWithProviders(<ErrorAlert message={specialMessage} />);
    
    expect(screen.getByText(specialMessage)).toBeInTheDocument();
  });

  it('maintains proper structure with icon, message, and close button', () => {
    const mockOnClose = jest.fn();
    renderWithProviders(<ErrorAlert message="Structured error" onClose={mockOnClose} />);
    
    // Check overall structure
    const flexContainer = document.querySelector('.flex.items-start.gap-3');
    expect(flexContainer).toHaveClass('flex', 'items-start', 'gap-3');
    
    // Check icon is present
    const icon = document.querySelector('svg');
    expect(icon).toBeInTheDocument();
    
    // Check message is present
    expect(screen.getByText('Structured error')).toBeInTheDocument();
    
    // Check close button is present
    const closeButton = screen.getByRole('button');
    expect(closeButton).toBeInTheDocument();
  });

  it('has accessible close button with proper hover states', () => {
    const mockOnClose = jest.fn();
    renderWithProviders(<ErrorAlert message="Accessible error" onClose={mockOnClose} />, {
      preloadedState: mockAuthenticatedState
    });
    
    const closeButton = screen.getByRole('button');
    expect(closeButton).toHaveClass(
      'text-theme-error',
      'hover:text-theme-error-hover',
      'transition-colors'
    );
  });

  it('uses proper text sizing and colors', () => {
    renderWithProviders(<ErrorAlert message="Styled text" />);
    
    const message = screen.getByText('Styled text');
    expect(message).toHaveClass('text-sm', 'text-theme-error');
  });

  it('icon is properly sized and positioned', () => {
    renderWithProviders(<ErrorAlert message="Icon test" />);
    
    const icon = document.querySelector('svg');
    expect(icon).toHaveClass('w-5', 'h-5', 'text-theme-error', 'flex-shrink-0', 'mt-0.5');
  });

  it('close button icon is properly sized', () => {
    const mockOnClose = jest.fn();
    renderWithProviders(<ErrorAlert message="Close icon test" onClose={mockOnClose} />);
    
    const closeButton = screen.getByRole('button');
    const closeIcon = closeButton.querySelector('svg');
    expect(closeIcon).toHaveClass('w-4', 'h-4');
  });

  it('handles multiple rapid close clicks', () => {
    const mockOnClose = jest.fn();
    renderWithProviders(<ErrorAlert message="Rapid clicks" onClose={mockOnClose} />);
    
    const closeButton = screen.getByRole('button');
    
    // Click multiple times rapidly
    fireEvent.click(closeButton);
    fireEvent.click(closeButton);
    fireEvent.click(closeButton);
    
    expect(mockOnClose).toHaveBeenCalledTimes(3);
  });

  it('maintains focus accessibility for close button', () => {
    const mockOnClose = jest.fn();
    renderWithProviders(<ErrorAlert message="Focus test" onClose={mockOnClose} />);
    
    const closeButton = screen.getByRole('button');
    closeButton.focus();
    
    expect(document.activeElement).toBe(closeButton);
    
    // Should be triggerable via keyboard
    fireEvent.keyDown(closeButton, { key: 'Enter' });
    fireEvent.keyUp(closeButton, { key: 'Enter' });
  });

  it('renders correctly without crashing on edge cases', () => {
    // Test with undefined onClose (should be handled gracefully)
    expect(() => {
      renderWithProviders(<ErrorAlert message="Edge case test" onClose={undefined} />);
    }).not.toThrow();
    
    // Should not show close button when onClose is undefined
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  it('maintains responsive layout on different screen sizes', () => {
    renderWithProviders(<ErrorAlert message="Responsive test" onClose={jest.fn()} />);
    
    const flexContainer = document.querySelector('.flex.items-start.gap-3');
    
    // Check flexbox layout classes for responsiveness
    expect(flexContainer).toHaveClass('flex', 'items-start');
    
    // Check for proper gap spacing
    expect(flexContainer).toHaveClass('gap-3');
  });

  describe('Integration scenarios', () => {
    it('works with React.StrictMode', () => {
      renderWithProviders(
        <React.StrictMode>
          <ErrorAlert message="StrictMode test" onClose={jest.fn()} />
        </React.StrictMode>,
        { preloadedState: mockAuthenticatedState }
      );
      
      expect(screen.getByText('StrictMode test')).toBeInTheDocument();
    });

    it('handles re-renders with different messages', () => {
      const { rerender } = renderWithProviders(<ErrorAlert message="First message" />, {
        preloadedState: mockAuthenticatedState
      });
      expect(screen.getByText('First message')).toBeInTheDocument();
      
      rerender(<ErrorAlert message="Second message" />);
      expect(screen.getByText('Second message')).toBeInTheDocument();
      expect(screen.queryByText('First message')).not.toBeInTheDocument();
    });

    it('handles onClose function changes', () => {
      const firstOnClose = jest.fn();
      const { rerender } = renderWithProviders(<ErrorAlert message="Test" onClose={firstOnClose} />, {
        preloadedState: mockAuthenticatedState
      });
      
      const secondOnClose = jest.fn();
      rerender(<ErrorAlert message="Test" onClose={secondOnClose} />);
      
      const closeButton = screen.getByRole('button');
      fireEvent.click(closeButton);
      
      expect(firstOnClose).not.toHaveBeenCalled();
      expect(secondOnClose).toHaveBeenCalledTimes(1);
    });
  });
});