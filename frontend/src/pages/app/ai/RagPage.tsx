// RAG Knowledge Base Page - Knowledge-Augmented Agents
import React, { useState, useEffect, useCallback } from 'react';
import {
  FileText, Search, Database, Upload, Pencil,
  Trash2, Play, Link, BarChart3, MessageSquare, RefreshCw, Plus
} from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import {
  ragApi,
  KnowledgeBase,
  Document as RagDocument,
  RagQuery,
  QueryResult,
  DataConnector,
  RagAnalytics
} from '@/shared/services/ai/RagApiService';

// Type guard for API errors
interface ApiErrorResponse {
  response?: {
    data?: {
      error?: string;
    };
  };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) {
    return error.response?.data?.error || fallback;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}

type TabType = 'knowledge-bases' | 'documents' | 'query' | 'connectors' | 'analytics';

interface RagContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const RagContent: React.FC<RagContentProps> = ({ onActionsReady }) => {
  const { confirm, ConfirmationDialog } = useConfirmation();
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('knowledge-bases');
  const [knowledgeBases, setKnowledgeBases] = useState<KnowledgeBase[]>([]);
  const [selectedKb, setSelectedKb] = useState<KnowledgeBase | null>(null);
  const [documents, setDocuments] = useState<RagDocument[]>([]);
  const [queryHistory, setQueryHistory] = useState<RagQuery[]>([]);
  const [connectors, setConnectors] = useState<DataConnector[]>([]);
  const [analytics, setAnalytics] = useState<RagAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [queryText, setQueryText] = useState('');
  const [queryResult, setQueryResult] = useState<QueryResult | null>(null);
  const [queryLoading, setQueryLoading] = useState(false);

  // Editing KB state
  const [editingKb, setEditingKb] = useState<KnowledgeBase | null>(null);

  // Create/Edit KB modal
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [newKbName, setNewKbName] = useState('');
  const [newKbDescription, setNewKbDescription] = useState('');

  // Connector modal
  const [showConnectorModal, setShowConnectorModal] = useState(false);
  const [newConnectorName, setNewConnectorName] = useState('');
  const [newConnectorType, setNewConnectorType] = useState<string>('notion');
  const [newConnectorFrequency, setNewConnectorFrequency] = useState<string>('daily');


  // Create document modal
  const [showDocModal, setShowDocModal] = useState(false);
  const [newDocName, setNewDocName] = useState('');
  const [newDocContent, setNewDocContent] = useState('');

  const { refreshAction } = useRefreshAction({
    onRefresh: async () => { await loadData(); },
    loading,
  });

