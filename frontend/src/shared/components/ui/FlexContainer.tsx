import React from 'react';

export interface FlexContainerProps {
  children: React.ReactNode;
  direction?: 'row' | 'col' | 'row-reverse' | 'col-reverse';
  align?: 'start' | 'center' | 'end' | 'stretch' | 'baseline';
  justify?: 'start' | 'center' | 'end' | 'between' | 'around' | 'evenly';
  wrap?: 'wrap' | 'nowrap' | 'wrap-reverse';
  gap?: 'none' | 'xs' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';
  className?: string;
  as?: keyof React.JSX.IntrinsicElements;
}

const directionClasses = {
  'row': 'flex-row',
  'col': 'flex-col',
  'row-reverse': 'flex-row-reverse',
  'col-reverse': 'flex-col-reverse'
};

const alignClasses = {
  'start': 'items-start',
  'center': 'items-center',
  'end': 'items-end',
  'stretch': 'items-stretch',
  'baseline': 'items-baseline'
};

const justifyClasses = {
  'start': 'justify-start',
  'center': 'justify-center', 
  'end': 'justify-end',
  'between': 'justify-between',
  'around': 'justify-around',
  'evenly': 'justify-evenly'
};

const wrapClasses = {
  'wrap': 'flex-wrap',
  'nowrap': 'flex-nowrap',
  'wrap-reverse': 'flex-wrap-reverse'
};

const gapClasses = {
  'none': 'gap-0',
  'xs': 'gap-1',
  'sm': 'gap-2',
  'md': 'gap-4',
  'lg': 'gap-6',
  'xl': 'gap-8',
  '2xl': 'gap-12'
};

export const FlexContainer: React.FC<FlexContainerProps> = ({
  children,
  direction = 'row',
  align = 'center',
  justify = 'start',
  wrap = 'nowrap',
  gap = 'none',
  className = '',
  as: Component = 'div'
}) => {
  const classes = [
    'flex',
    directionClasses[direction],
    alignClasses[align],
    justifyClasses[justify],
    wrapClasses[wrap],
    gapClasses[gap],
    className
  ].filter(Boolean).join(' ');

  return React.createElement(Component, { className: classes }, children);
};


// Commonly used variations as convenience exports
export const FlexRow: React.FC<Omit<FlexContainerProps, 'direction'>> = (props) => (
  <FlexContainer direction="row" {...props} />
);

export const FlexCol: React.FC<Omit<FlexContainerProps, 'direction'>> = (props) => (
  <FlexContainer direction="col" {...props} />
);

export const FlexCentered: React.FC<Omit<FlexContainerProps, 'align' | 'justify'>> = (props) => (
  <FlexContainer align="center" justify="center" {...props} />
);

export const FlexBetween: React.FC<Omit<FlexContainerProps, 'justify'>> = (props) => (
  <FlexContainer justify="between" {...props} />
);

// Most common pattern: flex items-center space-x-*
export const FlexItemsCenter: React.FC<Omit<FlexContainerProps, 'align'>> = (props) => (
  <FlexContainer align="center" gap="sm" {...props} />
);

