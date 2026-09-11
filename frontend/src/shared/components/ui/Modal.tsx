import React, { createContext, useContext, useEffect, useRef, useId } from 'react';
import { createPortal } from 'react-dom';

// ── NESTED-DIALOG STATE (C3 review F5-F7, C14 review C14-1/C14-2) ──────────
//
// A page can mount more than one Modal at once (a ConfirmationModal nested
// inside a drawer, say). Three things must be tracked module-wide, across ALL
// instances, rather than per-instance:
//
//  1. Which instance is TOPMOST, so only it answers Escape (F6: without this,
//     one Escape keypress closed both the confirmation and the drawer behind
//     it — both attach the same document-level keydown listener).
//  2. A REFCOUNT of open modals, so body scroll only unlocks at zero (F7:
//     without this, cancelling the inner dialog unset `overflow` while the
//     outer dialog was still open, and the page behind it scrolled again).
//
// (F5 — the duplicate `id="modal-title"` breaking `aria-labelledby` for the
// inner dialog — is per-instance and fixed below with `useId()`, no shared
// state needed.)
//
// C14-1: "topmost" cannot be "last pushed". React runs a CHILD's effects
// before its PARENT's, so an outer Modal and an inner Modal that mount in the
// SAME commit (e.g. a form Modal whose ConfirmationModal is already open on
// mount, from restored state) push the inner one first — making the OUTER
// read as "last pushed" and wrongly topmost. Ordering by NESTING DEPTH fixes
// this regardless of effect order: each Modal reads its depth from
// `ModalDepthContext` and provides `depth + 1` to its own children, so a
// truly nested Modal is always deeper than its parent no matter which one's
// effect ran first. Depth ties (siblings, not nested in each other) still
// break by push order, preserving the existing sibling semantics.
const ModalDepthContext = createContext(0);

interface OpenModalEntry {
  instanceId: string;
  depth: number;
}

let openModalStack: OpenModalEntry[] = [];
let scrollLockCount = 0;

function pushOpenModal(instanceId: string, depth: number) {
  openModalStack = [...openModalStack, { instanceId, depth }];
  scrollLockCount += 1;
  if (scrollLockCount === 1) {
    document.body.style.overflow = 'hidden';
  }
}

function popOpenModal(instanceId: string) {
  const before = openModalStack.length;
  openModalStack = openModalStack.filter((e) => e.instanceId !== instanceId);
  // C14-3: an unbalanced pop (an instance popping that was never pushed —
  // the exact shape of the C14-2 mutant) must not be silently absorbed by a
  // clamp. Only decrement for an entry that was actually removed; the
  // Modal.test.tsx "does not release the scroll lock" pair (C14-2) is the
  // guard against a regression here, not a console call (pattern-validation
  // fails on any console.* call, dev-only or not — the tests carry this now).
  if (openModalStack.length === before) {
    return;
  }
  scrollLockCount -= 1;
  if (scrollLockCount <= 0) {
    scrollLockCount = 0;
    document.body.style.overflow = 'unset';
  }
}

function isTopmostModal(instanceId: string): boolean {
  if (openModalStack.length === 0) return false;
  const maxDepth = Math.max(...openModalStack.map((e) => e.depth));
  const deepest = openModalStack.filter((e) => e.depth === maxDepth);
  // Tie-break: last pushed among the deepest wins (matches the pre-existing
  // sibling behaviour — two modals at the same depth, opened in turn).
  return deepest[deepest.length - 1]?.instanceId === instanceId;
}

// Test-only reset seam (C14-4). Module-wide state cannot leak between RTL
// tests through normal unmount/cleanup (push and pop are balanced by React's
// own effect cleanup), but a raw root that skips RTL's cleanup — or a test
// that crashes mid-render — could leave it dirty for the next test file in
// the same worker. Never called from application code.
export function __resetModalStackForTests(): void {
  openModalStack = [];
  scrollLockCount = 0;
  document.body.style.overflow = 'unset';
}

export interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title?: string | React.ReactNode;
  children: React.ReactNode;
  maxWidth?: 'sm' | 'md' | 'lg' | 'xl' | '2xl' | '3xl' | '4xl' | '5xl' | '6xl' | '7xl' | 'full';
  size?: 'sm' | 'md' | 'lg' | 'xl' | '2xl' | '3xl' | '4xl' | '5xl' | '6xl' | '7xl' | 'full'; // Alias for maxWidth
  className?: string;
  variant?: 'default' | 'centered' | 'fullscreen' | 'drawer';
  showCloseButton?: boolean;
  closeOnBackdrop?: boolean;
  closeOnEscape?: boolean;
  footer?: React.ReactNode;
  icon?: React.ReactNode;
  subtitle?: string | React.ReactNode;
  animate?: boolean;
  blur?: boolean;
  disableContentScroll?: boolean;
}

