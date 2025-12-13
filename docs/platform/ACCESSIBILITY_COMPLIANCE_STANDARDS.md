# Accessibility Compliance Standards (WCAG AA)

## Overview

This document establishes mandatory accessibility standards for the Powernode platform, ensuring WCAG AA compliance across all frontend components and admin interfaces.

## Critical Accessibility Requirements

### 1. Color Contrast Standards (MANDATORY)

#### Contrast Ratio Requirements
- **Normal text**: Minimum 4.5:1 contrast ratio
- **Large text** (18pt+ or 14pt+ bold): Minimum 3:1 contrast ratio  
- **Interactive elements**: Minimum 3:1 contrast ratio for focus states
- **Graphical elements**: Minimum 3:1 contrast ratio for meaningful graphics

#### Theme-Aware Color Implementation
```tsx
// ✅ CORRECT: Theme-aware colors ensuring proper contrast
const ACCESSIBLE_THEME_CLASSES = {
  // High contrast text combinations
  primaryText: 'text-theme-primary',        // Ensures 4.5:1+ on theme-surface
  secondaryText: 'text-theme-secondary',    // Ensures 4.5:1+ on theme-surface
  
  // Form inputs with proper contrast
  inputBase: 'bg-theme-surface text-theme-primary',  // Meets contrast requirements
  inputFocus: 'focus:ring-2 focus:ring-theme-primary focus:border-theme-primary',
  
  // Error states with sufficient contrast
  errorText: 'text-theme-error',            // High contrast error text
  errorBackground: 'bg-theme-error-background', // Subtle error background
  
  // Warning states maintaining readability
  warningText: 'text-theme-warning-dark',   // Dark warning text for contrast
  warningBackground: 'bg-theme-warning-background',
  
  // Success states with proper visibility
  successText: 'text-theme-success-dark',   // Dark success text
  successBackground: 'bg-theme-success-background'
} as const;

// ❌ FORBIDDEN: Insufficient contrast combinations
const FORBIDDEN_COMBINATIONS = [
  'text-yellow-400 on bg-yellow-100',    // Poor contrast
  'text-gray-400 on bg-white',          // Below 4.5:1 ratio
  'text-blue-300 on bg-blue-100'        // Insufficient for body text
];
```

#### Form Input Contrast Standards
```tsx
// ✅ MANDATORY: Accessible form input pattern
const AccessibleInput: React.FC<InputProps> = ({ error, ...props }) => {
  return (
    <input
      className={cn(
        // Base contrast-compliant styling
        'w-full px-3 py-2 rounded-md border',
        'bg-theme-surface text-theme-primary',     // 4.5:1+ contrast
        'placeholder:text-theme-tertiary',         // Sufficient contrast for hints
        'border-theme focus:border-theme-primary', // Clear focus indication
        'focus:ring-2 focus:ring-theme-primary focus:ring-offset-0',
        
        // Error state with maintained contrast
        error && 'border-theme-error focus:border-theme-error focus:ring-theme-error',
        
        // Disabled state remains readable
        'disabled:opacity-50 disabled:bg-theme-background disabled:text-theme-secondary'
      )}
      {...props}
    />
  );
};
```

### 2. Focus Management (CRITICAL)

#### Visible Focus Indicators
```tsx
// ✅ MANDATORY: Visible focus states for all interactive elements
const focusStyles = {
  // Standard focus ring - 2px minimum
  standard: 'focus:ring-2 focus:ring-theme-primary focus:ring-offset-2 focus:outline-none',
  
  // High contrast focus for critical elements
  critical: 'focus:ring-2 focus:ring-theme-primary focus:ring-offset-2 focus:outline-none focus:bg-theme-primary/10',
  
  // Form element focus
  input: 'focus:ring-2 focus:ring-theme-primary focus:border-theme-primary focus:ring-offset-0',
  
  // Button focus states
  button: 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-theme-primary'
};

// ✅ CORRECT: Button with proper focus management
const AccessibleButton: React.FC<ButtonProps> = ({ children, ...props }) => {
  return (
    <button
      className={cn(
        'inline-flex items-center justify-center px-4 py-2 rounded-md',
        'bg-theme-primary text-white hover:bg-theme-primary-hover',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-theme-primary',
        'disabled:opacity-50 disabled:pointer-events-none'
      )}
      {...props}
    >
      {children}
    </button>
  );
};
```

