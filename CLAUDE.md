<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Claude Instructions – BFHllm

- Mac: `@~/.claude/rules/CLAUDE_BOOTSTRAP_WORKFLOW.md`
- Windows: `@C:/Users/jrev0004/.claude/rules/CLAUDE_BOOTSTRAP_WORKFLOW.md`

---

## 1) Project Overview

- **Project Type:** R Package
- **Purpose:** LLM Integration Framework for BFH Packages. Provides AI-driven insights and text generation for healthcare quality improvement with LLM chat interface, RAG integration, and SPC-specific improvement suggestions.
- **Status:** Production (v0.1.1)

**Technology Stack:**
- ellmer (Google Gemini API client)
- ragnar (RAG knowledge stores)
- digest (response caching)
- Shiny integration support

---

## 2) Project-Specific Architecture

### Package Structure

```
BFHllm/
├── R/
│   ├── BFHllm-package.R      # Package documentation
│   ├── chat.R                # Main chat interface
│   ├── prompts.R             # Prompt template utilities
│   ├── config.R              # Configuration management
│   ├── provider-interface.R  # Provider abstraction
│   ├── provider-gemini.R     # Gemini implementation
│   ├── response-validation.R # Response sanitization
│   ├── cache.R               # Generic caching
│   ├── cache-shiny.R         # Shiny session cache
│   ├── knowledge-store.R     # RAG store management
│   ├── rag.R                 # RAG query/integration
│   └── spc-suggestions.R     # SPC-specific AI suggestions
├── inst/
│   ├── spc_knowledge/        # SPC methodology docs
│   ├── ragnar_store/         # Pre-built vector store
│   └── examples/             # Usage examples
├── data-raw/
│   └── build_ragnar_store.R  # Store rebuild script
├── tests/testthat/           # Unit tests (142 passing)
└── man/                      # Auto-generated documentation
```

### Core Components

**Chat Interface:**
- `bfhllm_chat()` - Main LLM chat function
- `bfhllm_configure()` - Runtime configuration
- `bfhllm_validate_setup()` - API validation

**RAG Integration:**
- `bfhllm_load_knowledge_store()` - Load Ragnar store
- `bfhllm_query_knowledge()` - Query for context
- `bfhllm_chat_with_rag()` - RAG-enhanced chat

**SPC Suggestions:**
- `bfhllm_spc_suggestion()` - Generate Danish SPC improvement suggestions
- `bfhllm_extract_spc_metadata()` - Extract metadata from qicharts2/BFHcharts results
- `bfhllm_map_chart_type_danish()` - Translate chart types to Danish

**Caching:**
- `bfhllm_cache_create()` - Generic in-memory cache
- `bfhllm_cache_shiny()` - Shiny session-scoped cache

**Circuit Breaker:**
- `bfhllm_circuit_breaker_status()` - Check state
- `bfhllm_circuit_breaker_reset()` - Manual reset

### Provider Abstraction Pattern

**Design:**
```r
# Provider interface (extensible)
provider_interface <- list(
  validate_setup = function() { ... },
  call_api = function(prompt, model, timeout) { ... },
  extract_text = function(response) { ... }
)

# Current implementation: Gemini via ellmer
gemini_validate_setup()
gemini_call_api(prompt, model, timeout)
gemini_extract_text(response)
```

**Future providers:**
- OpenAI (GPT-4)
- Anthropic (Claude)
- Azure OpenAI
- Local models (Ollama)

### Circuit Breaker Pattern

**Purpose:** Prevent cascading failures from LLM API issues

```r
# Package-level state
.gemini_circuit_breaker <- new.env(parent = emptyenv())
.gemini_circuit_breaker$failures <- 0L
.gemini_circuit_breaker$last_failure_time <- NULL
.gemini_circuit_breaker$is_open <- FALSE

# Auto-reset after timeout (default: 60 seconds)
# Threshold: 3 consecutive failures (configurable)
```

### Caching Strategy

**Generic Cache (package-level):**
```r
.cache <- new.env(parent = emptyenv())
cache_key <- digest::digest(list(prompt, model, config))
```

**Shiny Cache (session-scoped):**
```r
cache <- session$userData$.bfhllm_cache
# Automatic cleanup on session end
```

---

## 3) Critical Project Constraints

### Do NOT Modify

