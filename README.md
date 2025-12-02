# BFHllm

> LLM Integration Framework for BFH Packages

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

BFHllm provides AI-driven insights and text generation for healthcare quality improvement. The package offers:

- **LLM Chat Interface** - Generic chat function with provider abstraction
- **RAG Integration** - Retrieval Augmented Generation with knowledge stores
- **SPC-Specific Suggestions** - Improvement suggestions for Statistical Process Control charts
- **Circuit Breaker** - Resilient API calls with automatic failure handling
- **Caching** - Session-scoped response caching for Shiny applications

Designed for standalone use with [BFHcharts](https://github.com/johanreventlow/BFHcharts) or integration in Shiny applications like [SPCify](https://github.com/johanreventlow/claude_spc).

## Installation

```r
# Install from GitHub
remotes::install_github("johanreventlow/BFHllm")
```

## Quick Start

### Basic Chat

```r
library(BFHllm)

# Set API key
Sys.setenv(GOOGLE_API_KEY = "your_api_key")

# Simple chat
response <- bfhllm_chat(
  prompt = "Explain statistical process control in 2 sentences"
)
```

### SPC Suggestions (with BFHcharts)

```r
library(BFHcharts)
library(BFHllm)

# Generate SPC chart
result <- bfh_qic(data, x = date, y = value, chart = "run")

# Get AI-driven improvement suggestion
suggestion <- bfhllm_spc_suggestion(
  spc_result = result,
  context = list(
    title = "Emergency Department Wait Time",
    unit = "minutes",
    target_value = 60
  )
)

print(suggestion)
```

### RAG-Enhanced Chat

```r
# Load knowledge store
store <- bfhllm_load_knowledge_store()

# Query with RAG context
response <- bfhllm_chat_with_rag(
  prompt = "What does a long run above centerline indicate?",
  knowledge_query = "Anhøj rules run chart interpretation",
  store = store
)
```

## Features

### Circuit Breaker

Automatic protection against API failures:
- Opens after threshold failures (default: 5)
- Auto-resets after timeout (default: 5 minutes)
- Prevents cascading failures

### Caching

Reduce API calls and costs:
- Hash-based cache keys
- TTL enforcement (default: 1 hour)
- Session-scoped for Shiny apps
- Generic interface for standalone use

### Provider Abstraction

Currently supports Google Gemini via [ellmer](https://github.com/hadley/ellmer). Extensible design allows future providers (OpenAI, Anthropic, etc.).

## Configuration

```r
# Configure LLM settings
bfhllm_configure(
  provider = "gemini",
  model = "gemini-2.5-flash-lite",
  timeout_seconds = 10,
  max_response_chars = 350
)

# Check setup
bfhllm_validate_setup()
```

## Environment Variables

- `GOOGLE_API_KEY` or `GEMINI_API_KEY` - API key for Gemini
- `BFHLLM_MODEL` - Default model (optional)
- `BFHLLM_TIMEOUT` - Default timeout in seconds (optional)

## Development

This package was extracted from [SPCify](https://github.com/johanreventlow/claude_spc) to enable standalone use with BFHcharts and future applications.

### Related Packages

- [BFHcharts](https://github.com/johanreventlow/BFHcharts) - SPC visualization engine
- [BFHtheme](https://github.com/johanreventlow/BFHtheme) - Hospital branding and themes
- [ragnar](https://github.com/edubruell/ragnar) - RAG knowledge store framework
- [ellmer](https://github.com/hadley/ellmer) - Gemini API client

## License

MIT © Johan Reventlow

## Status

**In Development** - v0.1.0 targeting initial release

See [implementation tracking](https://github.com/johanreventlow/claude_spc/issues/99) for progress.
