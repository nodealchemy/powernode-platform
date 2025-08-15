import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { WelcomePage } from './WelcomePage';
import { pagesApi } from '../services/pagesApi';

// Mock the API
jest.mock('../services/pagesApi', () => ({
  pagesApi: {
    getPublicPage: jest.fn()
  }
}));

const mockPageContent = {
  data: {
    id: '1',
    title: 'Welcome to Powernode',
    slug: 'welcome',
    content: '# Welcome to Powernode\n\nThe complete subscription lifecycle management platform.',
    status: 'published',
    published_at: new Date().toISOString(),
    word_count: 10,
    estimated_read_time: 1,
    meta_description: null,
    meta_keywords: null
  }
};

describe('WelcomePage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders loading state initially', () => {
    (pagesApi.getPublicPage as jest.Mock).mockReturnValue(new Promise(() => {}));
    
    render(
      <BrowserRouter>
        <WelcomePage />
      </BrowserRouter>
    );

    expect(screen.getByText(/Loading/i)).toBeInTheDocument();
  });

  it('renders page content when loaded successfully', async () => {
    (pagesApi.getPublicPage as jest.Mock).mockResolvedValue(mockPageContent);
    
    render(
      <BrowserRouter>
        <WelcomePage />
      </BrowserRouter>
    );

    await waitFor(() => {
      expect(screen.getByText(/Welcome to Powernode/i)).toBeInTheDocument();
    });
    
    // Check for any subscription-related text (using getAllByText to handle multiple matches)
    const subscriptionTexts = screen.getAllByText(/subscription/i);
    expect(subscriptionTexts.length).toBeGreaterThan(0);
  });

  it('renders error state when page fails to load', async () => {
    (pagesApi.getPublicPage as jest.Mock).mockRejectedValue(
      new Error('Failed to load')
    );
    
    render(
      <BrowserRouter>
        <WelcomePage />
      </BrowserRouter>
    );

    await waitFor(() => {
      expect(screen.getByText(/Something went wrong/i)).toBeInTheDocument();
    });
    
    expect(screen.getByRole('button', { name: /Try Again/i })).toBeInTheDocument();
  });

  it('renders 404 error for non-existent page', async () => {
    (pagesApi.getPublicPage as jest.Mock).mockRejectedValue({
      response: { status: 404 }
    });
    
    render(
      <BrowserRouter>
        <WelcomePage />
      </BrowserRouter>
    );

    await waitFor(() => {
      expect(screen.getByText(/Page Not Found/i)).toBeInTheDocument();
    });
  });

  it('displays header with gradient styling', async () => {
    (pagesApi.getPublicPage as jest.Mock).mockResolvedValue(mockPageContent);
    
    render(
      <BrowserRouter>
        <WelcomePage />
      </BrowserRouter>
    );

    await waitFor(() => {
      const header = screen.getByRole('banner');
      expect(header).toBeInTheDocument();
    });

    // Check for Powernode branding
    const powernodeElements = screen.getAllByText(/Powernode/i);
    expect(powernodeElements.length).toBeGreaterThan(0);
    
    // Check for navigation links
    const signInElements = screen.getAllByText(/Sign In/i);
    expect(signInElements.length).toBeGreaterThan(0);
    
    const getStartedElements = screen.getAllByText(/Get Started|Start/i);
    expect(getStartedElements.length).toBeGreaterThan(0);
  });

  it('displays call-to-action section', async () => {
    (pagesApi.getPublicPage as jest.Mock).mockResolvedValue(mockPageContent);
    
    render(
      <BrowserRouter>
        <WelcomePage />
      </BrowserRouter>
    );

    await waitFor(() => {
      // Check for any CTA-related text more generically
      const ctaTexts = screen.getAllByText(/Ready to|Transform|Business|Plans/i);
      expect(ctaTexts.length).toBeGreaterThan(0);
    });
    
    // Check for plan-related links
    const planElements = screen.getAllByText(/plans/i);
    expect(planElements.length).toBeGreaterThan(0);
  });

  it('updates document title when page loads', async () => {
    (pagesApi.getPublicPage as jest.Mock).mockResolvedValue(mockPageContent);
    
    render(
      <BrowserRouter>
        <WelcomePage />
      </BrowserRouter>
    );

    await waitFor(() => {
      expect(document.title).toBe('Welcome to Powernode | Powernode');
    });
  });

  it('renders with custom page slug', async () => {
    const customSlug = 'custom-welcome';
    (pagesApi.getPublicPage as jest.Mock).mockResolvedValue({
      ...mockPageContent,
      data: { ...mockPageContent.data, slug: customSlug }
    });
    
    render(
      <BrowserRouter>
        <WelcomePage pageSlug={customSlug} />
      </BrowserRouter>
    );

    await waitFor(() => {
      expect(pagesApi.getPublicPage).toHaveBeenCalledWith(customSlug);
    });
  });
});