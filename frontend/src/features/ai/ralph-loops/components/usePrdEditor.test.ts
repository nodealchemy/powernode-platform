import { renderHook, act } from '@testing-library/react';
import { usePrdEditor } from './usePrdEditor';
import type { PrdTask } from '@/shared/services/ai/types/ralph-types';

// Regression: handleRemoveTask / handleDragEnd built a new array but kept the SAME
// element object references, then did `task.priority = idx + 1` — mutating the task
// objects still held in the parent's current `tasks` state snapshot (breaks React
// referential-equality assumptions, undo/optimistic rollback). The renumber must
// produce fresh objects.
const makeTasks = (): PrdTask[] => [
  { key: 'a', description: 'A', priority: 1, dependencies: [] },
  { key: 'b', description: 'B', priority: 2, dependencies: [] },
  { key: 'c', description: 'C', priority: 3, dependencies: [] },
];

describe('usePrdEditor renumber immutability', () => {
  it('handleRemoveTask does not mutate the original task objects', () => {
    const tasks = makeTasks();
    const onChange = jest.fn();
    const { result } = renderHook(() => usePrdEditor({ tasks, onChange, readOnly: false }));

    act(() => result.current.handleRemoveTask(0));

    // The surviving originals keep their original priorities (no in-place mutation)
    expect(tasks[1].priority).toBe(2);
    expect(tasks[2].priority).toBe(3);

    // onChange receives fresh, renumbered objects (not the same refs)
    const passed = onChange.mock.calls[0][0] as PrdTask[];
    expect(passed.map((t) => [t.key, t.priority])).toEqual([['b', 1], ['c', 2]]);
    expect(passed[0]).not.toBe(tasks[1]);
    expect(passed[1]).not.toBe(tasks[2]);
  });

  it('handleDragEnd does not mutate the original task objects', () => {
    const tasks = makeTasks();
    const onChange = jest.fn();
    const { result } = renderHook(() => usePrdEditor({ tasks, onChange, readOnly: false }));

    // Drag 'a' (index 0) to index 2
    act(() => result.current.handleDragStart({ dataTransfer: {} } as unknown as React.DragEvent, 0));
    act(() => result.current.handleDragOver({ preventDefault: () => {} } as unknown as React.DragEvent, 2));
    act(() => result.current.handleDragEnd());

    // Originals unchanged
    expect(tasks.map((t) => [t.key, t.priority])).toEqual([['a', 1], ['b', 2], ['c', 3]]);

    // onChange got the reordered + renumbered fresh objects
    const passed = onChange.mock.calls[0][0] as PrdTask[];
    expect(passed.map((t) => [t.key, t.priority])).toEqual([['b', 1], ['c', 2], ['a', 3]]);
    passed.forEach((t) => expect(tasks).not.toContain(t));
  });
});
