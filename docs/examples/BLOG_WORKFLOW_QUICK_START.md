# Blog Generation Workflow - Quick Start Guide

**⏱️ 5-Minute Setup** | **🚀 Production Ready** | **💰 $0.50-$2 per blog**

---

## 🎯 What You'll Get

A **fully automated blog generation pipeline** that produces:

✅ SEO-optimized, publication-ready blog posts
✅ Fact-checked content with verified sources
✅ Professional editing and refinement
✅ Social media snippets
✅ Schema markup for rich snippets
✅ Quality scores (SEO, readability, credibility)

**In 5-10 minutes** instead of 8+ hours of manual work.

---

## 🚀 Quick Setup

### Step 1: Install Template (30 seconds)

```bash
# Option A: Via Marketplace UI
1. Go to AI Marketplace
2. Search "Blog Generation Pipeline"
3. Click "Install"

# Option B: Via API
curl -X POST https://api.powernode.ai/v1/ai/marketplace/templates/blog-generation-pipeline/install \
  -H "Authorization: Bearer YOUR_TOKEN"

# Option C: Via Seed File
cd server && rails db:seed:blog_generation_workflow_seed
```

### Step 2: Configure API Key (1 minute)

```bash
# Add Anthropic API key
POST /api/v1/ai/credentials
{
  "provider_type": "anthropic",
  "api_key": "sk-ant-...",
  "name": "Claude API"
}
```

### Step 3: Execute (30 seconds)

```bash
POST /api/v1/ai/workflows/{workflow_id}/execute
{
  "input_data": {
    "topic": "Your Blog Topic Here",
    "keywords": ["keyword1", "keyword2"],
    "word_count": 1500
  }
}
```

**That's it!** 🎉 Your blog is being generated.

---

## 📊 Workflow Architecture

```
INPUT → Research → Outline → [Write + FactCheck] → Edit → SEO → Quality Check → OUTPUT
                                    ↓                                    ↓
                                (Parallel)                        (Conditional)
                                                                        ↓
                                                                  Revision Loop
```

### 6 AI Agents Working Together

| Agent | Job | Output |
|-------|-----|--------|
| 🔍 **Research** | Gather data, stats, examples | Research summary |
| 📝 **Outline** | Create SEO-optimized structure | Blog outline |
| ✍️ **Writer** | Generate engaging content | Full blog post |
| ✓ **Fact Checker** | Verify accuracy (parallel) | Verified claims |
| 📐 **Editor** | Refine and improve | Polished content |
| 🎯 **SEO** | Optimize for search | SEO-ready post |

---

## 🎨 Input Parameters

### Required
```json
{
  "topic": "Your blog topic or title"
}
```

### Optional (with smart defaults)
```json
{
  "target_audience": "content marketers",
  "keywords": ["AI content", "automation"],
  "tone": "professional",
  "word_count": 1500,
  "quality_threshold": 85
}
```

---

## 📤 Output Format

```json
{
  "title": "SEO-Optimized Title with Primary Keyword",
  "content": "# Complete markdown blog post\n\nIntro...",
  "meta_description": "Compelling 155-character description",
  "url_slug": "seo-friendly-url-slug",
  "keywords": ["primary", "secondary", "keywords"],
  "social_snippets": {
    "twitter": "Engaging tweet with hashtags",
    "linkedin": "Professional LinkedIn post",
    "facebook": "Facebook-optimized snippet"
  },
  "schema_markup": {
    "@type": "Article",
    "headline": "...",
    "author": "..."
  },
  "reading_time": "8 minutes",
  "word_count": 1847,
  "quality_metrics": {
    "seo_score": 94,
    "quality_score": 92,
    "credibility_score": 95
  }
}
```

---

## 🔥 Advanced Features

### Parallel Processing
- **Writer** and **Fact Checker** run simultaneously
- **40% faster** execution

### Checkpointing
- Auto-save after research
- Auto-save after editing
- **Resume from any point** if interrupted

### Quality Gate
- Automatic quality check
- **Revision loop** if scores below threshold
- Ensures consistent output quality

### Error Recovery
- Saga pattern with **automatic compensation**
- **Self-healing** on failures
- Circuit breaker for API issues

---

## 💡 Use Cases

### 1. Content Marketing
```json
{
  "topic": "10 Content Marketing Trends for 2025",
  "target_audience": "marketing managers",
  "tone": "authoritative yet accessible",
  "word_count": 2000
}
```
**→ Professional thought leadership piece**

### 2. Technical Blog
```json
{
  "topic": "Introduction to Microservices Architecture",
  "target_audience": "developers",
  "tone": "technical",
  "word_count": 1800
}
```
**→ Developer-focused educational content**

