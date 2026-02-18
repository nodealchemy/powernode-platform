import React, { useState, useCallback, useRef, useEffect } from 'react';
import { PanelLeftClose, PanelLeft } from 'lucide-react';

interface ResizableListPanelProps {
  storageKeyPrefix: string;
  title: string;
  headerAction?: React.ReactNode;
  tabPills?: React.ReactNode;
  search?: React.ReactNode;
  children: React.ReactNode;
  footer?: React.ReactNode;
  collapsedContent?: React.ReactNode;
  minWidth?: number;
  maxWidth?: number;
  defaultWidth?: number;
  collapsedWidth?: number;
  onKeyDown?: (e: React.KeyboardEvent) => void;
}

export const ResizableListPanel: React.FC<ResizableListPanelProps> = ({
  storageKeyPrefix,
  title,
  headerAction,
  tabPills,
  search,
  children,
  footer,
  collapsedContent,
  minWidth = 240,
  maxWidth = 400,
  defaultWidth = 300,
  collapsedWidth = 48,
  onKeyDown,
}) => {
  const widthKey = `${storageKeyPrefix}-width`;
  const collapsedKey = `${storageKeyPrefix}-collapsed`;

  const [width, setWidth] = useState(() => {
    const saved = localStorage.getItem(widthKey);
    return saved ? Math.max(minWidth, Math.min(maxWidth, parseInt(saved, 10))) : defaultWidth;
  });

  const [collapsed, setCollapsed] = useState(() => {
    return localStorage.getItem(collapsedKey) === 'true';
  });

  const isDragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(0);

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    isDragging.current = true;
    startX.current = e.clientX;
    startWidth.current = width;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [width]);

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!isDragging.current) return;
      const delta = e.clientX - startX.current;
      const newWidth = Math.max(minWidth, Math.min(maxWidth, startWidth.current + delta));
      setWidth(newWidth);
      localStorage.setItem(widthKey, String(newWidth));
    };

    const handleMouseUp = () => {
      isDragging.current = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [minWidth, maxWidth, widthKey]);

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem(collapsedKey, String(next));
      return next;
    });
  }, [collapsedKey]);

  const sidebarWidth = collapsed ? collapsedWidth : width;

  return (
    <div
      className="relative flex flex-col h-full bg-theme-surface border-r border-theme flex-shrink-0"
      style={{ width: sidebarWidth, minWidth: sidebarWidth }}
      onKeyDown={!collapsed ? onKeyDown : undefined}
      tabIndex={collapsed ? undefined : 0}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-3 border-b border-theme">
        {!collapsed && (
          <h3 className="text-sm font-semibold text-theme-primary truncate">{title}</h3>
        )}
        <div className="flex items-center gap-1">
          {!collapsed && headerAction}
          <button
            onClick={toggleCollapsed}
            className="p-1 rounded text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
            title={collapsed ? 'Expand panel' : 'Collapse panel'}
          >
            {collapsed ? <PanelLeft className="h-4 w-4" /> : <PanelLeftClose className="h-4 w-4" />}
          </button>
        </div>
      </div>

      {/* Collapsed mode */}
      {collapsed ? (
        <div className="flex flex-col items-center gap-1.5 py-3">
          {collapsedContent}
        </div>
      ) : (
        <>
          {tabPills}
          {search}
          <div className="flex-1 overflow-y-auto">
            {children}
          </div>
          {footer}
        </>
      )}

      {/* Drag handle */}
      {!collapsed && (
        <div
          onMouseDown={handleMouseDown}
          onDoubleClick={toggleCollapsed}
          className="absolute top-0 right-0 w-1 h-full cursor-col-resize hover:bg-theme-interactive-primary/30 transition-colors"
        />
      )}
    </div>
  );
};