  useEffect(() => {
    if (onActionsReady) {
      onActionsReady([refreshAction]);
    }
  }, [onActionsReady, refreshAction]);

  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      loadData();
    }
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadKbData = useCallback(async (kbId: string) => {
    try {
      const [docsRes, historyRes, connectorsRes, analyticsRes] = await Promise.all([
        ragApi.listDocuments(kbId),
        ragApi.getQueryHistory(kbId),
        ragApi.listConnectors(kbId),
        ragApi.getAnalytics(kbId)
      ]);
      setDocuments(docsRes.documents || []);
      setQueryHistory(historyRes.queries || []);
      setConnectors(connectorsRes.connectors || []);
      setAnalytics(analyticsRes);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load knowledge base details')
      }));
    }
  }, [dispatch]);

  useEffect(() => {
    if (selectedKb) {
      loadKbData(selectedKb.id);
    }
  }, [selectedKb, loadKbData]);

  const loadData = async () => {
    try {
      setLoading(true);
      const kbRes = await ragApi.listKnowledgeBases();
      setKnowledgeBases(kbRes.knowledge_bases || []);
      if (kbRes.knowledge_bases?.length > 0 && !selectedKb) {
        setSelectedKb(kbRes.knowledge_bases[0]);
      }
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load knowledge bases')
      }));
    } finally {
      setLoading(false);
    }
  };

  const handleCreateKb = async () => {
    if (!newKbName.trim()) return;
    try {
      const kb = await ragApi.createKnowledgeBase({
        name: newKbName,
        description: newKbDescription || undefined
      });
      dispatch(addNotification({ type: 'success', message: 'Knowledge base created' }));
      setKnowledgeBases([...knowledgeBases, kb]);
      setSelectedKb(kb);
      setShowCreateModal(false);
      setNewKbName('');
      setNewKbDescription('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create knowledge base') }));
    }
  };

  const handleDeleteKb = (kbId: string) => {
    const kbName = knowledgeBases.find(kb => kb.id === kbId)?.name || 'this knowledge base';
    confirm({
      title: 'Delete Knowledge Base',
      message: `Are you sure you want to delete "${kbName}"? This will permanently remove all documents and embeddings.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await ragApi.deleteKnowledgeBase(kbId);
          dispatch(addNotification({ type: 'success', message: 'Knowledge base deleted' }));
          setKnowledgeBases(knowledgeBases.filter(kb => kb.id !== kbId));
          if (selectedKb?.id === kbId) {
            setSelectedKb(knowledgeBases.find(kb => kb.id !== kbId) || null);
          }
        } catch (error) {
          dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to delete knowledge base') }));
        }
      },
    });
  };

  const handleCreateDoc = async () => {
    if (!selectedKb || !newDocName.trim()) return;
    try {
      const doc = await ragApi.createDocument(selectedKb.id, {
        name: newDocName,
        source_type: 'upload',
        content: newDocContent
      });
      dispatch(addNotification({ type: 'success', message: 'Document created' }));
      setDocuments([...documents, doc]);
      setShowDocModal(false);
      setNewDocName('');
      setNewDocContent('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create document') }));
    }
  };

  const handleProcessDoc = async (docId: string) => {
    if (!selectedKb) return;
    try {
      await ragApi.processDocument(selectedKb.id, docId);
      dispatch(addNotification({ type: 'success', message: 'Document processing started' }));
      loadKbData(selectedKb.id);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to process document') }));
    }
  };

  const handleQuery = async () => {
    if (!selectedKb || !queryText.trim()) return;
    try {
      setQueryLoading(true);
      const result = await ragApi.query(selectedKb.id, { query: queryText });
      setQueryResult(result);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Query failed') }));
    } finally {
      setQueryLoading(false);
    }
  };

  const handleDeleteDoc = (docId: string) => {
    if (!selectedKb) return;
    const docName = documents.find(d => d.id === docId)?.name || 'this document';
    confirm({
      title: 'Delete Document',
      message: `Are you sure you want to delete "${docName}"? This will remove the document and all its embeddings.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await ragApi.deleteDocument(selectedKb!.id, docId);
          dispatch(addNotification({ type: 'success', message: 'Document deleted' }));
          setDocuments(documents.filter(d => d.id !== docId));
        } catch (error) {
          dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to delete document') }));
        }
      },
    });
  };

  const handleEditKb = (kb: KnowledgeBase) => {
    setEditingKb(kb);
    setNewKbName(kb.name);
    setNewKbDescription(kb.description || '');
    setShowCreateModal(true);
  };

  const handleUpdateKb = async () => {
    if (!editingKb || !newKbName.trim()) return;
    try {
      const updated = await ragApi.updateKnowledgeBase(editingKb.id, {
        name: newKbName,
        description: newKbDescription || undefined,
      });
      dispatch(addNotification({ type: 'success', message: 'Knowledge base updated' }));
      setKnowledgeBases(knowledgeBases.map(kb => kb.id === updated.id ? updated : kb));
      if (selectedKb?.id === updated.id) setSelectedKb(updated);
      setShowCreateModal(false);
      setEditingKb(null);
      setNewKbName('');
      setNewKbDescription('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to update knowledge base') }));
    }
  };

  const handleCreateConnector = async () => {
    if (!selectedKb || !newConnectorName.trim()) return;
    try {
      const connector = await ragApi.createConnector(selectedKb.id, {
        name: newConnectorName,
        connector_type: newConnectorType,
        sync_frequency: newConnectorFrequency,
      });
      dispatch(addNotification({ type: 'success', message: 'Connector created' }));
      setConnectors([...connectors, connector]);
      setShowConnectorModal(false);
      setNewConnectorName('');
      setNewConnectorType('notion');
      setNewConnectorFrequency('daily');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create connector') }));
    }
  };

  const handleSyncConnector = async (connectorId: string) => {
    if (!selectedKb) return;
    try {
      const result = await ragApi.syncConnector(selectedKb.id, connectorId);
      dispatch(addNotification({ type: 'success', message: result.message || 'Sync started' }));
      loadKbData(selectedKb.id);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to sync connector') }));
    }
  };

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'active': case 'indexed': case 'completed': return 'text-theme-success bg-theme-success/10';
      case 'indexing': case 'processing': case 'pending': return 'text-theme-warning bg-theme-warning/10';
      case 'error': case 'failed': return 'text-theme-danger bg-theme-danger/10';
      case 'paused': case 'archived': return 'text-theme-secondary bg-theme-surface';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const formatBytes = (bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
  };

  const ragTabs = [
    { id: 'knowledge-bases' as TabType, label: 'Knowledge Bases', icon: Database },
    { id: 'documents' as TabType, label: 'Documents', icon: FileText },
    { id: 'query' as TabType, label: 'Query', icon: Search },
    { id: 'connectors' as TabType, label: 'Connectors', icon: Link },
    { id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 }
  ];

  return (
    <div>
      {/* KB Selector */}
      {knowledgeBases.length > 0 && (
        <div className="flex items-center gap-4 mb-6 p-4 bg-theme-surface border border-theme rounded-lg">
          <label className="text-sm font-medium text-theme-primary">Knowledge Base:</label>
          <select
            value={selectedKb?.id || ''}
            onChange={(e) => {
              const kb = knowledgeBases.find(k => k.id === e.target.value);
              setSelectedKb(kb || null);
            }}
            className="flex-1 max-w-md px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
          >
            {knowledgeBases.map(kb => (
              <option key={kb.id} value={kb.id}>
                {kb.name} ({kb.document_count} docs, {kb.chunk_count} chunks) - {kb.status}
              </option>
            ))}
          </select>
          {selectedKb && (
            <div className="flex gap-4 text-sm text-theme-secondary">
              <span>{selectedKb.document_count} documents</span>
              <span>{formatBytes(selectedKb.storage_bytes)}</span>
            </div>
          )}
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex gap-4">
          {ragTabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2 border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-accent text-theme-accent'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon size={16} />
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading knowledge base data...</p>
        </div>
      ) : (
        <>
          {/* Knowledge Bases Tab */}
          {activeTab === 'knowledge-bases' && (
            <div className="space-y-4">
              {knowledgeBases.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Database size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No knowledge bases</h3>
                  <p className="text-theme-secondary mb-6">Create a knowledge base to start building your AI knowledge</p>
                  <button onClick={() => setShowCreateModal(true)} className="btn-theme btn-theme-primary">
                    Create Knowledge Base
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {knowledgeBases.map(kb => (
                    <div
                      key={kb.id}
                      onClick={() => setSelectedKb(kb)}
                      className={`bg-theme-surface border rounded-lg p-4 cursor-pointer transition-colors ${
                        selectedKb?.id === kb.id ? 'border-theme-accent' : 'border-theme hover:border-theme-accent/50'
                      }`}
                    >
                      <div className="flex items-center justify-between mb-2">
                        <h3 className="font-medium text-theme-primary">{kb.name}</h3>
                        <div className="flex items-center gap-2">
                          <span className={`px-2 py-1 text-xs rounded ${getStatusColor(kb.status)}`}>{kb.status}</span>
                          <button
                            onClick={(e) => { e.stopPropagation(); handleEditKb(kb); }}
                            className="text-theme-secondary hover:text-theme-primary transition-colors"
                          >
                            <Pencil size={14} />
                          </button>
                          <button
                            onClick={(e) => { e.stopPropagation(); handleDeleteKb(kb.id); }}
                            className="text-theme-secondary hover:text-theme-danger transition-colors"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      </div>
                      <p className="text-sm text-theme-secondary mb-3">{kb.description || 'No description'}</p>
                      <div className="flex flex-wrap gap-3 text-xs text-theme-secondary">
                        <span>{kb.document_count} docs</span>
                        <span>{kb.chunk_count} chunks</span>
                        <span>{kb.total_tokens.toLocaleString()} tokens</span>
                        <span>{formatBytes(kb.storage_bytes)}</span>
                      </div>
                      <div className="flex gap-2 text-xs text-theme-secondary mt-2">
                        <span>{kb.embedding_model}</span>
                        <span>{kb.chunking_strategy}</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Documents Tab */}
          {activeTab === 'documents' && (
            <div className="space-y-4">
              {!selectedKb ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a knowledge base to view documents</p>
                </div>
              ) : documents.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <FileText size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No documents</h3>
                  <p className="text-theme-secondary mb-6">Add documents to your knowledge base</p>
                  <button onClick={() => setShowDocModal(true)} className="btn-theme btn-theme-primary">
                    <Upload size={16} className="mr-2 inline" /> Add Document
                  </button>
                </div>
              ) : (
                <>
                  <div className="flex justify-end">
                    <button onClick={() => setShowDocModal(true)} className="btn-theme btn-theme-secondary btn-theme-sm">
                      <Upload size={14} className="mr-1 inline" /> Add Document
                    </button>
                  </div>
                  {documents.map(doc => (
                    <div key={doc.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-3">
                          <h3 className="font-medium text-theme-primary">{doc.name}</h3>
                          <span className={`px-2 py-1 text-xs rounded ${getStatusColor(doc.status)}`}>{doc.status}</span>
                          <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{doc.source_type}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          {doc.status === 'pending' && (
                            <button
                              onClick={() => handleProcessDoc(doc.id)}
                              className="btn-theme btn-theme-success btn-theme-sm"
                            >
                              <Play size={14} className="mr-1" /> Process
                            </button>
                          )}
                          <button
                            onClick={() => handleDeleteDoc(doc.id)}
                            className="text-theme-secondary hover:text-theme-danger transition-colors"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      </div>
                      <div className="flex gap-4 text-xs text-theme-secondary">
                        <span>{doc.chunk_count} chunks</span>
                        <span>{doc.token_count.toLocaleString()} tokens</span>
                        <span>{formatBytes(doc.content_size_bytes)}</span>
                        {doc.processed_at && <span>Processed: {new Date(doc.processed_at).toLocaleDateString()}</span>}
                      </div>
                    </div>
                  ))}
                </>
              )}
            </div>
          )}

          {/* Query Tab */}
          {activeTab === 'query' && (
            <div className="space-y-6">
              {!selectedKb ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a knowledge base to query</p>
                </div>
              ) : (
                <>
                  <div className="bg-theme-surface border border-theme rounded-lg p-6">
                    <h3 className="text-lg font-semibold text-theme-primary mb-4">Query Knowledge Base</h3>
                    <div className="flex gap-4">
                      <input
                        type="text"
                        value={queryText}
                        onChange={(e) => setQueryText(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleQuery()}
                        placeholder="Enter your query..."
                        className="flex-1 px-4 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
                      />
                      <button
                        onClick={handleQuery}
                        disabled={queryLoading || !queryText.trim()}
                        className="btn-theme btn-theme-primary"
                      >
                        {queryLoading ? 'Searching...' : 'Search'}
                      </button>
                    </div>
                  </div>

                  {/* Query Result */}
                  {queryResult && (
                    <div className="bg-theme-surface border border-theme rounded-lg p-6">
                      <div className="flex items-center justify-between mb-4">
                        <h3 className="text-lg font-semibold text-theme-primary">Results</h3>
                        <span className="text-sm text-theme-secondary">
                          {queryResult.total_retrieved} chunks in {queryResult.latency_ms}ms
                        </span>
                      </div>
                      <div className="space-y-4">
                        {queryResult.chunks.map((chunk, idx) => (
                          <div key={chunk.chunk_id} className="p-4 bg-theme-bg rounded-lg">
                            <div className="flex items-center justify-between mb-2">
                              <span className="text-xs font-medium text-theme-accent">#{idx + 1}</span>
                              <span className="text-xs text-theme-secondary">Score: {(chunk.score * 100).toFixed(1)}%</span>
                            </div>
                            <p className="text-sm text-theme-primary whitespace-pre-wrap">{chunk.content}</p>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Query History */}
                  {queryHistory.length > 0 && (
                    <div className="bg-theme-surface border border-theme rounded-lg p-6">
                      <h3 className="text-lg font-semibold text-theme-primary mb-4">Recent Queries</h3>
                      <div className="space-y-3">
                        {queryHistory.slice(0, 10).map(q => (
                          <div key={q.id} className="flex items-center justify-between p-3 bg-theme-bg rounded-lg">
                            <div className="flex items-center gap-3">
                              <MessageSquare size={14} className="text-theme-accent" />
                              <span className="text-sm text-theme-primary">{q.query_text}</span>
                            </div>
                            <div className="flex items-center gap-3 text-xs text-theme-secondary">
                              <span>{q.chunks_retrieved} chunks</span>
                              {q.query_latency_ms && <span>{q.query_latency_ms}ms</span>}
                              <span className={`px-2 py-1 rounded ${getStatusColor(q.status)}`}>{q.status}</span>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          )}

          {/* Connectors Tab */}
          {activeTab === 'connectors' && (
            <div className="space-y-4">
              {!selectedKb ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a knowledge base to view connectors</p>
                </div>
              ) : connectors.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Link size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No connectors</h3>
                  <p className="text-theme-secondary mb-6">Connect external data sources to your knowledge base</p>
                  <button onClick={() => setShowConnectorModal(true)} className="btn-theme btn-theme-primary">
                    Add Connector
                  </button>
                </div>
              ) : (
                <>
                <div className="flex justify-end mb-4">
                  <button onClick={() => setShowConnectorModal(true)} className="btn-theme btn-theme-secondary btn-theme-sm">
                    <Plus size={14} className="mr-1 inline" /> Add Connector
                  </button>
                </div>
                {connectors.map(connector => (
                  <div key={connector.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{connector.name}</h3>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(connector.status)}`}>{connector.status}</span>
                        <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{connector.connector_type}</span>
                      </div>
                      <button
                        onClick={() => handleSyncConnector(connector.id)}
                        className="btn-theme btn-theme-secondary btn-theme-sm"
                      >
                        <RefreshCw size={14} className="mr-1" /> Sync
                      </button>
                    </div>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      <span>{connector.documents_synced} docs synced</span>
                      {connector.last_sync_at && <span>Last sync: {new Date(connector.last_sync_at).toLocaleString()}</span>}
                    </div>
                  </div>
                ))}
                </>
              )}
            </div>
          )}

          {/* Analytics Tab */}
          {activeTab === 'analytics' && (
            <div className="space-y-4">
              {!selectedKb ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <p className="text-theme-secondary">Select a knowledge base to view analytics</p>
                </div>
              ) : !analytics ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <BarChart3 size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No analytics data</h3>
                  <p className="text-theme-secondary">Analytics will appear once the knowledge base has been queried</p>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  {Object.entries(analytics).filter(([, value]) => typeof value === 'number' || typeof value === 'string').slice(0, 9).map(([key, value]) => (
                    <div key={key} className="bg-theme-surface border border-theme rounded-lg p-4">
                      <p className="text-sm text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
                      <p className="text-2xl font-bold text-theme-primary">{typeof value === 'number' ? value.toLocaleString() : String(value)}</p>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </>
      )}

      {/* Create/Edit KB Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={() => { setShowCreateModal(false); setEditingKb(null); setNewKbName(''); setNewKbDescription(''); }}
        title={editingKb ? 'Edit Knowledge Base' : 'Create Knowledge Base'}
        maxWidth="md"
        icon={<Database />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => { setShowCreateModal(false); setEditingKb(null); setNewKbName(''); setNewKbDescription(''); }} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={editingKb ? handleUpdateKb : handleCreateKb} disabled={!newKbName.trim()} className="btn-theme btn-theme-primary">
              {editingKb ? 'Update' : 'Create'}
            </button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input
              type="text"
              value={newKbName}
              onChange={(e) => setNewKbName(e.target.value)}
              placeholder="Knowledge base name"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
            <textarea
              value={newKbDescription}
              onChange={(e) => setNewKbDescription(e.target.value)}
              placeholder="Optional description"
              rows={3}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
        </div>
      </Modal>

      {/* Create Document Modal */}
      <Modal
        isOpen={showDocModal}
        onClose={() => setShowDocModal(false)}
        title="Add Document"
        maxWidth="lg"
        icon={<FileText />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setShowDocModal(false)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleCreateDoc} disabled={!newDocName.trim()} className="btn-theme btn-theme-primary">Create</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input
              type="text"
              value={newDocName}
              onChange={(e) => setNewDocName(e.target.value)}
              placeholder="Document name"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Content</label>
            <textarea
              value={newDocContent}
              onChange={(e) => setNewDocContent(e.target.value)}
              placeholder="Enter or paste document content..."
              rows={10}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent font-mono text-sm"
            />
          </div>
        </div>
      </Modal>

      {/* Create Connector Modal */}
      <Modal
        isOpen={showConnectorModal}
        onClose={() => { setShowConnectorModal(false); setNewConnectorName(''); }}
        title="Add Data Connector"
        maxWidth="md"
        icon={<Link />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => { setShowConnectorModal(false); setNewConnectorName(''); }} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleCreateConnector} disabled={!newConnectorName.trim()} className="btn-theme btn-theme-primary">Create</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input
              type="text"
              value={newConnectorName}
              onChange={(e) => setNewConnectorName(e.target.value)}
              placeholder="Connector name"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Connector Type</label>
            <select
              value={newConnectorType}
              onChange={(e) => setNewConnectorType(e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            >
              <option value="notion">Notion</option>
              <option value="confluence">Confluence</option>
              <option value="google_drive">Google Drive</option>
              <option value="dropbox">Dropbox</option>
              <option value="github">GitHub</option>
              <option value="s3">Amazon S3</option>
              <option value="database">Database</option>
              <option value="api">API</option>
              <option value="web_scraper">Web Scraper</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Sync Frequency</label>
            <select
              value={newConnectorFrequency}
              onChange={(e) => setNewConnectorFrequency(e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            >
              <option value="manual">Manual</option>
              <option value="hourly">Hourly</option>
              <option value="daily">Daily</option>
              <option value="weekly">Weekly</option>
            </select>
          </div>
        </div>
      </Modal>

      {ConfirmationDialog}
    </div>
  );
};

const RagPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="RAG Knowledge Bases"
      description="Manage knowledge bases, documents, embeddings, and retrieval-augmented generation"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Knowledge Bases' }
      ]}
      actions={actions}
    >
      <RagContent onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};

export default RagPage;
