# BFHllm

> LLM Integration Framework for BFH Packages

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![R-CMD-check](https://github.com/johanreventlow/BFHllm/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/johanreventlow/BFHllm/actions/workflows/R-CMD-check.yaml)
[![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)](https://github.com/johanreventlow/BFHllm/blob/main/NEWS.md)

## Overview

BFHllm provides AI-driven insights and text generation for healthcare quality
improvement. It wraps the Google Gemini API (via [ellmer](https://github.com/hadley/ellmer))
behind a stable, resilient interface and adds SPC-specific knowledge and prompting.

Key capabilities:

- **LLM chat interface** — generic chat function with provider abstraction
- **RAG integration** — Retrieval Augmented Generation against a pre-built
  Ragnar knowledge store of SPC methodology
- **SPC suggestions** — Danish improvement suggestions for Statistical Process
  Control charts, single or batched
- **Resilience** — circuit breaker + client-side rate limiter (RPM/RPD) to
  protect against API failures and quota exhaustion
- **Multi-tier caching** — in-memory, file-based, and Shiny session-scoped
- **YAML-driven prompts** — SPC prompt templates externalised to YAML

Designed for standalone use with [BFHcharts](https://github.com/johanreventlow/BFHcharts)
or integration in Shiny applications like [SPCify](https://github.com/johanreventlow/claude_spc).

## Installation

```r
# Install from GitHub
remotes::install_github("johanreventlow/BFHllm")
```

Requires R, a Google Gemini API key, and the `ellmer` / `ragnar` packages
(resolved automatically). `BFHcharts` is a soft dependency used only for the
SPC integration examples.

## Quick Start

Set the API key once (e.g. in `.Renviron`):

```r
Sys.setenv(GOOGLE_API_KEY = "your_api_key")  # or GEMINI_API_KEY
```

### Basic chat

```r
library(BFHllm)

# Quick availability check (API key + provider)
bfhllm_chat_available()

response <- bfhllm_chat(
  prompt = "Explain statistical process control in 2 sentences",
  max_chars = 200
)
```

`bfhllm_chat()` returns `NULL` on any error (timeout, API failure, validation
failure) rather than throwing — check the result and inspect
`bfhllm_circuit_breaker_status()` if needed.

### SPC suggestions (with BFHcharts)

```r
library(BFHcharts)
library(BFHllm)

# Create an SPC chart
bfh_result <- bfh_qic(
  data = spc_data,
  x = date,
  y = waiting_time,
  chart_type = "run",
  y_axis_unit = "time",
  target_value = 30
)

# Build the metadata structure BFHllm expects (English keys)
spc_result <- list(
  metadata = list(
    chart_type = bfh_result$config$chart_type,
    n_points = nrow(bfh_result$qic_data),
    signals_detected = sum(bfh_result$summary$løbelængde_signal,
                           bfh_result$summary$sigma_signal, na.rm = TRUE),
    anhoej_rules = list(
      longest_run = bfh_result$summary$længste_løb,
      n_crossings = bfh_result$summary$antal_kryds,
      n_crossings_min = bfh_result$summary$antal_kryds_min
    )
  ),
  qic_data = bfh_result$qic_data
)

# Domain context for the prompt
context <- list(
  data_definition = "Ventetid til operation (dage)",
  chart_title = "Ventetid ortopædkirurgi 2023-2024",
  y_axis_unit = "time",
  target_value = 30
)

# Generate a Danish, RAG-enhanced improvement suggestion
suggestion <- bfhllm_spc_suggestion(
  spc_result = spc_result,
  context = context,
  use_rag = TRUE
)

print(suggestion)
```

**Full example:** see `inst/examples/bfhcharts-integration.R` for complete
standalone integration including caching and a RAG vs. no-RAG comparison.

### RAG-enhanced chat

```r
# Load the pre-built SPC knowledge store (cached after first load)
store <- bfhllm_load_knowledge_store()

response <- bfhllm_chat_with_rag(
  question = "What does a long run above the centerline indicate?",
  store    = store,
  top_k    = 5,
  method   = "hybrid"   # "hybrid" | "semantic" | "bm25"
)
```

### Batch SPC suggestions

```r
# Analyse many charts in one pass; file-cached to avoid repeat API calls
suggestions <- bfhllm_spc_suggestions_batch(
  contexts   = list_of_spc_contexts,
  batch_size = 25L,
  use_cache  = TRUE
)
```

## Features

### Circuit breaker

Automatic protection against API failures:

- Opens after a threshold of consecutive failures (default: **5**)
- Auto-resets after a timeout (default: **300 s** / 5 minutes)
- Inspect with `bfhllm_circuit_breaker_status()`, force reset with
  `bfhllm_circuit_breaker_reset()`

### Rate limiting

Client-side limiter that respects Gemini free-tier quotas:

- **RPM** (requests per minute): 15 by default
- **RPD** (requests per day): 1500 by default
- Configurable via `bfhllm_configure(rate_limit = list(...))`
- Inspect with `bfhllm_rate_limit_status()`, reset with `bfhllm_rate_limit_reset()`

### Caching

Three interchangeable cache backends reduce API calls and cost:

| Backend | Constructor | Scope | Persists across sessions |
|---|---|---|---|
| In-memory | `bfhllm_cache_create()` | R process | No |
| File-based | `bfhllm_file_cache_create()` | disk (`.bfhllm_cache/`) | Yes |
| Shiny session | `bfhllm_cache_shiny()` | Shiny session | No (cleared on disconnect) |

All backends use hash-based keys and TTL enforcement (default: 3600 s).
Pass a cache object to `bfhllm_chat()` / `bfhllm_spc_suggestion()` via `cache =`.

### Provider abstraction

Currently supports Google Gemini via
[ellmer](https://github.com/hadley/ellmer). The extensible design (see
`list_providers()`) allows future providers (OpenAI, Anthropic, local models).

## Function reference

| Function | Purpose |
|---|---|
| **Chat** | |
| `bfhllm_chat()` | Generic LLM chat with caching, circuit breaker & validation |
| `bfhllm_chat_available()` | Quick check that chat is usable (key + provider) |
| **RAG** | |
| `bfhllm_chat_with_rag()` | RAG-enhanced chat (retrieve → inject → generate) |
| `bfhllm_query_knowledge()` | Query the knowledge store for relevant context |
| `bfhllm_format_rag_context()` | Format RAG results into a prompt context string |
| `bfhllm_load_knowledge_store()` | Load the pre-built Ragnar store (session-cached) |
| `bfhllm_build_knowledge_store()` | Build a store from markdown documents |
| `bfhllm_reset_knowledge_store_cache()` | Clear cached store (testing / reload) |
| **SPC suggestions** | |
| `bfhllm_spc_suggestion()` | Danish improvement suggestion for one chart |
| `bfhllm_spc_suggestions_batch()` | Batched suggestions for many charts (file-cached) |
| `bfhllm_extract_spc_metadata()` | Extract metadata from BFHcharts/qicharts2 results |
| `bfhllm_map_chart_type_danish()` | Translate chart-type codes to Danish names |
| **Prompts** | |
| `bfhllm_build_prompt()` | Concatenate modular prompt components |
| `bfhllm_create_structured_prompt()` | Build a structured question/context/system prompt |
| `bfhllm_interpolate()` | Fill `{{variable}}` placeholders in a template |
| **Caching** | |
| `bfhllm_cache_create()` | In-memory cache |
| `bfhllm_file_cache_create()` | Disk-backed cache (survives sessions) |
| `bfhllm_cache_shiny()` | Shiny session-scoped cache |
| `bfhllm_generate_cache_key()` | Hash arbitrary inputs into a cache key |
| **Configuration** | |
| `bfhllm_configure()` | Set provider, model, timeouts, circuit breaker, rate limit, cache |
| `bfhllm_get_config()` | Current config with env-var fallbacks |
| `bfhllm_validate_setup()` | Check all prerequisites are met |
| **Resilience** | |
| `bfhllm_circuit_breaker_status()` / `_reset()` | Inspect / reset circuit breaker |
| `bfhllm_rate_limit_status()` / `_reset()` | Inspect / reset rate limiter |
| **Providers & validation** | |
| `list_providers()` | List registered LLM providers |
| `validate_response()` / `validate_response_length()` | Sanitise & length-check responses |

## Configuration

```r
bfhllm_configure(
  provider           = "gemini",
  model              = "gemini-3.1-flash-lite",
  timeout_seconds    = 120,
  max_response_chars = 350,
  circuit_breaker    = list(failure_threshold = 5, reset_timeout_seconds = 300),
  rate_limit         = list(enabled = TRUE, rpm = 15, rpd = 1500)
)

# Inspect current configuration
bfhllm_get_config()

# Verify prerequisites (API key, provider, dependencies)
bfhllm_validate_setup()
```

| Setting | Default | Description |
|---|---|---|
| `provider` | `"gemini"` | LLM provider |
| `model` | `"gemini-3.1-flash-lite"` | Model identifier |
| `timeout_seconds` | `120` | API timeout |
| `max_response_chars` | `350` | Maximum response length |
| `circuit_breaker$failure_threshold` | `5` | Failures before the breaker opens |
| `circuit_breaker$reset_timeout_seconds` | `300` | Auto-reset window |
| `cache$ttl_seconds` | `3600` | Cache entry time-to-live |
| `rate_limit$rpm` / `$rpd` | `15` / `1500` | Requests per minute / day |

## Environment variables

| Variable | Purpose |
|---|---|
| `GOOGLE_API_KEY` or `GEMINI_API_KEY` | Gemini API key (either is accepted) |
| `BFHLLM_MODEL` | Override the default model |
| `BFHLLM_TIMEOUT` | Override the default timeout (seconds) |

## Development

This package was extracted from
[SPCify](https://github.com/johanreventlow/claude_spc) to enable standalone use
with BFHcharts and future applications.

```r
devtools::load_all()   # Load for interactive testing
devtools::document()   # Regenerate docs + NAMESPACE
devtools::test()       # Run the test suite
devtools::check()      # Full R CMD check
```

Runnable usage examples live in `inst/examples/` (`basic-chat.R`,
`bfhcharts-integration.R`, `spc-suggestion.R`, `shiny-integration.R`).

### Related packages

- [BFHcharts](https://github.com/johanreventlow/BFHcharts) — SPC visualization engine
- [BFHtheme](https://github.com/johanreventlow/BFHtheme) — hospital branding and themes
- [ragnar](https://github.com/edubruell/ragnar) — RAG knowledge store framework
- [ellmer](https://github.com/hadley/ellmer) — Gemini API client

## License

MIT © Johan Reventlow

## Status

**v0.2.0** — production. See [NEWS.md](NEWS.md) for the changelog.