- **Exported function signatures** - Breaking changes require major version bump
- **NAMESPACE** - Auto-generated via `devtools::document()`, NEVER manual edit
- **inst/ragnar_store/** - Pre-built vector store (5.3MB), rebuild via data-raw script
- **API key environment variable names** - `GOOGLE_API_KEY` or `GEMINI_API_KEY` (backwards compatibility)

### Breaking Changes Policy

**Requires:**
- Major version bump (semver)
- Deprecation warnings in minor version first
- Migration guide
- Notification to downstream packages (SPCify)

### Security Considerations

**API Key Handling:**
```r
# ✅ Correct: Read from environment
api_key <- Sys.getenv("GOOGLE_API_KEY")

# ❌ Wrong: Never log or print API keys
message("Using API key: ", api_key)  # NEVER DO THIS
```

**Response Sanitization:**
```r
# Always validate LLM responses
bfhllm_sanitize_response <- function(text, max_chars = 2000) {
  if (!is.character(text) || length(text) != 1) {
    stop("Invalid response format", call. = FALSE)
  }

  # Truncate to max length
  if (nchar(text) > max_chars) {
    text <- substr(text, 1, max_chars)
  }

  # Remove control characters
  text <- gsub("[\x00-\x1F\x7F]", "", text)

  return(text)
}
```

**Input Validation:**
```r
# Validate all user inputs
validate_prompt <- function(prompt) {
  if (!is.character(prompt) || length(prompt) != 1 || nchar(prompt) == 0) {
    stop("prompt must be a non-empty character string", call. = FALSE)
  }

  if (nchar(prompt) > 10000) {
    stop("prompt exceeds maximum length (10000 characters)", call. = FALSE)
  }
}
```

---

## 4) Cross-Repository Coordination

### Integration with Upstream Packages

**BFHllm depends on:**
- **ellmer** (>= 0.4.0) - Gemini API client
- **ragnar** (>= 0.1.0) - RAG knowledge stores
- **digest** - Response caching

### Integration with Downstream Packages

**BFHllm provides LLM infrastructure for:**
- **SPCify** - Shiny application for SPC analysis (AI improvement suggestions)
- Future: **BFHcharts** integration (chart interpretation)

**Responsibility Boundaries:**

**BFHllm ansvar:**
- LLM API calls and error handling
- Response caching and validation
- RAG query and knowledge store management
- Provider abstraction
- Circuit breaker resilience
- SPC-specific prompt templates

**Downstream package ansvar:**
- UI/UX for AI features
- Domain-specific context assembly
- Result presentation
- User preference management
- Application-specific caching strategies

### Communication Channel

**For feature requests fra downstream:**
1. Opret issue i BFHllm repo
2. Label: `enhancement`, `from-spcify`
3. Reference downstream use case
4. Diskutér API design før implementation

---

## 5) Project-Specific Configuration

### API Design Principles

**Consistent Interface:**

```r
# Chat
bfhllm_chat(prompt, model = NULL, timeout_seconds = NULL, max_response_chars = NULL, cache = NULL)

# RAG
bfhllm_chat_with_rag(prompt, knowledge_store, n_results = 3, model = NULL, ...)

# SPC Suggestions
bfhllm_spc_suggestion(spc_result, context = list(), knowledge_store = NULL, ...)

# Configuration
bfhllm_configure(provider = "gemini", model = "gemini-2.0-flash-lite", timeout_seconds = 10, ...)
```

**Graceful Defaults:**
- Auto-detect API key from environment (`GOOGLE_API_KEY` or `GEMINI_API_KEY`)
- Fallback to sensible model defaults (`gemini-2.0-flash-lite`)
- Circuit breaker auto-reset (60 seconds)
- Reasonable timeout (10 seconds default)
- Session-scoped caching in Shiny context

### Development Commands

```r
# Development workflow
devtools::load_all()           # Load package for testing
devtools::document()           # Generate docs + NAMESPACE
devtools::test()               # Run all tests (142 tests)
devtools::check()              # Full package check

# Code quality
styler::style_pkg()            # Format code
lintr::lint_package()          # Lint code

# Testing
testthat::test_file("tests/testthat/test-chat.R")
covr::package_coverage()       # Track coverage

# RAG store rebuild
source("data-raw/build_ragnar_store.R")  # Requires GOOGLE_API_KEY
```

---

## 6) Domain-Specific Guidance

### LLM Integration Best Practices

**Prompt Engineering:**
```r
# ✅ Correct: Structured prompts with clear instructions
prompt <- bfhllm_build_prompt(
  system = "Du er en ekspert i statistisk proceskontrol.",
  context = rag_context,
  user_query = "Hvad betyder dette run chart?",
  constraints = "Svar på dansk, max 200 ord."
)

# ❌ Wrong: Vague or unstructured prompts
prompt <- "Fortæl om run chart"
```

**Error Handling Pattern:**
```r
# Always wrap LLM calls in tryCatch
result <- tryCatch(
  bfhllm_chat(prompt),
  error = function(e) {
    log_error("LLM call failed", error = e$message)
    return("Beklager, AI-tjenesten er midlertidigt utilgængelig.")
  }
)
```

**Caching Strategy:**
```r
# Standalone R scripts: use package-level cache
cache <- bfhllm_cache_create()
response <- bfhllm_chat(prompt, cache = cache)

# Shiny apps: use session-scoped cache
cache <- bfhllm_cache_shiny(session)
response <- bfhllm_chat(prompt, cache = cache)
```

### RAG Integration Pattern

**Knowledge Store Setup:**
```r
# Load pre-built store (recommended)
store <- bfhllm_load_knowledge_store("spc")

# Query for context
context <- bfhllm_query_knowledge(
  store = store,
  query = "run chart interpretation rules",
  n_results = 3
)

# RAG-enhanced chat
response <- bfhllm_chat_with_rag(
  prompt = "Forklar run chart regler",
  knowledge_store = store,
  n_results = 3
)
```

### SPC Suggestions Pattern

**Extract metadata from chart results:**
```r
# Works with qicharts2::qic() and BFHcharts::bfh_qic()
metadata <- bfhllm_extract_spc_metadata(
  spc_result = chart_result,
  context = list(
    title = "Ventetid i ambulatorium",
    unit = "minutter",
    target = 30,
    clinical_context = "Ambulatorium X"
  )
)

# Generate Danish AI suggestion
suggestion <- bfhllm_spc_suggestion(
  spc_result = chart_result,
  context = metadata$context,
  knowledge_store = store
)
```

### Testing Strategy

**Coverage Goals:**
- **≥90% samlet coverage**
- **100% på exported functions**
- **Edge cases** - NULL inputs, empty data, invalid types, API failures
- **Integration tests** - Full workflow RAG → prompt → LLM → validation

**Test Patterns:**

```r
# Unit test
test_that("bfhllm_chat validates prompt input", {
  expect_error(bfhllm_chat(NULL))
  expect_error(bfhllm_chat(""))
  expect_error(bfhllm_chat(123))
  expect_error(bfhllm_chat(c("a", "b")))
})

# Mock LLM API (avoid real calls in tests)
test_that("bfhllm_chat handles API failures gracefully", {
  mockery::stub(bfhllm_chat, "gemini_call_api", function(...) {
    stop("API unavailable")
  })

  expect_error(bfhllm_chat("test prompt"), "API unavailable")
})

# Integration test with caching
test_that("cache returns identical results for same prompt", {
  skip_if_not(nzchar(Sys.getenv("GOOGLE_API_KEY")))

  cache <- bfhllm_cache_create()

  result1 <- bfhllm_chat("test prompt", cache = cache)
  result2 <- bfhllm_chat("test prompt", cache = cache)

  expect_identical(result1, result2)
})
```

### Known Issues & Technical Debt

**Current Focus (v0.1.1):**
- ✅ Fixed ellmer 0.4.0 API deprecation
- ✅ Fixed roxygen2 @docType deprecation
- ✅ Updated dependency versions

**Future Work:**
1. **Provider support:**
   - Add OpenAI provider
   - Add Anthropic (Claude) provider
   - Add local model support (Ollama)

2. **RAG enhancements:**
   - Hybrid search (BM25 + semantic)
   - Query expansion
   - Re-ranking strategies

3. **Testing:**
   - Add integration tests with real LLM APIs (conditional)
   - Add performance benchmarks
   - Add visual regression tests for SPC suggestions output

4. **Documentation:**
   - pkgdown website
   - Detailed vignettes for each feature
   - Video tutorials

### Danish Language

- **Function names:** Engelsk
- **Function documentation:** Engelsk
- **Internal comments:** Dansk
- **Error messages:** Engelsk (standard for R packages)
- **LLM responses:** Dansk (for SPC suggestions)

**Exports:**
- `bfhllm_chat()` ikke `bfhllm_chat_dansk()`
- Danish responses handled via prompt engineering

---

## 📚 Global Standards Reference

**Dette projekt følger:**
- **R Development:** `~/.claude/rules/R_STANDARDS.md`
- **Architecture Patterns:** `~/.claude/rules/ARCHITECTURE_PATTERNS.md`
- **Git Workflow:** `~/.claude/rules/GIT_WORKFLOW.md`
- **Development Philosophy:** `~/.claude/rules/DEVELOPMENT_PHILOSOPHY.md`
- **Troubleshooting:** `~/.claude/rules/TROUBLESHOOTING_GUIDE.md`

**Globale agents:** tidyverse-code-reviewer, performance-optimizer, security-reviewer, test-coverage-analyzer, refactoring-advisor, legacy-code-detector, r-package-code-reviewer

**Globale commands:** /bootstrap, /debugger

---

**Version:** 0.1.1 (2025-12-02)
