import React, { useState, useEffect, useRef, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import {
  Send,
  Bot,
  User,
  X,
  MessageSquare,
  Loader2,
  ChevronDown,
  ChevronUp,
  Maximize2,
  Minimize2
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Avatar } from '@/shared/components/ui/Avatar';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { agentsApi, providersApi } from '@/shared/services/ai';
import { cleanMarkdownContent } from '@/shared/utils/markdownUtils';
import type {
  AiConversation,
  AiMessage,
  AiAgent
} from '@/shared/types/ai';
import type { AiWorkflowNode } from '@/shared/types/workflow';

interface NodeOperationsChatProps {
  isOpen: boolean;
  onClose: () => void;
  operationsAgent?: AiAgent;
  currentNode?: AiWorkflowNode;
  workflowId: string;
}

export const NodeOperationsChat: React.FC<NodeOperationsChatProps> = ({
  isOpen,
  onClose,
  operationsAgent,
  currentNode,
  workflowId
}) => {
  const [conversation, setConversation] = useState<AiConversation | null>(null);
  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const [isMinimized, setIsMinimized] = useState(false);
  const [isExpanded, setIsExpanded] = useState(false);
  const [isInitializing, setIsInitializing] = useState(false);
  const [initializationFailed, setInitializationFailed] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const initializingNodeIdRef = useRef<string | null>(null);
  const operationsAgentRef = useRef(operationsAgent);
  const currentNodeRef = useRef(currentNode);

  const { addNotification } = useNotifications();
  const currentUser = useSelector((state: RootState) => state.auth.user);

  // Keep refs in sync with props
  useEffect(() => {
    operationsAgentRef.current = operationsAgent;
    currentNodeRef.current = currentNode;
  }, [operationsAgent, currentNode]);

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, []);

  // Handle escape key to close
  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen, onClose]);

  // Clean message content to remove chunked encoding artifacts
  const cleanMessageContent = (content: string): string => {
    if (!content) return '';
    let cleaned = cleanMarkdownContent(content);
    cleaned = cleaned
      ?.replace(/[\r\n]*0[\r\n]*$/, '')
      ?.replace(/^[\r\n]*0[\r\n]*/, '')
      ?.replace(/([.!?])\s*0\s*$/, '$1')
      ?.replace(/\s+0\s*$/, '')
      ?.replace(/0$/, '')
      ?.trim() || '';
    return cleaned;
  };

  // Reset conversation state when node changes
  useEffect(() => {
    // When the node changes, reset conversation to force re-initialization
    setConversation(null);
    setMessages([]);
    setIsInitializing(false);
    setInitializationFailed(false);
    initializingNodeIdRef.current = null;
  }, [currentNode?.id]);

  // Initialize conversation when chat opens
  // Use currentNode.id instead of currentNode to prevent re-initialization on object reference changes
  useEffect(() => {
    if (isOpen && operationsAgent && currentNode && !conversation && !isInitializing && !initializationFailed) {
      initializeConversation();
    }
     
  }, [isOpen, operationsAgent?.id, currentNode?.id, conversation?.id, isInitializing, initializationFailed]);

  // Auto-focus input when chat opens and is not minimized
  useEffect(() => {
    if (isOpen && !isMinimized && !loading && inputRef.current) {
      // Small delay to ensure the chat is fully rendered
      setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
    }
  }, [isOpen, isMinimized, loading]);

  const loadMessages = useCallback(async (agentId: string, conversationId: string) => {
    try {
      const messages = await agentsApi.getMessages(agentId, conversationId);
      setMessages(messages.reverse()); // Reverse to show oldest first
      scrollToBottom();
    } catch (_error) {
      // Error loading messages - will display empty state
    }
  }, [scrollToBottom]);

  const initializeConversation = useCallback(async (): Promise<AiConversation | null> => {
    const agent = operationsAgentRef.current;
    const node = currentNodeRef.current;

    // Prevent multiple simultaneous initialization calls for the same node
    if (isInitializing || initializingNodeIdRef.current === node?.id) {
      return null;
    }

    if (!agent || !node) {
      return null;
    }

    initializingNodeIdRef.current = node.id;
    setIsInitializing(true);

    // Validate required data
    if (!agent.id) {
      setIsInitializing(false);
      initializingNodeIdRef.current = null;
      addNotification({
        type: 'error',
        title: 'Chat Error',
        message: 'Operations agent is missing required ID'
      });
      return null;
    }

    if (!node.id) {
      setIsInitializing(false);
      initializingNodeIdRef.current = null;
      addNotification({
        type: 'error',
        title: 'Chat Error',
        message: 'Selected node is missing required ID'
      });
      return null;
    }

    try {
      setLoading(true);

      // Check provider availability before creating conversation
      const agentProvider = agent.provider;
      if (agentProvider) {
        try {
          const availabilityCheck = await providersApi.checkAvailability(agentProvider.id);
          if (!availabilityCheck.availability.available) {
            setIsInitializing(false);
            setInitializationFailed(true);
            initializingNodeIdRef.current = null;
            setLoading(false);
            addNotification({
              type: 'error',
              title: 'Provider Unavailable',
              message: `Cannot start chat: ${availabilityCheck.availability.reason}`
            });
            return null;
          }
        } catch (_error) {
          // Error checking provider availability - continue with conversation creation
        }
      }

      // Create conversation first without initial message
      const conversationData = {
        title: `Node Operations: ${node.name}`,
        metadata: {
          workflow_id: workflowId,
          node_id: node.id,
          node_type: node.node_type,
          operation_type: 'node_configuration'
        }
      };

      const newConversation = await agentsApi.createConversation(agent.id, conversationData);
      setConversation(newConversation);

      try {
        // Send initial context message after conversation is created
        const nodeContext = `Working with ${node.node_type} node: "${node.name}"
Configuration: ${JSON.stringify(node.configuration, null, 2)}
Position: (${node.position_x}, ${node.position_y})`;

        const initialMessage = `I need help configuring this workflow node. Here's the current context:\n\n${nodeContext}\n\nHow can you help me optimize or modify this node?`;

        // Send initial message
        await agentsApi.sendMessage(agent.id, newConversation.id, {
          content: initialMessage,
          metadata: {
            current_node: node,
            workflow_id: workflowId,
            operation_context: 'node_configuration'
          }
        });

        // Load messages to show the conversation
        loadMessages(agent.id, newConversation.id);
        return newConversation;
      } catch (_error) {
        // If message sending fails, clean up the conversation
        try {
          await agentsApi.archiveConversation(agent.id, newConversation.id);
        } catch (_error) {
          // Ignore cleanup errors
        }
        setConversation(null);
        addNotification({
          type: 'error',
          title: 'Chat Error',
          message: 'Failed to send initial message'
        });
        return null;
      }
    } catch (error) {
      const apiError = error as { response?: { status?: number } };
      setInitializationFailed(true);
      addNotification({
        type: 'error',
        title: 'Chat Error',
        message: apiError?.response?.status === 500
          ? 'Server error creating conversation. Please try again or contact support.'
          : 'Failed to initialize chat. Please check your connection and try again.'
      });
      return null;
    } finally {
      setLoading(false);
      setIsInitializing(false);
      initializingNodeIdRef.current = null;
    }
  }, [isInitializing, workflowId, addNotification, loadMessages]);

  const sendMessage = async () => {
    if (!inputValue.trim() || sending || isInitializing) {
      return;
    }

    let activeConversation = conversation;

    // If no conversation exists, try to create one first
    if (!activeConversation) {
      if (!operationsAgent || !currentNode) {
        addNotification({
          type: 'error',
          title: 'Chat Error',
          message: 'Missing agent or node information'
        });
        return;
      }

      activeConversation = await initializeConversation();

      if (!activeConversation) {
        addNotification({
          type: 'error',
          title: 'Chat Error',
          message: 'Failed to initialize conversation'
        });
        return;
      }
    }

    const messageContent = inputValue.trim();
    setInputValue('');
    setSending(true);

    // Need agent ID for API calls
    if (!operationsAgent) {
      setSending(false);
      return;
    }

    try {
      // Add user message immediately for better UX
      const userMessage: AiMessage = {
        id: `temp-${Date.now()}`,
        sender_type: 'user',
        sender_id: currentUser?.id,
        content: messageContent,
        metadata: {
          timestamp: new Date().toISOString()
        },
        created_at: new Date().toISOString(),
        sender_info: {
          name: currentUser?.name || 'User'
        }
      };

      setMessages(prev => [...prev, userMessage]);
      scrollToBottom();

      await agentsApi.sendMessage(operationsAgent.id, activeConversation.id, {
        content: messageContent,
        metadata: {
          current_node: currentNode,
          workflow_id: workflowId,
          operation_context: 'node_configuration'
        }
      });

      // Remove temp message and add real messages
      setMessages(prev => prev.filter(m => m.id !== userMessage.id));
      loadMessages(operationsAgent.id, activeConversation.id);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Chat Error',
        message: 'Failed to send message'
      });
    } finally {
      setSending(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  const handleMinimize = () => {
    setIsMinimized(!isMinimized);
  };

  const handleExpand = () => {
    setIsExpanded(!isExpanded);
  };

  if (!isOpen) return null;

  const chatHeight = isExpanded ? 'h-[80vh]' : isMinimized ? 'h-12' : 'h-96';
  const chatWidth = isExpanded ? 'w-[80vw]' : 'w-96';

  return (
    <div className={`fixed bottom-4 right-4 ${chatWidth} ${chatHeight} bg-theme-surface border border-theme rounded-lg shadow-xl z-50 flex flex-col`}>
      {/* Header */}
      <div className="flex items-center justify-between p-3 border-b border-theme bg-theme-surface rounded-t-lg">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 bg-theme-interactive-primary rounded-lg flex items-center justify-center">
            <MessageSquare className="h-4 w-4 text-white" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-theme-primary text-sm truncate">
              Node Assistant
            </h3>
            {currentNode && (
              <p className="text-xs text-theme-muted truncate">
                {currentNode.name} ({currentNode.node_type})
              </p>
            )}
          </div>
        </div>

        <div className="flex items-center gap-1 flex-shrink-0">
          <Button
            variant="ghost"
            size="sm"
            onClick={handleMinimize}
            className="p-2 h-8 w-8 hover:bg-theme-hover transition-colors"
            title={isMinimized ? "Expand Node Assistant" : "Minimize Node Assistant"}
          >
            {isMinimized ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleExpand}
            className="p-2 h-8 w-8 hover:bg-theme-hover transition-colors"
            title={isExpanded ? "Restore Node Assistant" : "Maximize Node Assistant"}
          >
            {isExpanded ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={onClose}
            className="p-2 h-8 w-8 hover:bg-theme-danger/10 hover:text-theme-danger transition-colors"
            title="Close Node Assistant"
          >
            <X className="h-5 w-5" />
          </Button>
        </div>
      </div>

      {!isMinimized && (
        <>
          {/* Messages Area */}
          <div className="flex-1 overflow-y-auto p-3 space-y-3">
            {loading ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-6 w-6 animate-spin text-theme-muted" />
                <span className="ml-2 text-theme-muted">Initializing chat...</span>
              </div>
            ) : initializationFailed ? (
              <div className="text-center py-8 text-theme-muted">
                <Bot className="h-8 w-8 mx-auto mb-2 opacity-50" />
                <p className="text-sm text-theme-danger">Chat initialization failed</p>
                <p className="text-xs mt-1">The provider is not available. Please configure credentials first.</p>
              </div>
            ) : messages.length === 0 ? (
              <div className="text-center py-8 text-theme-muted">
                <Bot className="h-8 w-8 mx-auto mb-2 opacity-50" />
                <p className="text-sm">Chat with the Node Operations Assistant</p>
                <p className="text-xs mt-1">Ask questions about configuring your workflow nodes</p>
              </div>
            ) : (
              messages.map((message) => (
                <div
                  key={message.id}
                  className="flex gap-3"
                >
                  <Avatar
                    src={message.sender_type === 'user' ? message.sender_info?.avatar_url : undefined}
                    className="h-8 w-8 bg-theme-surface border"
                  >
                    {message.sender_type === 'user' ? <User className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
                  </Avatar>
                  <div className="flex-1">
                    <div
                      className={`inline-block max-w-[80%] p-3 rounded-lg text-sm ${
                        message.sender_type === 'user'
                          ? 'bg-theme-info text-white'
                          : 'bg-theme-surface border border-theme'
                      }`}
                    >
                      {message.sender_type === 'user' ? (
                        message.content
                      ) : (
                        <div className="prose prose-sm max-w-none dark:prose-invert">
                          <ReactMarkdown>
                            {cleanMessageContent(message.content)}
                          </ReactMarkdown>
                        </div>
                      )}
                    </div>
                    <div className="text-xs text-theme-muted mt-1">
                      {new Date(message.created_at).toLocaleTimeString()}
                    </div>
                  </div>
                </div>
              ))
            )}
            <div ref={messagesEndRef} />
          </div>

          {/* Input Area */}
          <div className="border-t border-theme p-3">
            <div className="flex gap-2">
              <textarea
                ref={inputRef}
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                onKeyPress={handleKeyPress}
                placeholder="Ask about node configuration, optimization, or modifications..."
                className="flex-1 resize-none rounded-md border border-theme bg-theme-surface px-3 py-2 text-sm placeholder:text-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent"
                rows={2}
                disabled={sending || loading || initializationFailed}
              />
              <Button
                onClick={sendMessage}
                disabled={!inputValue.trim() || sending || loading || initializationFailed}
                size="sm"
                className="px-3 py-2 h-auto"
              >
                {sending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Send className="h-4 w-4" />
                )}
              </Button>
            </div>
          </div>
        </>
      )}
    </div>
  );
};