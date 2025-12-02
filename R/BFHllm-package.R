#' BFHllm: LLM Integration Framework for BFH Packages
#'
#' @description
#' BFHllm provides AI-driven insights and text generation for healthcare quality
#' improvement. The package offers LLM chat interface, RAG (Retrieval Augmented
#' Generation) integration with knowledge stores, and SPC-specific improvement
#' suggestions.
#'
#' @section Core Functions:
#'
#' **Chat Interface:**
#' * [bfhllm_chat()] - Generic LLM chat with provider abstraction
#' * [bfhllm_configure()] - Configure LLM settings
#' * [bfhllm_validate_setup()] - Validate API setup
#'
#' **RAG Integration:**
#' * [bfhllm_load_knowledge_store()] - Load Ragnar knowledge store
#' * [bfhllm_query_knowledge()] - Query knowledge for context
#' * [bfhllm_chat_with_rag()] - RAG-enhanced chat
#'
#' **SPC Suggestions:**
#' * [bfhllm_spc_suggestion()] - Generate SPC improvement suggestions
#' * [bfhllm_extract_spc_metadata()] - Extract metadata from SPC results
#'
#' **Caching:**
#' * [bfhllm_cache_create()] - Create generic cache
#' * [bfhllm_cache_shiny()] - Create Shiny session cache
#'
#' **Circuit Breaker:**
#' * [bfhllm_circuit_breaker_status()] - Check circuit breaker state
#' * [bfhllm_circuit_breaker_reset()] - Reset circuit breaker
#'
#' @section Configuration:
#'
#' **Environment Variables:**
#' * `GOOGLE_API_KEY` or `GEMINI_API_KEY` - API key for Gemini
#' * `BFHLLM_MODEL` - Default model (optional)
#' * `BFHLLM_TIMEOUT` - Default timeout in seconds (optional)
#'
#' **Runtime Configuration:**
#' ```r
#' bfhllm_configure(
#'   provider = "gemini",
#'   model = "gemini-2.5-flash-lite",
#'   timeout_seconds = 10,
#'   max_response_chars = 350
#' )
#' ```
#'
#' @section Getting Started:
#'
#' **Basic Chat:**
#' ```r
#' library(BFHllm)
#'
#' # Set API key
#' Sys.setenv(GOOGLE_API_KEY = "your_api_key")
#'
#' # Simple chat
#' response <- bfhllm_chat(
#'   prompt = "Explain statistical process control in 2 sentences"
#' )
#' ```
#'
#' **SPC Suggestions:**
#' ```r
#' library(BFHcharts)
#' library(BFHllm)
#'
#' # Generate SPC chart
#' result <- bfh_qic(data, x = date, y = value, chart = "run")
#'
#' # Get AI suggestion
#' suggestion <- bfhllm_spc_suggestion(
#'   spc_result = result,
#'   context = list(title = "Wait Time", unit = "minutes")
#' )
#' ```
#'
#' @section Related Packages:
#' * [ellmer](https://github.com/hadley/ellmer) - Gemini API client
#' * [ragnar](https://github.com/edubruell/ragnar) - RAG knowledge store
#' * [BFHcharts](https://github.com/johanreventlow/BFHcharts) - SPC visualization
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
