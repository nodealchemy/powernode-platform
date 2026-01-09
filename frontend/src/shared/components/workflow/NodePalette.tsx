import React, { useState } from 'react';
import {
  Zap,
  Bot,
  Globe,
  GitBranch,
  GitCommit,
  RotateCcw,
  Search,
  Plus,
  ChevronDown,
  ChevronRight,
  RefreshCw,
  Clock,
  Users,
  Workflow,
  Merge,
  Split,
  Webhook,
  Database,
  Mail,
  File,
  Shield,
  FileText,
  Cpu,
  Calendar,
  Bell,
  Play,
  Square,
  BookOpen,
  Wrench,
  PlayCircle,
  Timer,
  XOctagon,
  ClipboardCheck
} from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';

export type WorkflowBuilderMode = 'full' | 'cicd' | 'ai';

export interface NodePaletteProps {
  onAddNode: (nodeType: string, position: { x: number; y: number }, defaultConfig?: Record<string, string>) => void;
  className?: string;
  mode?: WorkflowBuilderMode;
}

interface NodeTypeDefinition {
  type: string;
  label: string;
  description: string;
  icon: React.ReactNode;
  category: string;
  color: keyof typeof nodeColorThemes;
  defaultConfig?: Record<string, string>; // Default configuration for consolidated nodes (action, operation_type)
}