export const Modal: React.FC<ModalProps> = ({
  isOpen,
  onClose,
  title,
  children,
  maxWidth = 'lg',
  size, // Alias for maxWidth
  className = '',
  variant = 'default',
  showCloseButton = true,
  closeOnBackdrop = true,
  closeOnEscape = true,
  footer,
  icon,
  subtitle,
  animate = true,
  blur = true,
  disableContentScroll = false
}) => {
  const modalRef = useRef<HTMLDivElement>(null);
  // Unique per instance so nested Modals never share an id (F5): each dialog's
  // `aria-labelledby` resolves to its OWN title, not whichever Modal rendered
  // `id="modal-title"` first.
  const instanceId = useId();
  const titleId = `modal-title-${instanceId}`;
  // C14-1: this instance's own nesting depth, read from whichever Modal (if
  // any) rendered it inside `{children}`. Its own children — anything this
  // Modal renders — are one level deeper still (provided below).
  const depth = useContext(ModalDepthContext);

  // Use size if provided, otherwise use maxWidth
  const effectiveMaxWidth = size || maxWidth;

  const maxWidthClasses = {
    sm: 'max-w-sm',
    md: 'max-w-md',
    lg: 'max-w-lg',
    xl: 'max-w-xl',
    '2xl': 'max-w-2xl',
    '3xl': 'max-w-3xl',
    '4xl': 'max-w-4xl',
    '5xl': 'max-w-5xl',
    '6xl': 'max-w-6xl',
    '7xl': 'max-w-7xl',
    full: 'max-w-full mx-4'
  };

  // Join the shared open-modal stack while open — refcounts the body scroll
  // lock (F7) and tracks which instance is topmost (F6). Runs before the
  // Escape-handling effect below on both mount and unmount ordering, so the
  // stack is always current by the time a real (async) keydown can fire.
  useEffect(() => {
    if (!isOpen) return;
    pushOpenModal(instanceId, depth);
    return () => {
      popOpenModal(instanceId);
    };
  }, [isOpen, instanceId, depth]);

  // Handle escape key — only the TOPMOST open Modal answers it (F6), so
  // cancelling a nested confirmation never also closes the dialog behind it.
  useEffect(() => {
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && closeOnEscape && isTopmostModal(instanceId)) {
        onClose();
      }
    };

    if (isOpen) {
      document.addEventListener('keydown', handleEscape);
    }

    return () => {
      document.removeEventListener('keydown', handleEscape);
    };
  }, [isOpen, onClose, closeOnEscape, instanceId]);

  // Click outside to close
  const handleBackdropClick = (event: React.MouseEvent) => {
    if (event.target === event.currentTarget && closeOnBackdrop) {
      onClose();
    }
  };

  // Focus management
  useEffect(() => {
    if (isOpen && modalRef.current) {
      const focusableElements = modalRef.current.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      const firstElement = focusableElements[0] as HTMLElement;
      if (firstElement) {
        firstElement.focus();
      }
    }
  }, [isOpen]);

  if (!isOpen) return null;

  // Variant-specific styles
  const variantClasses = {
    default: disableContentScroll ? 'sm:my-4' : 'sm:my-8',
    centered: 'my-auto',
    fullscreen: 'h-full m-0',
    drawer: 'ml-auto h-full m-0'
  };

  const modalPositioning = {
    default: disableContentScroll
      ? 'flex items-start justify-center min-h-screen pt-4 px-4 pb-4 text-center sm:block sm:p-0'
      : 'flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0',
    centered: 'flex items-center justify-center min-h-screen p-4',
    fullscreen: 'flex items-center justify-center h-screen',
    drawer: 'flex justify-end h-screen'
  };

  const modalStyles = {
    default: `
      inline-block align-bottom bg-theme-surface 
      rounded-2xl text-left overflow-hidden 
      shadow-2xl transform transition-all sm:align-middle
      ${animate ? 'animate-modal-slide-up' : ''}
    `,
    centered: `
      bg-theme-surface rounded-2xl text-left overflow-hidden 
      shadow-2xl transform transition-all
      ${animate ? 'animate-modal-zoom-in' : ''}
    `,
    fullscreen: `
      bg-theme-surface h-full w-full text-left overflow-hidden flex flex-col
      ${animate ? 'animate-modal-fade-in' : ''}
    `,
    drawer: `
      bg-theme-surface h-full text-left overflow-hidden shadow-2xl flex flex-col
      ${animate ? 'animate-modal-slide-left' : ''}
    `
  };

   
  const selectedVariantClasses = variantClasses[variant] || variantClasses.default;
   
  const selectedModalPositioning = modalPositioning[variant] || modalPositioning.default;
   
  const selectedModalStyles = modalStyles[variant] || modalStyles.default;

  return createPortal(
    <div
      className={`fixed inset-0 z-[70] overflow-x-hidden ${disableContentScroll ? 'overflow-y-auto' : 'overflow-y-auto'}`}
      aria-labelledby={titleId}
      role="dialog"
      aria-modal="true"
    >
      <div
        className={selectedModalPositioning}
        onClick={handleBackdropClick}
      >
        {/* Enhanced background overlay with blur */}
        <div
          className={`
            fixed inset-0 transition-all duration-300 z-0
            ${blur ? 'backdrop-blur-sm' : ''}
            ${animate ? 'animate-fade-in' : ''}
            bg-black/60 dark:bg-black/80
          `}
          aria-hidden="true"
        />

        {/* Center modal helper for default variant */}
        {variant === 'default' && (
          <span className="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">
            &#8203;
          </span>
        )}

        <div
          ref={modalRef}
          className={`
            relative z-10
            ${selectedModalStyles}
            ${selectedVariantClasses}
            ${variant !== 'fullscreen' && variant !== 'drawer' ? 'w-full' : ''}
            ${variant === 'drawer' ? 'w-full max-w-md' : ''}
            ${
               
              variant !== 'fullscreen' && variant !== 'drawer' ? (maxWidthClasses[effectiveMaxWidth] || maxWidthClasses.lg) : ''
            }
            ${className}
          `.replace(/\s+/g, ' ').trim()}
        >
          {/* Enhanced Header */}
          <div className="relative bg-gradient-to-b from-theme-surface to-theme-background px-5 pt-4 pb-3">
            {/* Decorative top border */}
            <div className="absolute top-0 left-0 right-0 h-0.5 bg-gradient-to-r from-theme-interactive-primary via-theme-interactive-secondary to-theme-interactive-primary" />

            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2.5 min-w-0">
                {icon && (
                  <div className="flex-shrink-0 w-9 h-9 bg-theme-interactive-primary/10 rounded-lg flex items-center justify-center text-theme-interactive-primary text-base">
                    {icon}
                  </div>
                )}
                <div className="min-w-0">
                  <h3 className="text-lg font-semibold text-theme-primary break-words" id={titleId}>
                    {title}
                  </h3>
                  {subtitle && (
                    <div className="text-xs text-theme-secondary mt-0.5 break-words">
                      {subtitle}
                    </div>
                  )}
                </div>
              </div>
              {showCloseButton && (
                <button
                  onClick={onClose}
                  className="
                    -mt-1 -mr-1 p-2 rounded-lg
                    text-theme-secondary hover:text-theme-primary 
                    hover:bg-theme-surface-hover
                    focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary 
                    transition-all duration-200
                    group
                  "
                  aria-label="Close modal"
                >
                  <svg 
                    className="h-5 w-5 transform group-hover:rotate-90 transition-transform duration-300" 
                    fill="none" 
                    stroke="currentColor" 
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                </button>
              )}
            </div>
          </div>

          {/* Enhanced Content with conditional scroll */}
          <div className={`
            text-theme-secondary
            ${variant === 'fullscreen' || variant === 'drawer' ? 'flex-1 min-h-0 px-6 py-4 overflow-y-auto custom-scrollbar' :
              disableContentScroll ? 'px-6 py-4' : 'px-6 py-4 max-h-[60vh] overflow-y-auto custom-scrollbar'}
          `}>
            {/* C14-1: anything rendered here — including a nested Modal, no
                matter how many plain components sit between it and this one
                — is one nesting level deeper than THIS Modal. */}
            <ModalDepthContext.Provider value={depth + 1}>
              {children}
            </ModalDepthContext.Provider>
          </div>

          {/* Enhanced Footer */}
          {footer && (
            <div className="
              px-6 py-4 
              bg-gradient-to-t from-theme-surface to-theme-background
              border-t border-theme
              flex items-center justify-end gap-3
            ">
              {footer}
            </div>
          )}
        </div>
      </div>
    </div>,
    document.body,
  );
};

export default Modal;