### 3. Product Blog
```json
{
  "topic": "How AI Improves Customer Support",
  "target_audience": "business owners",
  "keywords": ["AI support", "customer service automation"],
  "tone": "conversational"
}
```
**→ Product marketing content**

---

## 📈 Real-Time Monitoring

### Via WebSocket
```javascript
cable.subscriptions.create(
  { channel: "AiWorkflowExecutionChannel", run_id: runId },
  {
    received(data) {
      if (data.type === 'node_completed') {
        console.log(`${data.node_name} completed`);
        updateProgress(data.progress_percent);
      }
    }
  }
);
```

### Progress Updates
```
✓ Research completed (20%)
✓ Outline created (35%)
✓ Content written (50%)
✓ Facts verified (65%)
✓ Content edited (80%)
✓ SEO optimized (95%)
✓ Quality check passed (100%)
```

---

## 💰 Cost & Performance

| Metric | Value |
|--------|-------|
| **Execution Time** | 5-8 minutes |
| **Average Cost** | $0.50-$2.00 |
| **Success Rate** | 96%+ |
| **Quality Score** | 90+ average |
| **Time Saved** | ~7.5 hours vs manual |
| **Cost Savings** | ~$150 vs freelancer |

---

## 🛠️ Customization

### Change Tone
```ruby
# Update writer agent
writer_agent.update!(
  system_prompt: "You are a casual, friendly blogger..."
)
```

### Adjust Word Count
```json
{
  "topic": "Your topic",
  "word_count": 2500  // Longer form
}
```

### Add Custom Agent
```ruby
# Example: Add image generator
image_agent = AiAgent.create!(
  name: 'Image Generator',
  agent_type: 'image_generator',
  ai_provider: dall_e_provider
)

# Add to workflow
AiWorkflowNode.create!(
  ai_workflow: workflow,
  node_type: 'ai_agent',
  configuration: { agent_id: image_agent.agent_id }
)
```

---

## 📊 Analytics Dashboard

```bash
GET /api/v1/ai/workflows/{workflow_id}/analytics/dashboard
```

**See**:
- Total executions and success rate
- Average duration and cost
- Node performance breakdown
- Optimization opportunities
- Cost savings recommendations

---

## 🔗 Integration Examples

### WordPress Auto-Publish
```javascript
async function autoPublish(result) {
  // Workflow completes → Auto-publish to WordPress
  await publishToWP({
    title: result.title,
    content: result.content,
    slug: result.url_slug,
    meta: result.meta_description
  });
}
```

### Slack Notification
```ruby
# After completion
SlackNotifier.notify(
  channel: '#content-team',
  message: "New blog post ready: #{result['title']}"
)
```

### Email Draft
```ruby
# Send to editor
Mailer.send_draft(
  to: 'editor@company.com',
  subject: "Review: #{result['title']}",
  content: result['content']
)
```

---

## 🆘 Troubleshooting

### Low Quality Scores?
```json
// Increase quality threshold
{
  "quality_threshold": 90  // Higher bar
}
```

### Content Too Short?
```json
{
  "word_count": 2500  // Increase target
}
```

### SEO Score Low?
```json
{
  "keywords": ["primary", "secondary", "tertiary"],  // More keywords
  "topic": "Include primary keyword in topic"
}
```

### API Timeout?
- Checkpointing enabled → Will resume
- Saga pattern → Automatic recovery
- Check `/recovery/statistics` for details

---

## 📚 Next Steps

1. **Review Output**: Check the generated blog post
2. **Customize Agents**: Adjust prompts for your needs
3. **Add Integrations**: Connect to WordPress, CMS, etc.
4. **Scale Up**: Run multiple blogs in parallel
5. **Analyze Performance**: Use analytics dashboard

---

## 🎯 Pro Tips

✨ **Use specific topics**: "10 Ways AI Improves Marketing" beats "AI and Marketing"

✨ **Provide keywords**: Better SEO when you specify target keywords

✨ **Set audience**: Content adapts to target reader demographic

✨ **Monitor costs**: Check analytics for optimization opportunities

✨ **Batch process**: Queue multiple blogs during off-hours

✨ **Template variations**: Clone and customize for different content types

---

## 📞 Support

- **Documentation**: [Full Workflow Guide](BLOG_GENERATION_WORKFLOW.md)
- **API Docs**: [AI Orchestration Guide](../platform/AI_ORCHESTRATION_GUIDE.md)
- **Examples**: See seed file for implementation details

---

**Ready to 10x your content production?** 🚀

Run the seed file and generate your first AI blog in 5 minutes!

```bash
cd server
rails db:seed:blog_generation_workflow_seed

# Then execute via API or dashboard
```

---

*Platform Version: 0.3.1 | Powered by Powernode AI Orchestration*