// Node color theme mapping - Using CSS custom properties for theme support
const nodeColorThemes = {
  'trigger': {
    bg: 'bg-[var(--node-trigger-bg)]',
    indicator: 'bg-[var(--node-trigger-bg)]',
    text: 'text-theme-success'
  },
  'ai_agent': {
    bg: 'bg-[var(--node-ai-agent-bg)]',
    indicator: 'bg-[var(--node-ai-agent-bg)]',
    text: 'text-theme-interactive-primary'
  },
  'api_call': {
    bg: 'bg-[var(--node-api-call-bg)]',
    indicator: 'bg-[var(--node-api-call-bg)]',
    text: 'text-theme-info'
  },
  'webhook': {
    bg: 'bg-[var(--node-webhook-bg)]',
    indicator: 'bg-[var(--node-webhook-bg)]',
    text: 'text-theme-interactive-primary'
  },
  'condition': {
    bg: 'bg-[var(--node-condition-bg)]',
    indicator: 'bg-[var(--node-condition-bg)]',
    text: 'text-theme-warning'
  },
  'loop': {
    bg: 'bg-[var(--node-loop-bg)]',
    indicator: 'bg-[var(--node-loop-bg)]',
    text: 'text-theme-warning'
  },
  'transform': {
    bg: 'bg-[var(--node-transformer-bg)]',
    indicator: 'bg-[var(--node-transformer-bg)]',
    text: 'text-theme-secondary'
  },
  'delay': {
    bg: 'bg-[var(--node-delay-bg)]',
    indicator: 'bg-[var(--node-delay-bg)]',
    text: 'text-theme-muted'
  },
  'human_approval': {
    bg: 'bg-[var(--node-webhook-bg)]',
    indicator: 'bg-[var(--node-webhook-bg)]',
    text: 'text-theme-interactive-primary'
  },
  'sub_workflow': {
    bg: 'bg-[var(--node-database-bg)]',
    indicator: 'bg-[var(--node-database-bg)]',
    text: 'text-theme-info'
  },
  'merge': {
    bg: 'bg-[var(--node-merge-bg)]',
    indicator: 'bg-[var(--node-merge-bg)]',
    text: 'text-theme-interactive-primary'
  },
  'split': {
    bg: 'bg-[var(--node-split-bg)]',
    indicator: 'bg-[var(--node-split-bg)]',
    text: 'text-theme-info'
  },
  // New node color themes
  'database': {
    bg: 'bg-[var(--node-database-bg)]',
    indicator: 'bg-[var(--node-database-bg)]',
    text: 'text-theme-info'
  },
  'email': {
    bg: 'bg-[var(--node-email-bg)]',
    indicator: 'bg-[var(--node-email-bg)]',
    text: 'text-theme-info'
  },
  'file': {
    bg: 'bg-[var(--node-file-bg)]',
    indicator: 'bg-[var(--node-file-bg)]',
    text: 'text-theme-interactive-primary'
  },
  'validator': {
    bg: 'bg-[var(--node-validator-bg)]',
    indicator: 'bg-[var(--node-validator-bg)]',
    text: 'text-theme-danger'
  },
  'prompt_template': {
    bg: 'bg-[var(--node-prompt-template-bg)]',
    indicator: 'bg-[var(--node-prompt-template-bg)]',
    text: 'text-theme-interactive-primary'
  },
  'data_processor': {
    bg: 'bg-[var(--node-data-processor-bg)]',
    indicator: 'bg-[var(--node-data-processor-bg)]',
    text: 'text-theme-interactive-primary'
  },
  'scheduler': {
    bg: 'bg-[var(--node-scheduler-bg)]',
    indicator: 'bg-[var(--node-scheduler-bg)]',
    text: 'text-theme-warning'
  },
  'notification': {
    bg: 'bg-[var(--node-notification-bg)]',
    indicator: 'bg-[var(--node-notification-bg)]',
    text: 'text-theme-success'
  },
  // Consolidated Node Types (Phase 1A)
  // KB Article - unified node with action parameter
  'kb_article': {
    bg: 'bg-node-kb-article',
    indicator: 'bg-node-kb-article',
    text: 'text-node-kb-article'
  },
  // Page - unified node with action parameter
  'page': {
    bg: 'bg-node-page',
    indicator: 'bg-node-page',
    text: 'text-node-page'
  },
  // MCP Operation - unified node with operation_type parameter
  'mcp_operation': {
    bg: 'bg-node-mcp-operation',
    indicator: 'bg-node-mcp-operation',
    text: 'text-node-mcp-operation'
  },
  // CI/CD Integration Node Types
  'ci_trigger': {
    bg: 'bg-gradient-to-r from-orange-500 to-orange-600',
    indicator: 'bg-theme-warning',
    text: 'text-theme-warning'
  },
  'ci_wait_status': {
    bg: 'bg-gradient-to-r from-amber-500 to-amber-600',
    indicator: 'bg-amber-500',
    text: 'text-amber-600'
  },
  'ci_get_logs': {
    bg: 'bg-gradient-to-r from-slate-500 to-slate-600',
    indicator: 'bg-slate-500',
    text: 'text-slate-600'
  },
  'ci_cancel': {
    bg: 'bg-gradient-to-r from-red-500 to-red-600',
    indicator: 'bg-theme-danger',
    text: 'text-theme-danger'
  },
  'git_commit_status': {
    bg: 'bg-gradient-to-r from-purple-500 to-purple-600',
    indicator: 'bg-theme-interactive-primary',
    text: 'text-theme-interactive-primary'
  },
  'git_create_check': {
    bg: 'bg-gradient-to-r from-indigo-500 to-indigo-600',
    indicator: 'bg-indigo-500',
    text: 'text-indigo-600'
  },
  // CI/CD Pipeline Node Types
  'git_checkout': {
    bg: 'bg-gradient-to-r from-emerald-500 to-emerald-600',
    indicator: 'bg-theme-success',
    text: 'text-theme-success'
  },
  'git_branch': {
    bg: 'bg-gradient-to-r from-teal-500 to-teal-600',
    indicator: 'bg-teal-500',
    text: 'text-teal-600'
  },
  'git_pull_request': {
    bg: 'bg-gradient-to-r from-purple-500 to-purple-600',
    indicator: 'bg-theme-interactive-primary',
    text: 'text-theme-interactive-primary'
  },
  'git_comment': {
    bg: 'bg-gradient-to-r from-blue-500 to-blue-600',
    indicator: 'bg-theme-info',
    text: 'text-theme-info'
  },
  'deploy': {
    bg: 'bg-gradient-to-r from-rose-500 to-rose-600',
    indicator: 'bg-rose-500',
    text: 'text-rose-600'
  },
  'run_tests': {
    bg: 'bg-gradient-to-r from-green-500 to-green-600',
    indicator: 'bg-theme-success',
    text: 'text-theme-success'
  },
  'shell_command': {
    bg: 'bg-gradient-to-r from-gray-700 to-gray-800',
    indicator: 'bg-gray-600',
    text: 'text-theme-secondary'
  }
} as const;

