// Hook for managing chat functionality in workflow builder

import { useState, useCallback, useEffect } from 'react';
import { Node } from '@xyflow/react';
import { AiAgent } from '@/shared/types/ai';
import { AiWorkflowNode } from '@/shared/types/workflow';
import { agentsApi } from '@/shared/services/ai';

interface UseWorkflowBuilderChatOptions {
  nodes: Node[];
  setNodes: React.Dispatch<React.SetStateAction<Node[]>>;
  setHasChanges: React.Dispatch<React.SetStateAction<boolean>>;
}

interface UseWorkflowBuilderChatReturn {
  isChatOpen: boolean;
  chatNodeId: string | null;
  operationsAgent: AiAgent | null;
  handleOpenChat: (nodeId: string) => void;
  handleCloseChat: () => void;
  handleNodeUpdateFromChat: (nodeId: string, updates: Partial<AiWorkflowNode>) => void;
}

export const useWorkflowBuilderChat = ({
  nodes,
  setNodes,
  setHasChanges
}: UseWorkflowBuilderChatOptions): UseWorkflowBuilderChatReturn => {
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [chatNodeId, setChatNodeId] = useState<string | null>(null);
  const [operationsAgent, setOperationsAgent] = useState<AiAgent | null>(null);

  // Load operations agent on mount
  useEffect(() => {
    const loadOperationsAgent = async () => {
      try {
        const response = await agentsApi.getAgents({
          status: 'active',
          per_page: 10
        });

        const agentList = response?.items || [];
        const operationsAgentCandidate = agentList.find((agent: AiAgent) =>
          agent.name?.toLowerCase().includes('operations') ||
          agent.name?.toLowerCase().includes('assistant') ||
          agent.name?.toLowerCase().includes('node')
        ) || agentList[0];

        if (operationsAgentCandidate) {
          setOperationsAgent(operationsAgentCandidate);
        }
      } catch (error) {
        if (process.env.NODE_ENV === 'development') {
          console.error('[WorkflowBuilder] Failed to load operations agent:', error);
        }
      }
    };

    loadOperationsAgent();
  }, []);

  const handleOpenChat = useCallback((nodeId: string) => {
    const node = nodes.find(n => n.id === nodeId);
    if (node) {
      setChatNodeId(nodeId);
      setIsChatOpen(true);
    }
  }, [nodes]);

  const handleCloseChat = useCallback(() => {
    setIsChatOpen(false);
    setChatNodeId(null);
  }, []);

  const handleNodeUpdateFromChat = useCallback((nodeId: string, updates: Partial<AiWorkflowNode>) => {
    setNodes(currentNodes =>
      currentNodes.map(node =>
        node.id === nodeId
          ? { ...node, data: { ...node.data, ...updates } }
          : node
      )
    );
    setHasChanges(true);
  }, [setNodes, setHasChanges]);

  return {
    isChatOpen,
    chatNodeId,
    operationsAgent,
    handleOpenChat,
    handleCloseChat,
    handleNodeUpdateFromChat
  };
};
