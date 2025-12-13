import { renderHook, act } from '@testing-library/react';
import { useWorkflowHistory } from '@/shared/hooks/useWorkflowHistory';
import type { Node, Edge } from '@xyflow/react';

describe('useWorkflowHistory', () => {
  const mockNodes: Node[] = [
    { id: '1', type: 'start', position: { x: 0, y: 0 }, data: { name: 'Start' } },
    { id: '2', type: 'end', position: { x: 100, y: 100 }, data: { name: 'End' } }
  ];

  const mockEdges: Edge[] = [
    { id: 'e1-2', source: '1', target: '2' }
  ];

  it('should initialize with provided nodes and edges', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    expect(result.current.currentState.nodes).toEqual(mockNodes);
    expect(result.current.currentState.edges).toEqual(mockEdges);
    expect(result.current.canUndo).toBe(false);
    expect(result.current.canRedo).toBe(false);
  });

  it('should push new state to history', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    const newNodes: Node[] = [
      ...mockNodes,
      { id: '3', type: 'ai_agent', position: { x: 50, y: 50 }, data: { name: 'Agent' } }
    ];

    act(() => {
      result.current.pushState(newNodes, mockEdges, 'Add node');
    });

    expect(result.current.canUndo).toBe(true);
    expect(result.current.canRedo).toBe(false);
    expect(result.current.currentState.nodes).toEqual(newNodes);
  });

  it('should undo to previous state', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    const newNodes: Node[] = [
      ...mockNodes,
      { id: '3', type: 'ai_agent', position: { x: 50, y: 50 }, data: { name: 'Agent' } }
    ];

    act(() => {
      result.current.pushState(newNodes, mockEdges, 'Add node');
    });

    expect(result.current.currentState.nodes.length).toBe(3);

    act(() => {
      result.current.undo();
    });

    expect(result.current.currentState.nodes.length).toBe(2);
    expect(result.current.currentState.nodes).toEqual(mockNodes);
    expect(result.current.canUndo).toBe(false);
    expect(result.current.canRedo).toBe(true);
  });

  it('should redo to next state', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    const newNodes: Node[] = [
      ...mockNodes,
      { id: '3', type: 'ai_agent', position: { x: 50, y: 50 }, data: { name: 'Agent' } }
    ];

    act(() => {
      result.current.pushState(newNodes, mockEdges, 'Add node');
    });

    act(() => {
      result.current.undo();
    });

    expect(result.current.currentState.nodes.length).toBe(2);

    act(() => {
      result.current.redo();
    });

    expect(result.current.currentState.nodes.length).toBe(3);
    expect(result.current.currentState.nodes).toEqual(newNodes);
    expect(result.current.canUndo).toBe(true);
    expect(result.current.canRedo).toBe(false);
  });

  it('should clear redo history when pushing new state after undo', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    const nodes2: Node[] = [...mockNodes, { id: '3', type: 'ai_agent', position: { x: 50, y: 50 }, data: { name: 'Agent 1' } }];
    const nodes3: Node[] = [...mockNodes, { id: '4', type: 'ai_agent', position: { x: 75, y: 75 }, data: { name: 'Agent 2' } }];

    act(() => {
      result.current.pushState(nodes2, mockEdges, 'Add node 1');
      result.current.pushState(nodes3, mockEdges, 'Add node 2');
    });

    expect(result.current.canUndo).toBe(true);
    expect(result.current.canRedo).toBe(false);

    act(() => {
      result.current.undo();
    });

    expect(result.current.canRedo).toBe(true);

    const nodesBranch: Node[] = [...mockNodes, { id: '5', type: 'condition', position: { x: 60, y: 60 }, data: { name: 'Condition' } }];

    act(() => {
      result.current.pushState(nodesBranch, mockEdges, 'Add condition');
    });

    expect(result.current.canRedo).toBe(false);
    expect(result.current.currentState.nodes).toEqual(nodesBranch);
  });

  it('should limit history to maximum size', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    // Push many states to test limit (default max is 50)
    act(() => {
      for (let i = 3; i <= 55; i++) {
        result.current.pushState(
          [...mockNodes, { id: `${i}`, type: 'ai_agent', position: { x: i * 10, y: i * 10 }, data: { name: `Node ${i}` } }],
          mockEdges,
          `State ${i}`
        );
      }
    });

    const stats = result.current.getHistoryStats();
    expect(stats.size).toBeLessThanOrEqual(50);
  });

  it('should provide accurate history statistics', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    act(() => {
      result.current.pushState([...mockNodes, { id: '3', type: 'ai_agent', position: { x: 50, y: 50 }, data: { name: 'Agent' } }], mockEdges, 'Add node');
    });

    const stats = result.current.getHistoryStats();

    expect(stats.size).toBe(2);
    expect(stats.currentIndex).toBe(1);
    expect(stats.canUndo).toBe(true);
    expect(stats.canRedo).toBe(false);
    expect(stats.oldestTimestamp).toBeDefined();
    expect(stats.newestTimestamp).toBeDefined();
  });

  it('should clear history', () => {
    const { result } = renderHook(() => useWorkflowHistory(mockNodes, mockEdges));

    act(() => {
      result.current.pushState([...mockNodes, { id: '3', type: 'ai_agent', position: { x: 50, y: 50 }, data: { name: 'Agent' } }], mockEdges, 'Add node');
    });

    // Should have 2 states: initial + pushed
    expect(result.current.getHistoryStats().size).toBe(2);

    act(() => {
      result.current.clearHistory();
    });

    const stats = result.current.getHistoryStats();
    expect(stats.size).toBe(1);
    expect(stats.currentIndex).toBe(0);
    expect(result.current.canUndo).toBe(false);
    expect(result.current.canRedo).toBe(false);
  });
});