const nodeTypes: NodeTypeDefinition[] = [
  {
    type: 'start',
    label: 'Start',
    description: 'Simple start point for workflow execution',
    icon: <Play className="h-4 w-4" />,
    category: 'Control',
    color: 'trigger'  // Use same color theme as trigger
  },
  {
    type: 'trigger',
    label: 'Trigger',
    description: 'Event-based start point for workflow execution',
    icon: <Zap className="h-4 w-4" />,
    category: 'Control',
    color: 'trigger'
  },
  {
    type: 'ai_agent',
    label: 'AI Agent',
    description: 'Execute AI model operations',
    icon: <Bot className="h-4 w-4" />,
    category: 'AI',
    color: 'ai_agent'
  },
  {
    type: 'api_call',
    label: 'API Call',
    description: 'Make HTTP requests to external services',
    icon: <Globe className="h-4 w-4" />,
    category: 'Integration',
    color: 'api_call'
  },
  {
    type: 'webhook',
    label: 'Webhook',
    description: 'Receive external webhook notifications',
    icon: <Webhook className="h-4 w-4" />,
    category: 'Integration',
    color: 'webhook'
  },
  {
    type: 'condition',
    label: 'Condition',
    description: 'Branch workflow based on conditions',
    icon: <GitBranch className="h-4 w-4" />,
    category: 'Control',
    color: 'condition'
  },
  {
    type: 'loop',
    label: 'Loop',
    description: 'Iterate over data or conditions',
    icon: <RefreshCw className="h-4 w-4" />,
    category: 'Control',
    color: 'loop'
  },
  {
    type: 'transform',
    label: 'Transform',
    description: 'Transform and manipulate data',
    icon: <RotateCcw className="h-4 w-4" />,
    category: 'Data',
    color: 'transform'
  },
  {
    type: 'delay',
    label: 'Delay',
    description: 'Add delays and scheduling to workflow',
    icon: <Clock className="h-4 w-4" />,
    category: 'Control',
    color: 'delay'
  },
  {
    type: 'human_approval',
    label: 'Human Approval',
    description: 'Require human approval to continue',
    icon: <Users className="h-4 w-4" />,
    category: 'Control',
    color: 'human_approval'
  },
  {
    type: 'sub_workflow',
    label: 'Sub Workflow',
    description: 'Execute another workflow as a step',
    icon: <Workflow className="h-4 w-4" />,
    category: 'Control',
    color: 'sub_workflow'
  },
  {
    type: 'merge',
    label: 'Merge',
    description: 'Merge multiple inputs into one',
    icon: <Merge className="h-4 w-4" />,
    category: 'Data',
    color: 'merge'
  },
  {
    type: 'split',
    label: 'Split',
    description: 'Split data into multiple paths',
    icon: <Split className="h-4 w-4" />,
    category: 'Data',
    color: 'split'
  },
  {
    type: 'end',
    label: 'End',
    description: 'Explicit end point for workflow execution',
    icon: <Square className="h-4 w-4" />,
    category: 'Control',
    color: 'delay'  // Use gray color theme
  },
  // Data Manipulation Nodes
  {
    type: 'database',
    label: 'Database',
    description: 'Execute database operations and queries',
    icon: <Database className="h-4 w-4" />,
    category: 'Data',
    color: 'database'
  },
  {
    type: 'file',
    label: 'File Operation',
    description: 'Read, write, and manipulate files',
    icon: <File className="h-4 w-4" />,
    category: 'Data',
    color: 'file'
  },
  {
    type: 'validator',
    label: 'Data Validator',
    description: 'Validate data against schemas and rules',
    icon: <Shield className="h-4 w-4" />,
    category: 'Data',
    color: 'validator'
  },
  // Communication Nodes
  {
    type: 'email',
    label: 'Send Email',
    description: 'Send emails via various providers',
    icon: <Mail className="h-4 w-4" />,
    category: 'Communication',
    color: 'email'
  },
  {
    type: 'notification',
    label: 'Notification',
    description: 'Send notifications via multiple channels',
    icon: <Bell className="h-4 w-4" />,
    category: 'Communication',
    color: 'notification'
  },
  // AI-Specific Nodes
  {
    type: 'prompt_template',
    label: 'Prompt Template',
    description: 'Define reusable AI prompt templates',
    icon: <FileText className="h-4 w-4" />,
    category: 'AI',
    color: 'prompt_template'
  },
  {
    type: 'data_processor',
    label: 'Data Processor',
    description: 'Advanced data processing and transformation',
    icon: <Cpu className="h-4 w-4" />,
    category: 'AI',
    color: 'data_processor'
  },
  // Integration Nodes
  {
    type: 'scheduler',
    label: 'Scheduler',
    description: 'Schedule and automate workflow execution',
    icon: <Calendar className="h-4 w-4" />,
    category: 'Integration',
    color: 'scheduler'
  },
  // Consolidated Content Management Nodes (Phase 1A)
  {
    type: 'kb_article',
    label: 'KB Article',
    description: 'Manage knowledge base articles (create, read, update, search, publish)',
    icon: <BookOpen className="h-4 w-4" />,
    category: 'Content',
    color: 'kb_article'
  },
  {
    type: 'page',
    label: 'Page',
    description: 'Manage content pages (create, read, update, publish)',
    icon: <FileText className="h-4 w-4" />,
    category: 'Content',
    color: 'page'
  },
  // MCP Operation - consolidated
  {
    type: 'mcp_operation',
    label: 'MCP Operation',
    description: 'Execute MCP server operations (tools, resources, prompts)',
    icon: <Wrench className="h-4 w-4" />,
    category: 'MCP',
    color: 'mcp_operation'
  },
  // CI/CD Integration Nodes
  {
    type: 'ci_trigger',
    label: 'CI Trigger',
    description: 'Trigger CI/CD pipelines (GitHub Actions, GitLab CI)',
    icon: <PlayCircle className="h-4 w-4" />,
    category: 'CI/CD',
    color: 'ci_trigger'
  },
  {
    type: 'ci_wait_status',
    label: 'CI Wait Status',
    description: 'Wait for pipeline to reach expected status',
    icon: <Timer className="h-4 w-4" />,
    category: 'CI/CD',
    color: 'ci_wait_status'
  },
  {
    type: 'ci_get_logs',
    label: 'CI Get Logs',
    description: 'Fetch logs from CI/CD pipeline jobs',
    icon: <FileText className="h-4 w-4" />,
    category: 'CI/CD',
    color: 'ci_get_logs'
  },
  {
    type: 'ci_cancel',
    label: 'CI Cancel',
    description: 'Cancel a running CI/CD pipeline',
    icon: <XOctagon className="h-4 w-4" />,
    category: 'CI/CD',
    color: 'ci_cancel'
  },
  {
    type: 'git_commit_status',
    label: 'Commit Status',
    description: 'Update commit status on Git provider',
    icon: <GitCommit className="h-4 w-4" />,
    category: 'CI/CD',
    color: 'git_commit_status'
  },
  {
    type: 'git_create_check',
    label: 'Create Check',
    description: 'Create GitHub check run for commits',
    icon: <ClipboardCheck className="h-4 w-4" />,
    category: 'CI/CD',
    color: 'git_create_check'
  },
  // CI/CD Pipeline Nodes
  {
    type: 'git_checkout',
    label: 'Git Checkout',
    description: 'Clone repository and checkout code',
    icon: <GitBranch className="h-4 w-4" />,
    category: 'Pipeline',
    color: 'git_checkout'
  },
  {
    type: 'git_branch',
    label: 'Git Branch',
    description: 'Create, switch, or delete branches',
    icon: <GitBranch className="h-4 w-4" />,
    category: 'Pipeline',
    color: 'git_branch'
  },
  {
    type: 'git_pull_request',
    label: 'Create PR',
    description: 'Create a pull request on Git provider',
    icon: <GitBranch className="h-4 w-4" />,
    category: 'Pipeline',
    color: 'git_pull_request'
  },
  {
    type: 'git_comment',
    label: 'Post Comment',
    description: 'Post comment on PR, issue, or commit',
    icon: <Mail className="h-4 w-4" />,
    category: 'Pipeline',
    color: 'git_comment'
  },
  {
    type: 'deploy',
    label: 'Deploy',
    description: 'Deploy to environment (staging, production)',
    icon: <Zap className="h-4 w-4" />,
    category: 'Pipeline',
    color: 'deploy'
  },
  {
    type: 'run_tests',
    label: 'Run Tests',
    description: 'Execute test suite (Jest, RSpec, Pytest, etc.)',
    icon: <Shield className="h-4 w-4" />,
    category: 'Pipeline',
    color: 'run_tests'
  },
  {
    type: 'shell_command',
    label: 'Shell Command',
    description: 'Execute custom shell command',
    icon: <Play className="h-4 w-4" />,
    category: 'Pipeline',
    color: 'shell_command'
  }
];