#### Focus Trap Implementation
```tsx
// ✅ REQUIRED: Focus trap for modals and important UI sections
const FocusTrap: React.FC<{ children: React.ReactNode; active: boolean }> = ({ 
  children, 
  active 
}) => {
  const trapRef = useRef<HTMLDivElement>(null);
  
  useEffect(() => {
    if (!active) return;
    
    const trapFocus = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;
      
      const focusableElements = trapRef.current?.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      ) as NodeListOf<HTMLElement>;
      
      if (!focusableElements?.length) return;
      
      const firstElement = focusableElements[0];
      const lastElement = focusableElements[focusableElements.length - 1];
      
      if (e.shiftKey) {
        if (document.activeElement === firstElement) {
          e.preventDefault();
          lastElement.focus();
        }
      } else {
        if (document.activeElement === lastElement) {
          e.preventDefault();
          firstElement.focus();
        }
      }
    };
    
    document.addEventListener('keydown', trapFocus);
    return () => document.removeEventListener('keydown', trapFocus);
  }, [active]);
  
  return <div ref={trapRef}>{children}</div>;
};
```

### 3. Semantic HTML and ARIA (MANDATORY)

#### Proper Heading Hierarchy
```tsx
// ✅ CORRECT: Logical heading structure
const AccessiblePageStructure: React.FC = () => {
  return (
    <main>
      <h1 className="text-2xl font-bold text-theme-primary">Admin Settings</h1>
      
      <section aria-labelledby="rate-limiting-title">
        <h2 id="rate-limiting-title" className="text-xl font-semibold text-theme-primary">
          Rate Limiting Configuration
        </h2>
        
        <div role="group" aria-labelledby="emergency-controls-title">
          <h3 id="emergency-controls-title" className="text-lg font-medium text-theme-warning">
            Emergency Controls
          </h3>
          {/* Emergency controls content */}
        </div>
        
        <div role="group" aria-labelledby="recent-violations-title">
          <h3 id="recent-violations-title" className="text-lg font-medium text-theme-error">
            Recent Violations
          </h3>
          {/* Violations content */}
        </div>
      </section>
    </main>
  );
};
```

#### Form Labels and Associations
```tsx
// ✅ MANDATORY: Proper form labeling
const AccessibleForm: React.FC = () => {
  return (
    <form>
      <div className="space-y-4">
        <div>
          <label 
            htmlFor="disable-duration" 
            className="block text-sm font-medium text-theme-primary mb-1"
          >
            Disable Duration (minutes)
            <span className="text-theme-error ml-1" aria-label="required">*</span>
          </label>
          <input
            id="disable-duration"
            type="number"
            min="1"
            max="480"
            required
            aria-describedby="disable-help"
            className="w-20 px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary"
          />
          <p id="disable-help" className="mt-1 text-sm text-theme-secondary">
            Temporarily disable rate limiting for maintenance (1-480 minutes)
          </p>
        </div>
        
        <fieldset className="border border-theme rounded-lg p-4">
          <legend className="px-2 text-sm font-medium text-theme-primary">
            Rate Limit Categories
          </legend>
          {/* Fieldset content */}
        </fieldset>
      </div>
    </form>
  );
};
```

#### ARIA Labels and Descriptions
```tsx
// ✅ CORRECT: Comprehensive ARIA implementation
const AccessibleComponents: React.FC = () => {
  return (
    <div>
      {/* Status announcements for screen readers */}
      <div 
        role="status" 
        aria-live="polite" 
        aria-atomic="true"
        className="sr-only"
      >
        {statusMessage && `Status: ${statusMessage}`}
      </div>
      
      {/* Interactive elements with proper ARIA */}
      <button
        onClick={handleEmergencyDisable}
        aria-describedby="emergency-warning"
        aria-pressed={isDisabled}
      >
        <Ban className="w-4 h-4 mr-2" aria-hidden="true" />
        {isDisabled ? 'Re-enable' : 'Disable'} Rate Limiting
      </button>
      
      <p id="emergency-warning" className="text-sm text-theme-warning">
        This will temporarily disable all rate limiting protections
      </p>
      
      {/* Data tables with proper structure */}
      <table 
        className="w-full" 
        role="table"
        aria-labelledby="violations-title"
      >
        <caption id="violations-title" className="text-lg font-medium mb-4">
          Recent Rate Limiting Violations
        </caption>
        <thead>
          <tr>
            <th scope="col" className="text-left px-4 py-2">Endpoint</th>
            <th scope="col" className="text-left px-4 py-2">Identifier</th>
            <th scope="col" className="text-left px-4 py-2">Count/Limit</th>
            <th scope="col" className="text-left px-4 py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {violations.map((violation) => (
            <tr key={violation.id}>
              <td className="px-4 py-2">{violation.endpoint}</td>
              <td className="px-4 py-2">{violation.identifier}</td>
              <td className="px-4 py-2">{violation.count}/{violation.limit}</td>
              <td className="px-4 py-2">
                <button
                  onClick={() => clearLimits(violation.identifier)}
                  aria-label={`Clear rate limits for ${violation.identifier}`}
                >
                  <Trash2 className="w-4 h-4" aria-hidden="true" />
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
```

