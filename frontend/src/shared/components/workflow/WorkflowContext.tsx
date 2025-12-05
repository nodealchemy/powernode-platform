import React, { createContext, useContext } from 'react';
import type { AiWorkflowNode } from '@/shared/types/workflow';
import type { AiAgent } from '@/shared/types/ai';

export interface WorkflowContextType {
  onOpenChat?: (nodeId: string) => void;
  operationsAgent?: AiAgent | null;
  workflowId?: string;
  onNodeUpdate?: (nodeId: string, updates: Partial<AiWorkflowNode>) => void;
}

const WorkflowContext = createContext<WorkflowContextType>({});

export const WorkflowProvider: React.FC<{
  children: React.ReactNode;
  value: WorkflowContextType;
}> = ({ children, value }) => (
  <WorkflowContext.Provider value={value}>
    {children}
  </WorkflowContext.Provider>
);

export const useWorkflowContext = () => {
  const context = useContext(WorkflowContext);
  return context;
};