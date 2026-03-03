import React from 'react';

import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';

import { RootState } from '@/shared/services';

import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';

import logoIcon from '@/assets/images/logo-icon.png';


export const WelcomePage: React.FC = () => {
  const registrationEnabled = useSelector((state: RootState) => state.config.registrationEnabled);

  return (
    <PublicPageContainer>
      <div className="bg-gradient-to-b from-slate-900 via-slate-900 to-slate-800">

        {/* Hero Section */}
        <section className="relative overflow-hidden pt-8 pb-24">
          {/* Background Decorations */}
          <div className="absolute inset-0 pointer-events-none overflow-hidden">
            <div
              className="absolute -top-40 left-1/4 w-[800px] h-[800px] rounded-full opacity-20"
              style={{ background: 'radial-gradient(circle, rgba(59, 130, 246, 0.3) 0%, transparent 70%)' }}
            />
            <div
              className="absolute -bottom-40 right-1/4 w-[800px] h-[800px] rounded-full opacity-20"
              style={{ background: 'radial-gradient(circle, rgba(139, 92, 246, 0.3) 0%, transparent 70%)' }}
            />
            <div
              className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] rounded-full opacity-10"
              style={{ background: 'radial-gradient(circle, rgba(6, 182, 212, 0.4) 0%, transparent 60%)' }}
            />
          </div>

          <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="text-center">
              {/* Logo */}
              <div className="flex justify-center mb-8">
                <div className="w-20 h-20 rounded-2xl overflow-hidden shadow-2xl shadow-blue-500/20">
                  <img src={logoIcon} alt="Powernode" className="w-20 h-20 object-cover" />
                </div>
              </div>

              {/* Trust Badges */}
              <div className="flex justify-center flex-wrap gap-3 mb-10">
                <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/10">
                  <span className="w-2 h-2 bg-emerald-400 rounded-full animate-pulse" />
                  <span className="text-sm font-medium text-white/90">AI-Native</span>
                </div>
                <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/10">
                  <span className="w-2 h-2 bg-blue-400 rounded-full" />
                  <span className="text-sm font-medium text-white/90">Self-Hosted</span>
                </div>
                <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/10">
                  <span className="w-2 h-2 bg-violet-400 rounded-full" />
                  <span className="text-sm font-medium text-white/90">Enterprise Ready</span>
                </div>
              </div>

              {/* Hero Headline */}
              <h1 className="text-4xl md:text-5xl lg:text-6xl font-bold text-white mb-6 leading-tight">
                The AI Orchestration<br />
                <span className="bg-gradient-to-r from-blue-400 via-cyan-400 to-violet-400 bg-clip-text text-transparent">Platform</span>
              </h1>
              <p className="text-lg md:text-xl text-white/70 max-w-2xl mx-auto mb-12 leading-relaxed">
                Deploy autonomous agents, build knowledge graphs, design multi-step workflows, and manage AI operations at scale — all from a single, self-hosted platform.
              </p>

              {/* CTA Buttons */}
              <div className="flex flex-col sm:flex-row gap-4 justify-center mb-16">
                {registrationEnabled && (
                  <Link to="/plans" className="inline-flex items-center justify-center px-8 py-4 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg shadow-blue-600/30 hover:shadow-xl hover:shadow-blue-600/40 text-lg">
                    Get Started Free
                    <svg className="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
                    </svg>
                  </Link>
                )}
                <Link to="/login" className="inline-flex items-center justify-center px-8 py-4 border-2 border-white/20 hover:border-white/40 text-white font-semibold rounded-xl transition-all duration-200 hover:bg-white/5 text-lg">
                  Sign In
                </Link>
              </div>

              {/* Stats Row */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-6 max-w-4xl mx-auto">
                <div className="text-center">
                  <div className="text-3xl md:text-4xl font-bold text-white mb-1">100+</div>
                  <div className="text-sm text-white/60">MCP Tools</div>
                </div>
                <div className="text-center">
                  <div className="text-3xl md:text-4xl font-bold text-white mb-1">23</div>
                  <div className="text-sm text-white/60">AI Agents</div>
                </div>
                <div className="text-center">
                  <div className="text-3xl md:text-4xl font-bold text-white mb-1">15</div>
                  <div className="text-sm text-white/60">Workflows</div>
                </div>
                <div className="text-center">
                  <div className="text-3xl md:text-4xl font-bold text-white mb-1">24/7</div>
                  <div className="text-sm text-white/60">Autonomous Ops</div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Core Platform Features */}
        <section className="py-24 bg-white/[0.02]">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="text-center mb-16">
              <p className="text-blue-400 font-semibold text-sm tracking-wider uppercase mb-3">Platform Capabilities</p>
              <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">Everything You Need to Orchestrate AI</h2>
              <p className="text-lg text-white/70 max-w-3xl mx-auto">From autonomous agents to knowledge graphs, Powernode provides the complete infrastructure for building, deploying, and managing intelligent systems.</p>
            </div>

            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
              {/* AI Agents */}
              <div className="group bg-white/5 backdrop-blur-sm p-8 rounded-2xl border border-white/10 hover:border-blue-500/30 transition-all duration-300 hover:bg-white/[0.08]">
                <div className="w-14 h-14 bg-gradient-to-br from-blue-500/20 to-blue-600/20 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform duration-300">
                  <svg className="w-7 h-7 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9.75 3.104v5.714a2.25 2.25 0 01-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 014.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19.8 15.3M14.25 3.104c.251.023.501.05.75.082M19.8 15.3l-1.57.393A9.065 9.065 0 0112 15a9.065 9.065 0 00-6.23.693L5 14.5m14.8.8l1.402 1.402c1.232 1.232.65 3.318-1.067 3.611A48.309 48.309 0 0112 21c-2.773 0-5.491-.235-8.135-.687-1.718-.293-2.3-2.379-1.067-3.61L5 14.5" />
                  </svg>
                </div>
                <h3 className="text-xl font-semibold text-white mb-3">AI Agent Orchestration</h3>
                <p className="text-white/60 leading-relaxed mb-4">Deploy autonomous agents with configurable trust tiers, memory systems, and goal-driven execution. Agents collaborate through teams, share knowledge, and learn from outcomes.</p>
                <div className="flex flex-wrap gap-2">
                  <span className="text-xs px-2.5 py-1 bg-blue-500/10 text-blue-300 rounded-full">Multi-Provider</span>
                  <span className="text-xs px-2.5 py-1 bg-blue-500/10 text-blue-300 rounded-full">Trust Tiers</span>
                  <span className="text-xs px-2.5 py-1 bg-blue-500/10 text-blue-300 rounded-full">Goal System</span>
                </div>
              </div>

              {/* Knowledge Graph */}
              <div className="group bg-white/5 backdrop-blur-sm p-8 rounded-2xl border border-white/10 hover:border-violet-500/30 transition-all duration-300 hover:bg-white/[0.08]">
                <div className="w-14 h-14 bg-gradient-to-br from-violet-500/20 to-purple-600/20 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform duration-300">
                  <svg className="w-7 h-7 text-violet-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5" />
                  </svg>
                </div>
                <h3 className="text-xl font-semibold text-white mb-3">Knowledge Graph + RAG</h3>
                <p className="text-white/60 leading-relaxed mb-4">Hybrid search across knowledge graphs, vector embeddings, and keyword indices. Multi-hop reasoning discovers connections across your entire knowledge base.</p>
                <div className="flex flex-wrap gap-2">
                  <span className="text-xs px-2.5 py-1 bg-violet-500/10 text-violet-300 rounded-full">pgvector</span>
                  <span className="text-xs px-2.5 py-1 bg-violet-500/10 text-violet-300 rounded-full">Hybrid Search</span>
                  <span className="text-xs px-2.5 py-1 bg-violet-500/10 text-violet-300 rounded-full">GraphRAG</span>
                </div>
              </div>

              {/* Workflows */}
              <div className="group bg-white/5 backdrop-blur-sm p-8 rounded-2xl border border-white/10 hover:border-cyan-500/30 transition-all duration-300 hover:bg-white/[0.08]">
                <div className="w-14 h-14 bg-gradient-to-br from-cyan-500/20 to-teal-600/20 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform duration-300">
                  <svg className="w-7 h-7 text-cyan-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z" />
                  </svg>
                </div>
                <h3 className="text-xl font-semibold text-white mb-3">Visual Workflow Builder</h3>
                <p className="text-white/60 leading-relaxed mb-4">Design multi-step AI workflows with a node-based visual editor. Chain agents, conditionals, loops, and human-in-the-loop checkpoints into reliable pipelines.</p>
                <div className="flex flex-wrap gap-2">
                  <span className="text-xs px-2.5 py-1 bg-cyan-500/10 text-cyan-300 rounded-full">Node Editor</span>
                  <span className="text-xs px-2.5 py-1 bg-cyan-500/10 text-cyan-300 rounded-full">Conditional Logic</span>
                  <span className="text-xs px-2.5 py-1 bg-cyan-500/10 text-cyan-300 rounded-full">Scheduling</span>
                </div>
              </div>

              {/* Memory System */}
              <div className="group bg-white/5 backdrop-blur-sm p-8 rounded-2xl border border-white/10 hover:border-amber-500/30 transition-all duration-300 hover:bg-white/[0.08]">
                <div className="w-14 h-14 bg-gradient-to-br from-amber-500/20 to-orange-600/20 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform duration-300">
                  <svg className="w-7 h-7 text-amber-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
                  </svg>
                </div>
                <h3 className="text-xl font-semibold text-white mb-3">Tiered Memory Architecture</h3>
                <p className="text-white/60 leading-relaxed mb-4">Three-tier memory (STM, working, long-term) with automatic consolidation. Agents remember context across sessions and share knowledge through memory pools.</p>
                <div className="flex flex-wrap gap-2">
                  <span className="text-xs px-2.5 py-1 bg-amber-500/10 text-amber-300 rounded-full">Auto-Consolidation</span>
                  <span className="text-xs px-2.5 py-1 bg-amber-500/10 text-amber-300 rounded-full">Shared Pools</span>
                  <span className="text-xs px-2.5 py-1 bg-amber-500/10 text-amber-300 rounded-full">Semantic Search</span>
                </div>
              </div>

              {/* MCP Tools */}
              <div className="group bg-white/5 backdrop-blur-sm p-8 rounded-2xl border border-white/10 hover:border-emerald-500/30 transition-all duration-300 hover:bg-white/[0.08]">
                <div className="w-14 h-14 bg-gradient-to-br from-emerald-500/20 to-green-600/20 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform duration-300">
                  <svg className="w-7 h-7 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M11.42 15.17l-5.1-5.1m0 0L11.42 4.97m-5.1 5.1h13.26M4.92 19.92l5.1-5.1m0 0l5.1 5.1m-5.1-5.1V1.56" />
                  </svg>
                </div>
                <h3 className="text-xl font-semibold text-white mb-3">100+ MCP Tools</h3>
                <p className="text-white/60 leading-relaxed mb-4">Model Context Protocol server with 100+ tools across agents, teams, workflows, knowledge, memory, DevOps, and content management. Extend with custom tools.</p>
                <div className="flex flex-wrap gap-2">
                  <span className="text-xs px-2.5 py-1 bg-emerald-500/10 text-emerald-300 rounded-full">MCP Native</span>
                  <span className="text-xs px-2.5 py-1 bg-emerald-500/10 text-emerald-300 rounded-full">Extensible</span>
                  <span className="text-xs px-2.5 py-1 bg-emerald-500/10 text-emerald-300 rounded-full">Semantic Discovery</span>
                </div>
              </div>

              {/* Safety & Autonomy */}
              <div className="group bg-white/5 backdrop-blur-sm p-8 rounded-2xl border border-white/10 hover:border-rose-500/30 transition-all duration-300 hover:bg-white/[0.08]">
                <div className="w-14 h-14 bg-gradient-to-br from-rose-500/20 to-red-600/20 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform duration-300">
                  <svg className="w-7 h-7 text-rose-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
                  </svg>
                </div>
                <h3 className="text-xl font-semibold text-white mb-3">AI Safety & Governance</h3>
                <p className="text-white/60 leading-relaxed mb-4">Emergency kill switch, trust-tiered autonomy, intervention policies, and structured escalation. Full audit trails and human-in-the-loop controls at every level.</p>
                <div className="flex flex-wrap gap-2">
                  <span className="text-xs px-2.5 py-1 bg-rose-500/10 text-rose-300 rounded-full">Kill Switch</span>
                  <span className="text-xs px-2.5 py-1 bg-rose-500/10 text-rose-300 rounded-full">Trust Tiers</span>
                  <span className="text-xs px-2.5 py-1 bg-rose-500/10 text-rose-300 rounded-full">Audit Trail</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Platform Architecture Section */}
        <section className="py-24">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="text-center mb-16">
              <p className="text-emerald-400 font-semibold text-sm tracking-wider uppercase mb-3">Architecture</p>
              <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">Built for Production</h2>
              <p className="text-lg text-white/70 max-w-3xl mx-auto">Enterprise-grade infrastructure from the ground up. Self-hosted with full control, or managed deployment.</p>
            </div>

            <div className="grid md:grid-cols-2 gap-8 max-w-5xl mx-auto">
              <div className="bg-gradient-to-br from-white/5 to-white/[0.02] p-8 rounded-2xl border border-white/10">
                <h3 className="text-lg font-semibold text-white mb-6 flex items-center gap-3">
                  <span className="w-8 h-8 bg-blue-500/20 rounded-lg flex items-center justify-center">
                    <svg className="w-4 h-4 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 12h14M12 5l7 7-7 7" /></svg>
                  </span>
                  Technical Stack
                </h3>
                <ul className="space-y-3">
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-blue-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">Rails 8 API</strong> with JWT auth, UUIDv7 primary keys, and PostgreSQL</span>
                  </li>
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-blue-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">React + TypeScript</strong> frontend with theme system and Tailwind CSS</span>
                  </li>
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-blue-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">Sidekiq Worker</strong> for async AI execution, pipelines, and background jobs</span>
                  </li>
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-blue-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">pgvector + HNSW</strong> for vector similarity search with cosine distance</span>
                  </li>
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-blue-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">ActionCable WebSockets</strong> for real-time updates across 17+ channels</span>
                  </li>
                </ul>
              </div>

              <div className="bg-gradient-to-br from-white/5 to-white/[0.02] p-8 rounded-2xl border border-white/10">
                <h3 className="text-lg font-semibold text-white mb-6 flex items-center gap-3">
                  <span className="w-8 h-8 bg-emerald-500/20 rounded-lg flex items-center justify-center">
                    <svg className="w-4 h-4 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" /></svg>
                  </span>
                  Enterprise Features
                </h3>
                <ul className="space-y-3">
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-emerald-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">Multi-provider AI</strong> — OpenAI, Anthropic, Ollama, and custom providers</span>
                  </li>
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-emerald-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">RBAC permissions</strong> with granular resource-level access control</span>
                  </li>
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-emerald-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">File management</strong> with 11 storage providers and processing pipelines</span>
                  </li>
                  <li className="flex items-start gap-3 text-white/70">
                    <span className="w-1.5 h-1.5 bg-emerald-400 rounded-full mt-2 shrink-0" />
                    <span><strong className="text-white/90">CI/CD pipelines</strong> with Gitea integration and runner dispatch</span>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </section>

        {/* How It Works */}
        <section className="py-24 bg-white/[0.02]">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="text-center mb-16">
              <p className="text-violet-400 font-semibold text-sm tracking-wider uppercase mb-3">How It Works</p>
              <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">From Zero to AI-Powered in Minutes</h2>
            </div>

            <div className="grid md:grid-cols-4 gap-8 max-w-5xl mx-auto">
              <div className="text-center">
                <div className="w-16 h-16 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-blue-500/20 to-blue-600/10 border border-blue-500/20 flex items-center justify-center">
                  <span className="text-2xl font-bold text-blue-400">1</span>
                </div>
                <h3 className="text-lg font-semibold text-white mb-2">Deploy</h3>
                <p className="text-sm text-white/60">Self-host with systemd services or deploy to your infrastructure. One command setup.</p>
              </div>

              <div className="text-center">
                <div className="w-16 h-16 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-violet-500/20 to-violet-600/10 border border-violet-500/20 flex items-center justify-center">
                  <span className="text-2xl font-bold text-violet-400">2</span>
                </div>
                <h3 className="text-lg font-semibold text-white mb-2">Connect</h3>
                <p className="text-sm text-white/60">Add your AI providers — OpenAI, Anthropic, Ollama. Bring your own keys.</p>
              </div>

              <div className="text-center">
                <div className="w-16 h-16 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-cyan-500/20 to-cyan-600/10 border border-cyan-500/20 flex items-center justify-center">
                  <span className="text-2xl font-bold text-cyan-400">3</span>
                </div>
                <h3 className="text-lg font-semibold text-white mb-2">Build</h3>
                <p className="text-sm text-white/60">Create agents, design workflows, build knowledge bases. Use 100+ MCP tools.</p>
              </div>

              <div className="text-center">
                <div className="w-16 h-16 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-emerald-500/20 to-emerald-600/10 border border-emerald-500/20 flex items-center justify-center">
                  <span className="text-2xl font-bold text-emerald-400">4</span>
                </div>
                <h3 className="text-lg font-semibold text-white mb-2">Scale</h3>
                <p className="text-sm text-white/60">Go autonomous. Agents learn, collaborate, and handle operations 24/7.</p>
              </div>
            </div>
          </div>
        </section>

        {/* Final CTA Section */}
        <section className="py-24">
          <div className="max-w-4xl mx-auto text-center px-4 sm:px-6 lg:px-8">
            <div className="bg-gradient-to-br from-blue-600/20 via-violet-600/10 to-transparent p-12 md:p-16 rounded-3xl border border-white/10">
              <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">Ready to Power Up?</h2>
              <p className="text-lg text-white/70 mb-10 max-w-2xl mx-auto">Join the next generation of AI-native platforms. Full control, full transparency, infinite possibilities.</p>
              <div className="flex flex-col sm:flex-row gap-4 justify-center">
                {registrationEnabled && (
                  <Link to="/plans" className="inline-flex items-center justify-center px-10 py-4 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg shadow-blue-600/30 text-lg">
                    Start Building
                    <svg className="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
                    </svg>
                  </Link>
                )}
                <Link to="/login" className="inline-flex items-center justify-center px-10 py-4 border-2 border-white/20 hover:border-white/40 text-white font-semibold rounded-xl transition-all duration-200 hover:bg-white/5 text-lg">
                  Sign In
                </Link>
              </div>
            </div>
          </div>
        </section>
      </div>
    </PublicPageContainer>
  );
};

export default WelcomePage;