// Define which node types are available in each mode
const CICD_MODE_NODE_TYPES = [
  'start', 'end', 'condition', 'loop', 'merge', 'split', 'delay',
  'git_checkout', 'git_branch', 'git_pull_request', 'git_comment',
  'deploy', 'run_tests', 'shell_command',
  'ai_agent', 'notification', 'human_approval', 'file',
  'ci_trigger', 'ci_wait_status', 'ci_get_logs', 'ci_cancel',
  'git_commit_status', 'git_create_check'
];

const AI_MODE_NODE_TYPES = [
  'start', 'end', 'trigger', 'condition', 'loop', 'merge', 'split', 'delay',
  'ai_agent', 'prompt_template', 'data_processor', 'transform',
  'database', 'file', 'validator',
  'email', 'notification',
  'api_call', 'webhook', 'scheduler',
  'human_approval', 'sub_workflow',
  'kb_article', 'page', 'mcp_operation'
];

export const NodePalette: React.FC<NodePaletteProps> = ({
  onAddNode,
  className = '',
  mode = 'full'
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const [isCollapsed, setIsCollapsed] = useState(false);

  // Get nodes available for the current mode
  const modeFilteredNodes = nodeTypes.filter(node => {
    if (mode === 'full') return true;
    if (mode === 'cicd') return CICD_MODE_NODE_TYPES.includes(node.type);
    if (mode === 'ai') return AI_MODE_NODE_TYPES.includes(node.type);
    return true;
  });

  // Get available categories for the current mode
  const availableCategories = ['All', ...new Set(modeFilteredNodes.map(n => n.category))];

  // Filter nodes based on search and category
  const filteredNodes = modeFilteredNodes.filter(node => {
    const matchesSearch = node.label.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         node.description.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCategory = selectedCategory === 'All' || node.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  // Group nodes by category
  const nodesByCategory = availableCategories.reduce((acc, category) => {
    if (category === 'All') return acc;
    acc[category] = filteredNodes.filter(node => node.category === category);
    return acc;
  }, {} as Record<string, NodeTypeDefinition[]>);

  const handleNodeClick = (nodeType: string, defaultConfig?: Record<string, string>) => {
    // Add node at a default position - the workflow builder will handle positioning
    const position = {
      x: Math.random() * 300 + 100,
      y: Math.random() * 300 + 100
    };
    onAddNode(nodeType, position, defaultConfig);
  };

  const handleDragStart = (event: React.DragEvent, nodeType: string, defaultConfig?: Record<string, string>) => {
    // Store both node type and default config for drag-drop
    const dragData = defaultConfig
      ? JSON.stringify({ type: nodeType, defaultConfig })
      : nodeType;
    event.dataTransfer.setData('application/reactflow', dragData);
    event.dataTransfer.effectAllowed = 'move';
  };

  if (isCollapsed) {
    return (
      <div className={`bg-theme-surface border border-theme rounded-lg shadow-lg ${className}`}>
        <button
          onClick={() => setIsCollapsed(false)}
          className="w-full p-3 flex items-center justify-between text-theme-primary hover:bg-theme-surface-hover transition-colors"
        >
          <span className="font-medium">Node Palette</span>
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
    );
  }

  return (
    <div className={`bg-theme-surface border border-theme rounded-lg shadow-lg w-80 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between p-3 border-b border-theme">
        <h3 className="font-medium text-theme-primary">Node Palette</h3>
        <button
          onClick={() => setIsCollapsed(true)}
          className="p-1 rounded hover:bg-theme-surface-hover transition-colors"
        >
          <ChevronDown className="h-4 w-4 text-theme-secondary" />
        </button>
      </div>

      {/* Search */}
      <div className="p-3 border-b border-theme">
        <div className="relative">
          <div className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-tertiary pointer-events-none">
            <Search className="h-4 w-4" />
          </div>
          <Input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search nodes..."
            className="w-full pl-10"
          />
        </div>
      </div>

      {/* Category Filter */}
      <div className="p-3 border-b border-theme">
        <div className="flex flex-wrap gap-1">
          {availableCategories.map(category => (
            <button
              key={category}
              onClick={() => setSelectedCategory(category)}
              className={`
                px-3 py-1.5 rounded-full text-xs font-medium transition-all duration-200 border
                ${selectedCategory === category
                  ? 'bg-theme-interactive-primary text-white border-theme-interactive-primary shadow-sm'
                  : 'bg-theme-background text-theme-secondary border-theme hover:bg-theme-surface-hover hover:border-theme-interactive-primary/30 hover:text-theme-primary'
                }
              `}
            >
              {category}
            </button>
          ))}
        </div>
      </div>

      {/* Node List */}
      <div className="max-h-96 overflow-y-auto custom-scrollbar">
        {selectedCategory === 'All' ? (
          // Show all nodes grouped by category
          Object.entries(nodesByCategory).map(([category, nodes]) => {
            if (nodes.length === 0) return null;
            
            return (
              <div key={category} className="p-3">
                <h4 className="text-sm font-medium text-theme-secondary mb-2 uppercase tracking-wide">
                  {category}
                </h4>
                <div className="space-y-2">
                  {nodes.map((node, index) => (
                    <NodePaletteItem
                      key={`${node.type}-${node.label}-${index}`}
                      node={node}
                      onAdd={() => handleNodeClick(node.type, node.defaultConfig)}
                      onDragStart={(e) => handleDragStart(e, node.type, node.defaultConfig)}
                    />
                  ))}
                </div>
              </div>
            );
          })
        ) : (
          // Show filtered nodes
          <div className="p-3">
            <div className="space-y-2">
              {filteredNodes.map((node, index) => (
                <NodePaletteItem
                  key={`${node.type}-${node.label}-${index}`}
                  node={node}
                  onAdd={() => handleNodeClick(node.type, node.defaultConfig)}
                  onDragStart={(e) => handleDragStart(e, node.type, node.defaultConfig)}
                />
              ))}
            </div>
          </div>
        )}

        {filteredNodes.length === 0 && (
          <div className="p-6 text-center text-theme-muted">
            <Search className="h-8 w-8 mx-auto mb-2 opacity-50" />
            <p>No nodes found</p>
            <p className="text-sm">Try adjusting your search or category filter</p>
          </div>
        )}
      </div>

      {/* Instructions */}
      <div className="p-3 border-t border-theme bg-theme-background rounded-b-lg">
        <p className="text-xs text-theme-muted">
          Click to add nodes or drag them to the canvas
        </p>
      </div>
    </div>
  );
};

interface NodePaletteItemProps {
  node: NodeTypeDefinition;
  onAdd: () => void;
  onDragStart: (event: React.DragEvent) => void;
}

const NodePaletteItem: React.FC<NodePaletteItemProps> = ({
  node,
  onAdd,
  onDragStart
}) => {
  return (
    <div
      draggable
      onDragStart={onDragStart}
      className="
        group relative bg-theme-background border border-theme rounded-lg p-3
        hover:border-theme-interactive-primary hover:shadow-lg hover:shadow-theme-interactive-primary/10
        cursor-move transition-all duration-200 ease-out
        active:scale-95 hover:-translate-y-0.5
      "
    >
      {/* Color indicator badge */}
      <div 
        className={`absolute top-2 right-2 w-4 h-4 rounded-full ${nodeColorThemes[node.color]?.indicator || 'bg-theme-interactive-primary'} shadow-sm border-2 border-white dark:border-theme-surface`}
        aria-hidden="true"
      />

      {/* Main content */}
      <div className="flex items-start gap-3">
        {/* Icon */}
        <div className={`
          flex-shrink-0 w-9 h-9 rounded-lg flex items-center justify-center text-white shadow-sm
          ${nodeColorThemes[node.color]?.bg || 'bg-theme-interactive-primary'}
        `}>
          {node.icon}
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <h4 className="font-medium text-theme-primary group-hover:text-theme-interactive-primary transition-colors">
              {node.label}
            </h4>
            <span className={`
              px-1.5 py-0.5 text-[10px] font-medium rounded-md border
              ${nodeColorThemes[node.color]?.text || 'text-theme-interactive-primary'}
              bg-theme-background border-current opacity-60 group-hover:opacity-100
            `}>
              {node.category}
            </span>
          </div>
          <p className="text-xs text-theme-secondary mt-0.5 line-clamp-2 leading-relaxed">
            {node.description}
          </p>
        </div>
      </div>

      {/* Add button overlay */}
      <button
        onClick={onAdd}
        className="
          absolute inset-0 w-full h-full bg-transparent
          opacity-0 group-hover:opacity-100 transition-all duration-200
          flex items-center justify-center
          bg-theme-interactive-primary/5 hover:bg-theme-interactive-primary/10 rounded-lg
        "
        aria-label={`Add ${node.label} node`}
      >
        <div className="bg-theme-interactive-primary rounded-full p-1.5 shadow-lg">
          <Plus className="h-4 w-4 text-white" />
        </div>
      </button>
    </div>
  );
};