### 4. Keyboard Navigation (MANDATORY)

#### Tab Order and Navigation
```tsx
// ✅ CORRECT: Logical tab order implementation
const KeyboardNavigableInterface: React.FC = () => {
  const handleKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    // Escape key handling
    if (e.key === 'Escape' && onClose) {
      onClose();
    }
    
    // Arrow key navigation for custom components
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      focusNextItem();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      focusPreviousItem();
    }
  };
  
  return (
    <div onKeyDown={handleKeyDown}>
      {/* Proper tab sequence */}
      <button tabIndex={1}>Primary Action</button>
      <input tabIndex={2} placeholder="Enter value" />
      <select tabIndex={3}>
        <option>Option 1</option>
        <option>Option 2</option>
      </select>
      <button tabIndex={4}>Secondary Action</button>
      
      {/* Skip to main content link */}
      <a 
        href="#main-content" 
        className="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 bg-theme-primary text-white px-4 py-2 rounded"
      >
        Skip to main content
      </a>
    </div>
  );
};
```

#### Custom Component Keyboard Support
```tsx
// ✅ REQUIRED: Custom dropdown with keyboard navigation
const AccessibleDropdown: React.FC<DropdownProps> = ({ options, onSelect }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);
  
  const handleKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    switch (e.key) {
      case 'Enter':
      case ' ':
        e.preventDefault();
        if (activeIndex >= 0) {
          onSelect(options[activeIndex]);
          setIsOpen(false);
        } else {
          setIsOpen(!isOpen);
        }
        break;
        
      case 'ArrowDown':
        e.preventDefault();
        setActiveIndex(prev => (prev + 1) % options.length);
        break;
        
      case 'ArrowUp':
        e.preventDefault();
        setActiveIndex(prev => prev <= 0 ? options.length - 1 : prev - 1);
        break;
        
      case 'Escape':
        setIsOpen(false);
        setActiveIndex(-1);
        break;
    }
  };
  
  return (
    <div 
      className="relative"
      onKeyDown={handleKeyDown}
      role="combobox"
      aria-expanded={isOpen}
      aria-haspopup="listbox"
    >
      {/* Implementation */}
    </div>
  );
};
```

### 5. Error Handling and Feedback (CRITICAL)

#### Accessible Error Messages
```tsx
// ✅ MANDATORY: Accessible error presentation
const AccessibleErrorHandling: React.FC = () => {
  const [errors, setErrors] = useState<string[]>([]);
  
  return (
    <div>
      {/* Error summary for screen readers */}
      {errors.length > 0 && (
        <div 
          role="alert"
          aria-live="assertive"
          className="mb-6 p-4 bg-theme-error-background border border-theme-error rounded-lg"
        >
          <h3 className="text-lg font-medium text-theme-error mb-2">
            Please correct the following errors:
          </h3>
          <ul className="list-disc list-inside space-y-1">
            {errors.map((error, index) => (
              <li key={index} className="text-theme-error-dark">
                {error}
              </li>
            ))}
          </ul>
        </div>
      )}
      
      {/* Form fields with inline error handling */}
      <div className="space-y-4">
        <div>
          <label htmlFor="email" className="block text-sm font-medium">
            Email Address
          </label>
          <input
            id="email"
            type="email"
            aria-invalid={errors.includes('email')}
            aria-describedby="email-error"
            className={cn(
              'w-full px-3 py-2 border rounded-md',
              errors.includes('email') 
                ? 'border-theme-error focus:ring-theme-error' 
                : 'border-theme focus:ring-theme-primary'
            )}
          />
          {errors.includes('email') && (
            <p id="email-error" role="alert" className="mt-1 text-sm text-theme-error">
              Please enter a valid email address
            </p>
          )}
        </div>
      </div>
    </div>
  );
};
```

