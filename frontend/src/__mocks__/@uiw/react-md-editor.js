import React from 'react';

const MDEditor = React.forwardRef(({ value = '', onChange, ...props }, ref) => {
  return React.createElement('div', { 
    ref,
    'data-testid': 'md-editor',
    ...props
  }, [
    React.createElement('textarea', {
      key: 'editor',
      value: value,
      onChange: onChange ? (e) => onChange(e.target.value) : undefined,
      'data-testid': 'md-editor-textarea'
    }),
    React.createElement('div', {
      key: 'preview',
      'data-testid': 'md-editor-preview',
      dangerouslySetInnerHTML: { __html: value }
    })
  ]);
});

MDEditor.displayName = 'MDEditor';

export default MDEditor;