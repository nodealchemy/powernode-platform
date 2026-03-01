import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { ContainersPage } from './ContainersPage';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  containerExecutionApi: {
    getContainerInstances: jest.fn(),
    getContainerTemplates: jest.fn(),
    getResourceQuotas: jest.fn(),
    getTemplate: jest.fn(),
    executeTemplate: jest.fn(),
  },
}));

import { containerExecutionApi } from '@/shared/services/ai';
const mockApi = containerExecutionApi as jest.Mocked<typeof containerExecutionApi>;

// Mock the permissions hook
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({
    hasPermission: () => true,
  }),
}));

// Mock the notifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

// Mock TabContainer layout component - render all panels unconditionally for testing
jest.mock('@/shared/components/layout/TabContainer', () => ({
  TabContainer: ({ children, tabs, activeTab, onTabChange }: any) => (
    <div data-testid="tabs" data-value={activeTab}>
      <div data-testid="tabs-list">
        {tabs?.map((tab: any) => (
          <button
            key={tab.id}
            data-testid={`tab-trigger-${tab.id}`}
            onClick={() => onTabChange?.(tab.id)}
          >
            {tab.label}
          </button>
        ))}
      </div>
      {children}
    </div>
  ),
  TabPanel: ({ children, tabId, className }: any) => (
    <div data-testid={`tab-content-${tabId}`} className={className}>
      {children}
    </div>
  ),
}));

// Mock child components
jest.mock('../components/ContainerList', () => ({
  ContainerList: ({ onSelectContainer, onViewLogs }: any) => (
    <div data-testid="container-list">
      Container List
      <button
        data-testid="select-container-btn"
        onClick={() =>
          onSelectContainer?.({
            id: 'container-1',
            status: 'running',
            template: { name: 'Test Template' },
          })
        }
      >
        Select Container
      </button>
      <button
        data-testid="view-logs-btn"
        onClick={() => onViewLogs?.({ id: 'container-1' })}
      >
        View Logs
      </button>
    </div>
  ),
}));

jest.mock('../components/TemplateList', () => ({
  TemplateList: ({ onSelectTemplate, onExecuteTemplate }: any) => (
    <div data-testid="template-list">
      Template List
      <button
        data-testid="select-template-btn"
        onClick={() =>
          onSelectTemplate({ id: 'template-1', name: 'Test Template' })
        }
      >
        Select Template
      </button>
      <button
        data-testid="execute-template-btn"
        onClick={() =>
          onExecuteTemplate({ id: 'template-1', name: 'Test Template' })
        }
      >
        Execute Template
      </button>
    </div>
  ),
}));

jest.mock('../components/QuotaDisplay', () => ({
  QuotaDisplay: ({ compact }: any) => (
    <div data-testid="quota-display" data-compact={compact}>
      Quota Display
    </div>
  ),
}));

jest.mock('../components/TemplateFormModal', () => ({
  TemplateFormModal: ({ isOpen, mode, templateId }: any) =>
    isOpen ? (
      <div data-testid="template-form-modal" data-mode={mode} data-template-id={templateId}>
        Template Form Modal
      </div>
    ) : null,
}));

jest.mock('../components/ExecuteContainerModal', () => ({
  ExecuteContainerModal: ({ isOpen, template }: any) =>
    isOpen ? (
      <div data-testid="execute-container-modal" data-template-id={template?.id}>
        Execute Container Modal
      </div>
    ) : null,
}));

