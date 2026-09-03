import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Loader2, Server, Bot, Globe, Cpu, ExternalLink } from 'lucide-react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { ChatStreamingRenderer } from '@/features/ai/chat/components/ChatStreamingRenderer';
import { ConciergeActionCard } from '@/shared/components/concierge/ConciergeActionCard';
import { chatApi } from '@/features/ai/chat/services/chatApi';
import { logger } from '@/shared/utils/logger';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { provisioningApi } from './services/provisioningApi';
import { UpgradeRequiredCard, type UpgradeReason } from './UpgradeRequiredCard';

export interface BriefCardData {
  type: 'brief_card';
  title?: string;
  summary?: string;
  fields?: Record<string, unknown>;
  [key: string]: unknown;
}

/**
 * Payload shape returned by the provisioning tool / quota guard when the
 * account hits a billing or cost limit. Surfaced in `metadata.upgrade_required`
 * so the chat layer can render <UpgradeRequiredCard /> inline.
 */
export interface UpgradeRequiredPayload {
  requires_upgrade: true;
  reason: UpgradeReason;
  // Nullable, not merely optional: the backend's canonical denial contract
  // (Powernode::BillingBridge::UPGRADE_PAYLOAD_KEYS) always SENDS these keys,
  // carrying null where the value is unknown. Typing them as `?: number`
  // alone is a lie about the wire that tsc will happily believe.
  spent?: number | null;
  cap?: number | null;
  upgrade_url?: string | null;
}

export interface ProvisioningChatMessage {
  id: string;
  sender_type: 'user' | 'ai' | 'system';
  content: string;
  created_at: string;
  metadata?: {
    streaming?: boolean;
    tokens_used?: number;
    actions?: Array<{ type: string; label: string; style: string }>;
    action_context?: {
      type?: string;
      action_type?: string;
      status?: string;
      resolved_at?: string;
    };
    action_metadata?: BriefCardData | Record<string, unknown>;
    concierge_action?: string;
    action_params?: Record<string, unknown>;
    pending_action?: {
      type?: string;
      [key: string]: unknown;
    };
    plan_ready?: {
      mission_id: string;
      [key: string]: unknown;
    };
    mission_id?: string;
    mission_phase?: string;
    /**
     * Set by ProvisioningTool when the account hits a quota / cost cap. When
     * present + truthy, the chat surface renders an UpgradeRequiredCard
     * instead of (or alongside) the regular AI reply.
     */
    upgrade_required?: UpgradeRequiredPayload;
    requires_upgrade?: boolean;
    upgrade_reason?: UpgradeReason;
    [key: string]: unknown;
  };
}

/**
 * Pull a normalized upgrade-required payload off a chat message. Tolerates
 * both the structured `metadata.upgrade_required` shape and a flatter form
 * (`metadata.requires_upgrade: true` + sibling `upgrade_reason` / `spent` / `cap`)
 * so the chat keeps working while Slice C settles its payload contract.
 */
const extractUpgradePayload = (
  msg: ProvisioningChatMessage
): UpgradeRequiredPayload | null => {
  const meta = msg.metadata;
  if (!meta) return null;
  if (meta.upgrade_required && meta.upgrade_required.requires_upgrade) {
    return meta.upgrade_required;
  }
  if (meta.requires_upgrade && meta.upgrade_reason) {
    return {
      requires_upgrade: true,
      reason: meta.upgrade_reason,
      spent: typeof meta.spent === 'number' ? (meta.spent as number) : undefined,
      cap: typeof meta.cap === 'number' ? (meta.cap as number) : undefined,
      upgrade_url:
        typeof meta.upgrade_url === 'string' ? (meta.upgrade_url as string) : undefined,
    };
  }
  return null;
};

const STARTER_CHIPS: Array<{ label: string; prompt: string; icon: React.ElementType }> = [
  { label: 'SaaS API', prompt: 'I want to provision a SaaS API backend.', icon: Server },
  { label: 'Bot', prompt: 'Help me provision infrastructure for a bot.', icon: Bot },
  { label: 'GPU job', prompt: 'I need to provision a GPU job runner.', icon: Cpu },
  { label: 'Static site', prompt: 'I want to provision a static site.', icon: Globe },
];

export interface ProjectProvisioningChatProps {
  conversationId: string;
  onOpenPlan: (missionId: string) => void;
  onMissionUpdate?: (mission: { id: string; phase: string }) => void;
  /**
   * Optional renderer for the companion rail. Receives the latest detected
   * `brief_card` metadata (or null if none). Slice B wires this to <BriefCard />.
   */
  renderBriefCard?: (data: BriefCardData | null) => React.ReactNode;
}

type FetchedMessages = { messages?: ProvisioningChatMessage[] } & Record<string, unknown>;

/**
 * Chat-first entry point for the AI provisioning flow.
 *
 * Renders the canonical ChatStreamingRenderer for assistant messages,
 * existing ConciergeActionCard for `provision_infrastructure` actions,
 * and an "Open Plan" button when the AI emits a `plan_ready` event.
 */