## Accessibility Testing and Validation

### 1. Automated Testing Commands

#### Accessibility Audit Scripts
```bash
# Install accessibility testing dependencies
npm install --save-dev @axe-core/react jest-axe @testing-library/jest-dom

# Run accessibility tests
npm run test:a11y

# Generate accessibility report
npm run a11y:report

# Validate color contrast ratios
npm run contrast:check
```

#### Component Accessibility Tests
```typescript
// accessibility.test.tsx
import { render } from '@testing-library/react';
import { axe, toHaveNoViolations } from 'jest-axe';
import { RateLimitingSettings } from '../RateLimitingSettings';

expect.extend(toHaveNoViolations);

describe('RateLimitingSettings Accessibility', () => {
  test('should not have any accessibility violations', async () => {
    const { container } = render(<RateLimitingSettings />);
    const results = await axe(container);
    expect(results).toHaveNoViolations();
  });
  
  test('form inputs have proper labels', () => {
    const { getByLabelText } = render(<RateLimitingSettings />);
    expect(getByLabelText(/disable duration/i)).toBeInTheDocument();
  });
  
  test('error messages are announced to screen readers', () => {
    const { getByRole } = render(<RateLimitingSettings />);
    // Trigger error state
    const errorAlert = getByRole('alert');
    expect(errorAlert).toHaveAttribute('aria-live', 'assertive');
  });
});
```

### 2. Manual Testing Checklist

#### Keyboard Navigation Testing
- [ ] All interactive elements reachable via Tab key
- [ ] Logical tab order follows visual layout
- [ ] Escape key closes modals and dismisses overlays
- [ ] Arrow keys navigate within custom components
- [ ] Enter/Space activates buttons and controls
- [ ] Focus indicators clearly visible on all elements

#### Screen Reader Testing
- [ ] Headings create logical document structure
- [ ] Form inputs properly labeled and described
- [ ] Error messages announced appropriately
- [ ] Status changes communicated via aria-live regions
- [ ] Tables have proper headers and captions
- [ ] Interactive elements have descriptive names

#### Color Contrast Validation
- [ ] All text meets 4.5:1 contrast minimum
- [ ] Large text meets 3:1 contrast minimum
- [ ] Focus indicators have 3:1 contrast
- [ ] Error states maintain sufficient contrast
- [ ] Theme switching preserves contrast ratios

### 3. Compliance Monitoring

#### Continuous Accessibility Testing
```typescript
// Pre-commit accessibility check
const accessibilityPreCommit = async () => {
  // Run axe-core on all component changes
  const results = await runAxeTests();
  
  // Check for color contrast violations
  const contrastResults = await checkContrast();
  
  // Validate ARIA usage
  const ariaResults = await validateAria();
  
  if (results.violations.length > 0) {
    console.error('Accessibility violations found:', results.violations);
    process.exit(1);
  }
};
```

#### Accessibility Metrics Tracking
```bash
# Generate accessibility scorecard
npm run a11y:scorecard

# Track improvements over time
npm run a11y:metrics

# Validate theme compliance
npm run theme:a11y-check
```

## Implementation Priorities

### Phase 1: Critical Compliance (IMMEDIATE)
1. **Color contrast fixes** - All form inputs and text
2. **Focus indicators** - Visible 2px focus rings
3. **Form labeling** - Proper htmlFor associations
4. **Error messaging** - ARIA alerts and descriptions

### Phase 2: Enhanced Accessibility (SHORT-TERM)  
1. **Keyboard navigation** - Full keyboard operability
2. **Screen reader optimization** - ARIA landmarks and descriptions
3. **Status announcements** - Live regions for state changes
4. **Skip links** - Navigation shortcuts

### Phase 3: Advanced Features (ONGOING)
1. **High contrast mode** - Enhanced visibility options
2. **Reduced motion** - Respect user preferences
3. **Font sizing** - Scalable text support
4. **Voice navigation** - Advanced input methods

## Enforcement and Monitoring

All accessibility requirements are MANDATORY and will be validated through:
- **Pre-commit hooks** - Automated accessibility testing
- **CI/CD pipeline** - Continuous compliance checking  
- **Code reviews** - Manual accessibility assessment
- **User testing** - Real-world accessibility validation

**Failure to meet WCAG AA standards will block deployment and require immediate remediation.**