describe('ContainersPage', () => {
  let store: any;

  beforeEach(() => {
    jest.clearAllMocks();

    // Re-setup mock implementations after clearAllMocks
    (mockApi.getTemplate as jest.Mock).mockResolvedValue({
      template: { name: 'Test Template', image_name: 'test:latest' },
    });
    (mockApi as any).executeTemplate.mockResolvedValue({
      execution: { id: 'exec-1' },
    });

    store = configureStore({
      reducer: {
        auth: (state = { user: null, isAuthenticated: false }) => state,
      },
    });
  });

  const renderComponent = (props = {}) => {
    return render(
      <Provider store={store}>
        <BrowserRouter>
          <BreadcrumbProvider>
            <ContainersPage {...props} />
          </BreadcrumbProvider>
        </BrowserRouter>
      </Provider>
    );
  };

  describe('Initial Rendering', () => {
    it('renders the tabs component', () => {
      renderComponent();

      expect(screen.getByTestId('tabs')).toBeInTheDocument();
      expect(screen.getByTestId('tabs-list')).toBeInTheDocument();
    });

    it('renders all tab triggers', () => {
      renderComponent();

      expect(screen.getByTestId('tab-trigger-executions')).toBeInTheDocument();
      expect(screen.getByTestId('tab-trigger-templates')).toBeInTheDocument();
      expect(screen.getByTestId('tab-trigger-quotas')).toBeInTheDocument();
    });

    it('renders container list component', () => {
      renderComponent();

      expect(screen.getByTestId('container-list')).toBeInTheDocument();
    });

    it('renders template list component', () => {
      renderComponent();

      expect(screen.getByTestId('template-list')).toBeInTheDocument();
    });

    it('renders quota display component', () => {
      renderComponent();

      // QuotaDisplay is rendered twice - once compact in header, once in quotas tab
      expect(screen.getAllByTestId('quota-display').length).toBeGreaterThanOrEqual(1);
    });
  });

  describe('Callbacks', () => {
    it('calls onSelectContainer when container is selected', () => {
      const onSelectContainer = jest.fn();
      renderComponent({ onSelectContainer });

      fireEvent.click(screen.getAllByTestId('select-container-btn')[0]);

      expect(onSelectContainer).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'container-1',
          status: 'running',
        })
      );
    });

    it('calls onViewContainerLogs when view logs is clicked', () => {
      const onViewContainerLogs = jest.fn();
      renderComponent({ onViewContainerLogs });

      fireEvent.click(screen.getAllByTestId('view-logs-btn')[0]);

      expect(onViewContainerLogs).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'container-1',
        })
      );
    });

    it('opens edit modal when template is selected', () => {
      renderComponent();

      // Modal should not be visible initially
      expect(screen.queryByTestId('template-form-modal')).not.toBeInTheDocument();

      fireEvent.click(screen.getAllByTestId('select-template-btn')[0]);

      // Edit modal should open with the selected template
      const modal = screen.getByTestId('template-form-modal');
      expect(modal).toBeInTheDocument();
      expect(modal).toHaveAttribute('data-mode', 'edit');
      expect(modal).toHaveAttribute('data-template-id', 'template-1');
    });

    it('opens execute modal when template execution is requested', () => {
      renderComponent();

      // Modal should not be visible initially
      expect(screen.queryByTestId('execute-container-modal')).not.toBeInTheDocument();

      fireEvent.click(screen.getAllByTestId('execute-template-btn')[0]);

      // Execute modal should open with the selected template
      const modal = screen.getByTestId('execute-container-modal');
      expect(modal).toBeInTheDocument();
      expect(modal).toHaveAttribute('data-template-id', 'template-1');
    });

    it('renders quota display in quotas tab', () => {
      renderComponent();

      // QuotaDisplay is rendered twice - once compact in header, once in quotas tab
      const quotaDisplays = screen.getAllByTestId('quota-display');
      expect(quotaDisplays.length).toBeGreaterThanOrEqual(1);
    });
  });

  describe('Tab Content', () => {
    it('shows executions content in executions tab', () => {
      renderComponent();

      expect(screen.getAllByTestId('tab-content-executions')[0]).toBeInTheDocument();
      expect(screen.getAllByTestId('container-list')[0]).toBeInTheDocument();
    });

    it('shows templates content in templates tab', () => {
      renderComponent();

      expect(screen.getAllByTestId('tab-content-templates')[0]).toBeInTheDocument();
      expect(screen.getAllByTestId('template-list')[0]).toBeInTheDocument();
    });

    it('shows quotas content in quotas tab', () => {
      renderComponent();

      expect(screen.getAllByTestId('tab-content-quotas')[0]).toBeInTheDocument();
      expect(screen.getAllByTestId('quota-display')[0]).toBeInTheDocument();
    });
  });
});
