import React, { useRef, useCallback, useEffect, useMemo } from 'react';
import { ChatWindow } from './ChatWindow';
import { useChatWindow } from '../context/ChatWindowContext';

const MIN_WIDTH = 360;
const MIN_HEIGHT = 400;
const DEFAULT_RIGHT = 16;
const DEFAULT_BOTTOM = 80;

function clampPosition(left: number, top: number, width: number, height: number) {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  // Ensure at least the header (40px) is visible and 100px of width stays on-screen
  return {
    left: Math.max(0, Math.min(vw - 100, left)),
    top: Math.max(0, Math.min(vh - 40, top)),
    width: Math.min(width, vw),
    height: Math.min(height, vh),
  };
}

export const ChatWindowFloating: React.FC = () => {
  const { state, dispatch } = useChatWindow();
  const containerRef = useRef<HTMLDivElement>(null);
  const dragState = useRef<{ startX: number; startY: number; startLeft: number; startTop: number } | null>(null);

  // Compute initial inline style so the first paint is correct (no useEffect flash)
  const initialStyle = useMemo(() => {
    const { floatingPosition, floatingSize } = state;
    let left: number;
    let top: number;
    if (floatingPosition.x >= 0 && floatingPosition.y >= 0) {
      left = floatingPosition.x;
      top = floatingPosition.y;
    } else {
      left = window.innerWidth - floatingSize.width - DEFAULT_RIGHT;
      top = window.innerHeight - floatingSize.height - DEFAULT_BOTTOM;
    }
    const clamped = clampPosition(left, top, floatingSize.width, floatingSize.height);
    return {
      left: clamped.left,
      top: clamped.top,
      width: clamped.width,
      height: clamped.height,
      minWidth: MIN_WIDTH,
      minHeight: MIN_HEIGHT,
      resize: 'both' as const,
    };
  }, []);  

  const handleDragStart = useCallback((e: React.PointerEvent) => {
    if (!containerRef.current) return;
    e.preventDefault();
    const rect = containerRef.current.getBoundingClientRect();
    dragState.current = {
      startX: e.clientX,
      startY: e.clientY,
      startLeft: rect.left,
      startTop: rect.top,
    };
    containerRef.current.style.cursor = 'grabbing';
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  }, []);

  const handleDragMove = useCallback((e: React.PointerEvent) => {
    if (!dragState.current || !containerRef.current) return;
    const dx = e.clientX - dragState.current.startX;
    const dy = e.clientY - dragState.current.startY;
    const newLeft = Math.max(0, Math.min(window.innerWidth - 100, dragState.current.startLeft + dx));
    const newTop = Math.max(0, Math.min(window.innerHeight - 40, dragState.current.startTop + dy));
    containerRef.current.style.left = `${newLeft}px`;
    containerRef.current.style.top = `${newTop}px`;
  }, []);

  const handleDragEnd = useCallback(() => {
    if (!containerRef.current) return;
    dragState.current = null;
    containerRef.current.style.cursor = '';
    const rect = containerRef.current.getBoundingClientRect();
    dispatch({ type: 'SET_FLOATING_POSITION', payload: { x: rect.left, y: rect.top } });
  }, [dispatch]);

  // ResizeObserver to track manual CSS resize (use borderBoxSize to match box-sizing: border-box)
  useEffect(() => {
    if (!containerRef.current) return;
    const el = containerRef.current;
    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const boxSize = entry.borderBoxSize?.[0];
        const width = boxSize ? boxSize.inlineSize : entry.contentRect.width;
        const height = boxSize ? boxSize.blockSize : entry.contentRect.height;
        if (width >= MIN_WIDTH && height >= MIN_HEIGHT) {
          dispatch({ type: 'SET_FLOATING_SIZE', payload: { width, height } });
        }
      }
    });
    observer.observe(el, { box: 'border-box' });
    return () => observer.disconnect();
  }, [dispatch]);

  return (
    <div
      ref={containerRef}
      className="fixed z-50 border-2 border-theme rounded-xl shadow-2xl ring-1 ring-black/10 dark:ring-white/10 overflow-hidden bg-theme-background"
      style={initialStyle}
      onPointerMove={handleDragMove}
      onPointerUp={handleDragEnd}
    >
      <ChatWindow onDragStart={handleDragStart} />
    </div>
  );
};
