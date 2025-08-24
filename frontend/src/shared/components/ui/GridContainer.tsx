import React from 'react';

export interface GridContainerProps {
  children: React.ReactNode;
  cols?: 'none' | '1' | '2' | '3' | '4' | '5' | '6' | '12' | 'auto' | 'fit' | 'fill';
  rows?: 'none' | '1' | '2' | '3' | '4' | '5' | '6' | 'auto';
  gap?: 'none' | 'xs' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';
  gapX?: 'none' | 'xs' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';
  gapY?: 'none' | 'xs' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';
  flow?: 'row' | 'col' | 'row-dense' | 'col-dense';
  autoFit?: boolean; // grid-cols-[minmax(250px,1fr)]
  autoFill?: boolean; // grid-cols-[minmax(250px,auto)]
  className?: string;
  as?: keyof React.JSX.IntrinsicElements;
}

const colClasses = {
  'none': 'grid-cols-none',
  '1': 'grid-cols-1',
  '2': 'grid-cols-2', 
  '3': 'grid-cols-3',
  '4': 'grid-cols-4',
  '5': 'grid-cols-5',
  '6': 'grid-cols-6',
  '12': 'grid-cols-12',
  'auto': 'grid-cols-auto',
  'fit': 'grid-cols-[repeat(auto-fit,minmax(250px,1fr))]',
  'fill': 'grid-cols-[repeat(auto-fill,minmax(250px,1fr))]'
};

const rowClasses = {
  'none': 'grid-rows-none',
  '1': 'grid-rows-1',
  '2': 'grid-rows-2',
  '3': 'grid-rows-3', 
  '4': 'grid-rows-4',
  '5': 'grid-rows-5',
  '6': 'grid-rows-6',
  'auto': 'grid-rows-auto'
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

const gapXClasses = {
  'none': 'gap-x-0',
  'xs': 'gap-x-1',
  'sm': 'gap-x-2',
  'md': 'gap-x-4', 
  'lg': 'gap-x-6',
  'xl': 'gap-x-8',
  '2xl': 'gap-x-12'
};

const gapYClasses = {
  'none': 'gap-y-0',
  'xs': 'gap-y-1',
  'sm': 'gap-y-2',
  'md': 'gap-y-4',
  'lg': 'gap-y-6',
  'xl': 'gap-y-8',
  '2xl': 'gap-y-12'
};

const flowClasses = {
  'row': 'grid-flow-row',
  'col': 'grid-flow-col',
  'row-dense': 'grid-flow-row-dense',
  'col-dense': 'grid-flow-col-dense'
};

export const GridContainer: React.FC<GridContainerProps> = ({
  children,
  cols = '1',
  rows,
  gap = 'md',
  gapX,
  gapY,
  flow = 'row',
  autoFit,
  autoFill,
  className = '',
  as: Component = 'div'
}) => {
  const classes = [
    'grid',
    autoFit ? 'grid-cols-[repeat(auto-fit,minmax(250px,1fr))]' :
    autoFill ? 'grid-cols-[repeat(auto-fill,minmax(250px,1fr))]' :
    colClasses[cols],
    rows && rowClasses[rows],
    flowClasses[flow],
    // Use individual gap classes if specified, otherwise use general gap
    gapX ? gapXClasses[gapX] : !gapY ? gapClasses[gap] : '',
    gapY ? gapYClasses[gapY] : !gapX ? gapClasses[gap] : '',
    className
  ].filter(Boolean).join(' ');

  return React.createElement(Component, { className: classes }, children);
};


// Commonly used variations as convenience exports
export const GridCols2: React.FC<Omit<GridContainerProps, 'cols'>> = (props) => (
  <GridContainer cols="2" {...props} />
);

export const GridCols3: React.FC<Omit<GridContainerProps, 'cols'>> = (props) => (
  <GridContainer cols="3" {...props} />
);

export const GridCols4: React.FC<Omit<GridContainerProps, 'cols'>> = (props) => (
  <GridContainer cols="4" {...props} />
);

export const GridAutoFit: React.FC<Omit<GridContainerProps, 'autoFit'>> = (props) => (
  <GridContainer autoFit {...props} />
);

export const GridResponsive: React.FC<GridContainerProps> = ({ className = '', ...props }) => (
  <GridContainer 
    className={`grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 ${className}`} 
    {...props} 
  />
);

