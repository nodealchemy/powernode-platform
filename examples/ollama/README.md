# Ollama Examples

Simple examples demonstrating Ollama integration with Powernode AI features.

## Prerequisites

1. **Ollama installed and running**:
   ```bash
   # Install Ollama (macOS/Linux)
   curl -fsSL https://ollama.com/install.sh | sh

   # Start Ollama
   ollama serve
   ```

2. **Model available**:
   ```bash
   # Pull the llama3.2 model
   ollama pull llama3.2

   # Verify it's available
   ollama list
   ```

3. **Powernode server running**:
   ```bash
   # From project root
   sudo systemctl start powernode.target
   ```

4. **Database seeded with Ollama provider**:
   ```bash
   cd server
   bundle exec rails runner db/seeds/examples/ollama_examples_seed.rb
   ```

## Examples

### 01-basic-chat.rb

Basic Ollama connectivity test. Verifies your Ollama setup is working correctly.

```bash
cd server
bundle exec rails runner ../examples/ollama/01-basic-chat.rb
```

### 02-simple-ralph-loop.rb

Creates and runs a simple Ralph Loop with 3 tasks using Ollama.

```bash
cd server
bundle exec rails runner ../examples/ollama/02-simple-ralph-loop.rb
```

### 03-simple-workflow.rb

Creates and executes a simple workflow: start -> ai_agent -> end.

```bash
cd server
bundle exec rails runner ../examples/ollama/03-simple-workflow.rb
```

## Configuration

The examples use these defaults:
- **Model**: `llama3.2`
- **Ollama URL**: `http://localhost:11434`

To use a different model, set environment variables:
```bash
export OLLAMA_MODEL=mistral
bundle exec rails runner ../examples/ollama/01-basic-chat.rb
```

## Troubleshooting

### Ollama not responding

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# If not running, start it
ollama serve
```

### Model not found

```bash
# List available models
ollama list

# Pull the required model
ollama pull llama3.2
```

### Provider not configured

Run the seed file to create the Ollama provider:
```bash
cd server
bundle exec rails runner db/seeds/examples/ollama_examples_seed.rb
```
