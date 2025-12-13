import { useState, useCallback, useRef } from 'react';
import { Node, Edge } from '@xyflow/react';

/**
 * Workflow state snapshot for history
 */
interface WorkflowSnapshot {
  nodes: Node[];
  edges: Edge[];
  timestamp: number;
}

/**
 * Hook for managing workflow history with undo/redo capability
 */
export const useWorkflowHistory = (
  initialNodes: Node[] = [],
  initialEdges: Edge[] = []
) => {
  const [history, setHistory] = useState<WorkflowSnapshot[]>([
    { nodes: initialNodes, edges: initialEdges, timestamp: Date.now() }
  ]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const maxHistorySize = useRef(50); // Keep last 50 states

  // Get current state
  const getCurrentState = useCallback((): WorkflowSnapshot => {
    return history[currentIndex] || { nodes: [], edges: [], timestamp: Date.now() };
  }, [history, currentIndex]);

  // Add new state to history
  const pushState = useCallback((nodes: Node[], edges: Edge[], _description: string = 'Change') => {
    setHistory(prevHistory => {
      // Remove any states after current index (when undoing then making new changes)
      const newHistory = prevHistory.slice(0, currentIndex + 1);

      // Add new state
      const newSnapshot: WorkflowSnapshot = {
        nodes: [...nodes],
        edges: [...edges],
        timestamp: Date.now()
      };

      newHistory.push(newSnapshot);

      // Limit history size
      if (newHistory.length > maxHistorySize.current) {
        newHistory.shift();
        setCurrentIndex(prev => prev); // Adjust index since we removed first item
        return newHistory;
      }

      setCurrentIndex(newHistory.length - 1);
      return newHistory;
    });
  }, [currentIndex]);

  // Undo operation
  const undo = useCallback((): WorkflowSnapshot | null => {
    if (currentIndex > 0) {
      const newIndex = currentIndex - 1;
      setCurrentIndex(newIndex);
      return history[newIndex];
    }
    return null;
  }, [currentIndex, history]);

  // Redo operation
  const redo = useCallback((): WorkflowSnapshot | null => {
    if (currentIndex < history.length - 1) {
      const newIndex = currentIndex + 1;
      setCurrentIndex(newIndex);
      return history[newIndex];
    }
    return null;
  }, [currentIndex, history]);

  // Check if undo is available
  const canUndo = currentIndex > 0;

  // Check if redo is available
  const canRedo = currentIndex < history.length - 1;

  // Clear history
  const clearHistory = useCallback(() => {
    const currentState = getCurrentState();
    setHistory([currentState]);
    setCurrentIndex(0);
  }, [getCurrentState]);

  // Get history statistics
  const getHistoryStats = useCallback(() => {
    return {
      size: history.length,
      currentIndex,
      canUndo,
      canRedo,
      oldestTimestamp: history[0]?.timestamp,
      newestTimestamp: history[history.length - 1]?.timestamp
    };
  }, [history, currentIndex, canUndo, canRedo]);

  return {
    // State
    currentState: getCurrentState(),
    canUndo,
    canRedo,

    // Actions
    pushState,
    undo,
    redo,
    clearHistory,

    // Utils
    getHistoryStats
  };
};
