# ESLint Configuration Guide - Powernode Frontend

## Overview

The Powernode frontend uses a multi-tier ESLint configuration to balance security, code quality, and developer experience.

## Configuration Files

### 1. `.eslintrc.js` (Development)
- **Purpose**: Primary development configuration
- **Security**: Balanced approach with smart overrides
- **Usage**: `npm run lint`

### 2. `.eslintrc.production.js` (Production)
- **Purpose**: Strict production checks
- **Security**: Maximum security enforcement
- **Usage**: `npm run lint:production`

### 3. `.eslintrc.security.js` (Security Audit)
- **Purpose**: Security-focused linting
- **Security**: All security rules as errors
- **Usage**: `npm run lint:security`

## NPM Scripts

```bash
# Development linting (recommended for daily use)
npm run lint

# Auto-fix development issues
npm run lint:fix

# Security audit (CI/CD)
npm run lint:security

# Production readiness check
npm run lint:production

# Check ESLint configuration
npm run lint:check
```

## Security Rule Strategy

### Object Injection (`security/detect-object-injection`)

**Problem**: ESLint security plugin flags dynamic object property access as potential security issues.

**Our Approach**:
- **Development**: Disabled globally (too many false positives)
- **Admin Components**: Disabled (authenticated, permission-controlled context)
- **UI Components**: Disabled (controlled design system props)
- **Public Components**: Enabled with explicit overrides
- **Production**: Warn level with required eslint-disable comments

### False Positives in Admin Context

These patterns are **safe** in authenticated admin interfaces:
```typescript
// Safe: Service status lookup with known keys
const service = healthStatus.services[serviceName];

// Safe: CSS class mapping with controlled props  
const classes = themeClasses[variant];

// Safe: Form field access with validated keys
const value = formData[fieldName];
```

### Dangerous Patterns (Always Avoided)

```typescript
// Dangerous: User input directly accessing objects
const value = obj[userInput]; // ❌ Never do this

// Dangerous: Dynamic code execution
eval(userCode); // ❌ Blocked by security rules

// Dangerous: Prototype pollution
obj.__proto__ = malicious; // ❌ Prevented
```

## Rule Overrides by Context

### Admin Components (`**/admin/**/*.tsx`)
```javascript
rules: {
  'security/detect-object-injection': 'off', // Safe in authenticated context
  'security/detect-possible-timing-attacks': 'off' // Admin operations authenticated
}
```

### UI Components (`**/shared/components/ui/**/*.tsx`)
```javascript
rules: {
  'security/detect-object-injection': 'off' // Design system prop access controlled
}
```

### Public Components (`**/public/**/*.tsx`)
```javascript
rules: {
  'security/detect-object-injection': 'error', // Strict security
  'security/detect-possible-timing-attacks': 'error'
}
```

### Test Files (`**/*.test.tsx`)
```javascript
rules: {
  'no-console': 'off', // Console allowed in tests
  'security/detect-object-injection': 'off' // Testing requires flexibility
}
```

## Troubleshooting Common Issues

### 1. Build Failing with Security Warnings

**Solution**: Use development ESLint config for builds:
```bash
# Instead of npm run build, use:
ESLINT_NO_DEV_ERRORS=true npm run build
```

### 2. Object Injection False Positives

**Option A**: Use development config (recommended):
```bash
npm run lint # Uses .eslintrc.js with smart overrides
```

**Option B**: Explicit disable (production):
```typescript
// eslint-disable-next-line security/detect-object-injection
const value = safeObject[controlledKey];
```

### 3. TypeScript Integration Issues

Ensure TypeScript ESLint parser is used:
```javascript
parser: '@typescript-eslint/parser',
plugins: ['@typescript-eslint']
```

### 4. CI/CD Integration

Recommended CI/CD pipeline:
```yaml
# Development check (allows admin object access)
- run: npm run lint

# Security audit (strict)  
- run: npm run lint:security

# Production readiness (strict)
- run: npm run lint:production
```

## Best Practices

### 1. Development Workflow
- Use `npm run lint:fix` to auto-fix issues
- Run security audit before PR: `npm run lint:security`
- Check production readiness: `npm run lint:production`

### 2. Security-Conscious Development
- Validate user input before object access
- Use TypeScript for type safety
- Prefer explicit property access over dynamic lookups
- Document security-critical code sections

### 3. Admin Component Guidelines
- Object property access is allowed (authenticated context)
- Still validate external data sources
- Use TypeScript interfaces to constrain object shapes
- Log security-relevant operations

### 4. Public Component Guidelines
- Follow strict security rules
- Validate all dynamic access
- Use allowlists for object property access
- Sanitize user inputs

## Integration with IDE

### VS Code Configuration (`.vscode/settings.json`)
```json
{
  "eslint.workingDirectories": ["frontend"],
  "eslint.options": {
    "configFile": "frontend/.eslintrc.js"
  },
  "eslint.validate": [
    "javascript",
    "typescript",
    "javascriptreact",
    "typescriptreact"
  ]
}
```

### Enable ESLint Auto-fix on Save
```json
{
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  }
}
```

## Conclusion

This ESLint configuration provides:
- ✅ **Developer-friendly**: Smart overrides reduce false positives
- ✅ **Security-conscious**: Real security issues still caught
- ✅ **Context-aware**: Different rules for different component types
- ✅ **CI/CD ready**: Multiple configurations for different environments
- ✅ **Production-ready**: Strict checks available for production builds

For questions or issues, check the configuration files and this guide for context-specific rule overrides.