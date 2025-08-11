import React from 'react';

const ReactMarkdown = ({ children, ...props }) => {
  return React.createElement('div', {
    'data-testid': 'react-markdown',
    dangerouslySetInnerHTML: { __html: children || '' },
    ...props
  });
};

export default ReactMarkdown;