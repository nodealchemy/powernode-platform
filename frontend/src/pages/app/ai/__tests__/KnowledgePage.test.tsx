import { screen, fireEvent, waitFor } from '@testing-library/react';
import { Routes, Route } from 'react-router-dom';
import { render } from '@/test-utils';
import { KnowledgePage } from '../KnowledgePage';

// fc-43: Knowledge holds what agents know — Contexts, Tiered Memory, RAG,
// Graph and Learning. Prompts and Skills are their own AI Agents items now,
// and Learning Insights (recommendations, trajectory insights) folded in
// under Learning beside Compound Learning. Each tab is gated on the
// permission its endpoints enforce.

jest.mock('@/pages/app/ai/ContextsPage', () => ({ ContextsContent: () => <div data-testid="contexts-panel" /> }));
jest.mock('@/pages/app/ai/RagPage', () => ({ RagContent: () => <div data-testid="rag-panel" /> }));
jest.mock('@/features/ai/knowledge-graph', () => ({ KnowledgeGraphContent: () => <div data-testid="graph-panel" /> }));
jest.mock('@/features/ai/memory', () => ({ KnowledgeMemoryContent: () => <div data-testid="memory-panel" /> }));
jest.mock('@/pages/app/ai/CompoundLearningPage', () => ({
  CompoundLearningContent: () => <div data-testid="compound-learning-panel" />,
}));
jest.mock('@/features/ai/learning/RecommendationsDashboard', () => ({
  RecommendationsContent: () => <div data-testid="recommendations-panel" />,
}));
jest.mock('@/features/ai/learning/TrajectoryInsights', () => ({
  TrajectoryInsights: () => <div data-testid="insights-panel" />,
}));

const ALL = ['ai.context.read', 'ai.memory.read', 'ai.rag.read', 'ai.knowledge_graph.read', 'ai.analytics.read'];

const renderAt = (path: string, permissions: string[] = ALL) => {
  window.history.pushState({}, '', path);
  return render(
    <Routes>
      <Route path="/app/ai/knowledge/*" element={<KnowledgePage />} />
    </Routes>,
    { preloadedState: { auth: { user: { id: 'u1', permissions }, isAuthenticated: true, isLoading: false } } },
  );
};

const tabLabels = () => screen.getAllByRole('tab').map((t) => t.textContent?.trim());

describe('KnowledgePage (fc-43)', () => {
  it('has exactly Contexts, Tiered Memory, RAG, Graph and Learning', () => {
    renderAt('/app/ai/knowledge');

    expect(tabLabels()).toEqual(['Contexts', 'Tiered Memory', 'RAG', 'Graph', 'Learning']);
  });

  it.each([
    ['/app/ai/knowledge', 'contexts-panel'],
    ['/app/ai/knowledge/contexts', 'contexts-panel'],
    ['/app/ai/knowledge/memory', 'memory-panel'],
    ['/app/ai/knowledge/rag', 'rag-panel'],
    ['/app/ai/knowledge/graph', 'graph-panel'],
    ['/app/ai/knowledge/learning', 'compound-learning-panel'],
    ['/app/ai/knowledge/learning/recommendations', 'recommendations-panel'],
    ['/app/ai/knowledge/learning/insights', 'insights-panel'],
  ])('%s renders its panel', (path, testId) => {
    renderAt(path);

    expect(screen.getByTestId(testId)).toBeInTheDocument();
  });

  it('offers Compound Learning, Recommendations and Insights under Learning', () => {
    renderAt('/app/ai/knowledge/learning');

    for (const label of ['Compound Learning', 'Recommendations', 'Insights']) {
      expect(screen.getByRole('tab', { name: label })).toBeInTheDocument();
    }
  });

  it('switches Learning sub-views by path', async () => {
    renderAt('/app/ai/knowledge/learning');

    fireEvent.click(screen.getByRole('tab', { name: 'Insights' }));

    await waitFor(() => expect(window.location.pathname).toBe('/app/ai/knowledge/learning/insights'));
    expect(screen.getByTestId('insights-panel')).toBeInTheDocument();
  });

  it('shows only the tabs the viewer may read', () => {
    renderAt('/app/ai/knowledge', ['ai.rag.read', 'ai.analytics.read']);

    expect(tabLabels()).toEqual(['RAG', 'Learning']);
    expect(screen.getByTestId('rag-panel')).toBeInTheDocument();
    expect(screen.queryByTestId('contexts-panel')).not.toBeInTheDocument();
  });

  it('does not render a gated tab reached by URL', () => {
    renderAt('/app/ai/knowledge/memory', ['ai.rag.read']);

    expect(screen.queryByTestId('memory-panel')).not.toBeInTheDocument();
    expect(screen.getByTestId('rag-panel')).toBeInTheDocument();
  });
});