export const ProjectProvisioningChat: React.FC<ProjectProvisioningChatProps> = ({
  conversationId,
  onOpenPlan,
  onMissionUpdate,
  renderBriefCard,
}) => {
  const [messages, setMessages] = useState<ProvisioningChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement | null>(null);

  const { subscribe, isConnected } = useWebSocket();
  const { addNotification } = useNotifications();

  const fetchMessages = useCallback(async () => {
    if (!conversationId) return;
    setLoading(true);
    try {
      const payload = await provisioningApi.getConversationMessages(conversationId);
      const data = ((payload as { data?: unknown } | undefined)?.data ?? payload ?? {}) as FetchedMessages;
      const fetched: ProvisioningChatMessage[] = Array.isArray(data)
        ? (data as ProvisioningChatMessage[])
        : Array.isArray(data.messages)
          ? data.messages
          : [];
      setMessages(fetched);
    } catch (err) {
      logger.error('Failed to load provisioning conversation messages', err);
      addNotification({ type: 'error', message: 'Failed to load messages' });
    } finally {
      setLoading(false);
    }
  }, [conversationId, addNotification]);

  useEffect(() => {
    fetchMessages();
  }, [fetchMessages]);

  // Subscribe to AiConversationChannel for streaming/new messages.
  // (The Rails channel class is `AiConversationChannel`. Using the bare
  // `'ConversationChannel'` value matches no server-side channel and
  // surfaces as `Subscription class not found: "ConversationChannel"` in
  // backend logs, breaking live message streaming silently.)
  useEffect(() => {
    if (!isConnected || !conversationId) return;
    const unsub = subscribe({
      channel: 'AiConversationChannel',
      params: { conversation_id: conversationId },
      onMessage: (data: unknown) => {
        const evt = data as {
          event?: string;
          message?: ProvisioningChatMessage;
          payload?: Record<string, unknown>;
        };
        if (evt?.event === 'message_created' && evt.message) {
          const incoming = evt.message;
          setMessages((prev) => (prev.some((m) => m.id === incoming.id) ? prev : [...prev, incoming]));
        } else if (evt?.event === 'message_updated' && evt.message) {
          const updated = evt.message;
          setMessages((prev) => prev.map((m) => (m.id === updated.id ? updated : m)));
        }
      },
      onError: (err) => logger.warn('AiConversationChannel error', { err }),
    });
    return () => {
      if (unsub) unsub();
    };
  }, [isConnected, conversationId, subscribe]);

  // Detect plan_ready / mission_phase changes and notify parent
  useEffect(() => {
    if (!onMissionUpdate) return;
    const last = [...messages].reverse().find((m) => m.metadata?.mission_id);
    if (last?.metadata?.mission_id && last.metadata.mission_phase) {
      onMissionUpdate({ id: last.metadata.mission_id, phase: last.metadata.mission_phase });
    }
  }, [messages, onMissionUpdate]);

  // Auto-scroll
  useEffect(() => {
    if (typeof messagesEndRef.current?.scrollIntoView === 'function') {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages.length]);

  const latestBriefCard = useMemo<BriefCardData | null>(() => {
    for (let i = messages.length - 1; i >= 0; i--) {
      const meta = messages[i]?.metadata?.action_metadata as BriefCardData | undefined;
      if (meta && meta.type === 'brief_card') return meta;
    }
    return null;
  }, [messages]);

  const handleSend = useCallback(
    async (overrideContent?: string) => {
      const content = (overrideContent ?? input).trim();
      if (!content || sending) return;
      setSending(true);
      try {
        // Optimistic user message
        const optimisticId = `optimistic-${Date.now()}`;
        setMessages((prev) => [
          ...prev,
          {
            id: optimisticId,
            sender_type: 'user',
            content,
            created_at: new Date().toISOString(),
          },
        ]);
        setInput('');
        await provisioningApi.sendConversationMessage(conversationId, content);
      } catch (err) {
        logger.error('Failed to send provisioning message', err);
        addNotification({ type: 'error', message: 'Failed to send message' });
      } finally {
        setSending(false);
      }
    },
    [input, sending, conversationId, addNotification]
  );

  const handleStarterChip = useCallback((prompt: string) => {
    setInput(prompt);
  }, []);

  const handleConciergeConfirmed = useCallback(() => {
    fetchMessages();
  }, [fetchMessages]);

  return (
    <div className="flex h-full w-full flex-col md:flex-row gap-3" data-testid="project-provisioning-chat">
      {/* Chat surface */}
      <div className="flex flex-1 flex-col min-w-0 bg-theme-surface border border-theme rounded-lg overflow-hidden">
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {loading && messages.length === 0 && (
            <div className="flex items-center gap-2 text-theme-secondary text-sm">
              <Loader2 className="h-4 w-4 animate-spin text-theme-info-fg" />
              Loading conversation…
            </div>
          )}
          {messages.length === 0 && !loading && (
            <div className="flex flex-col items-center justify-center py-10 px-4 text-center">
              <div className="w-12 h-12 rounded-2xl bg-theme-interactive-primary/10 flex items-center justify-center mb-3">
                <Server className="h-6 w-6 text-theme-interactive-primary" />
              </div>
              <h3 className="text-base font-semibold text-theme-primary mb-1">
                What do you want to provision?
              </h3>
              <p className="text-sm text-theme-secondary">
                Describe your project — pick a starter or type your own.
              </p>
            </div>
          )}
          {messages.map((msg) => {
            const isUser = msg.sender_type === 'user';
            const isAI = msg.sender_type === 'ai';
            const meta = msg.metadata ?? {};
            const planReady = meta.plan_ready;
            const isProvisioningAction =
              meta.pending_action?.type === 'provision_infrastructure' && !!meta.concierge_action;
            const upgradeRequired = extractUpgradePayload(msg);

            return (
              <div
                key={msg.id}
                className={`flex ${isUser ? 'justify-end' : 'justify-start'}`}
                data-testid={`msg-${msg.sender_type}`}
              >
                <div
                  className={`max-w-[85%] rounded-2xl px-4 py-3 shadow-sm ${
                    isUser
                      ? 'bg-theme-interactive-primary/10 border border-theme-interactive-primary/20 text-theme-primary'
                      : 'bg-theme-background-secondary border border-theme text-theme-primary'
                  }`}
                >
                  {isAI ? (
                    <ChatStreamingRenderer
                      content={msg.content}
                      isStreaming={!!meta.streaming}
                      tokenCount={meta.tokens_used}
                    />
                  ) : (
                    <div className="text-sm whitespace-pre-wrap text-theme-primary">{msg.content}</div>
                  )}

                  {isAI && upgradeRequired && (
                    <div className="mt-3">
                      <UpgradeRequiredCard
                        reason={upgradeRequired.reason}
                        spent={upgradeRequired.spent}
                        cap={upgradeRequired.cap}
                        upgradeUrl={upgradeRequired.upgrade_url}
                      />
                    </div>
                  )}

                  {isAI && !upgradeRequired && isProvisioningAction && (
                    <ConciergeActionCard
                      actions={
                        meta.actions ?? [
                          { type: 'confirm', label: 'Confirm', style: 'primary' },
                          { type: 'modify', label: 'Modify', style: 'secondary' },
                        ]
                      }
                      actionContext={{
                        type: 'concierge',
                        action_type: meta.action_context?.action_type ?? 'provision_infrastructure',
                        status: meta.action_context?.status ?? 'pending',
                        resolved_at: meta.action_context?.resolved_at,
                      }}
                      actionParams={meta.action_params ?? {}}
                      onConfirm={(actionType, actionParams) => chatApi.confirmConciergeAction(conversationId, actionType, actionParams)}
                      onConfirmed={handleConciergeConfirmed}
                    />
                  )}

                  {isAI && planReady?.mission_id && (
                    <button
                      type="button"
                      onClick={() => onOpenPlan(planReady.mission_id)}
                      data-testid="open-plan-button"
                      className="mt-3 inline-flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium bg-theme-interactive-primary text-white hover:opacity-90 transition-opacity"
                    >
                      <ExternalLink className="h-4 w-4" />
                      Open Plan
                    </button>
                  )}
                </div>
              </div>
            );
          })}
          <div ref={messagesEndRef} />
        </div>

        {/* Input + starter chips */}
        <div className="border-t border-theme bg-theme-surface p-3 space-y-2">
          <div className="flex flex-wrap gap-2" data-testid="starter-chips">
            {STARTER_CHIPS.map(({ label, prompt, icon: Icon }) => (
              <button
                key={label}
                type="button"
                onClick={() => handleStarterChip(prompt)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium border border-theme bg-theme-background-secondary text-theme-primary hover:bg-theme-interactive-primary/10 hover:border-theme-interactive-primary/40 transition-colors"
              >
                <Icon className="h-3.5 w-3.5" aria-hidden="true" />
                {label}
              </button>
            ))}
          </div>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              handleSend();
            }}
            className="flex items-end gap-2"
          >
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  handleSend();
                }
              }}
              placeholder="Describe what you want to provision…"
              disabled={sending}
              rows={2}
              data-testid="chat-input"
              className="flex-1 resize-none px-3 py-2 text-sm rounded-md bg-theme-background-secondary border border-theme text-theme-primary placeholder:text-theme-secondary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={sending || !input.trim()}
              className="px-4 py-2 rounded-md text-sm font-medium bg-theme-interactive-primary text-white hover:opacity-90 disabled:opacity-50 transition-opacity"
            >
              {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Send'}
            </button>
          </form>
        </div>
      </div>

      {/* Companion rail */}
      {renderBriefCard && (
        <aside
          className="md:w-80 lg:w-96 shrink-0"
          data-testid="companion-rail"
          aria-label="Provisioning brief"
        >
          {renderBriefCard(latestBriefCard)}
        </aside>
      )}
    </div>
  );
};

export default ProjectProvisioningChat;
