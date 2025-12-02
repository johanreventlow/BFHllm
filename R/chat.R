# chat.R
# Main LLM Chat Function

#' LLM Chat Interface
#'
#' Generic chat function with provider abstraction, caching, circuit breaker
#' protection, and response validation.
#'
#' @param prompt Character string, prompt to send to LLM
#' @param model Character string, model identifier (default: from config)
#' @param provider Character string, provider name (default: "gemini")
#' @param timeout Numeric, timeout in seconds (default: from config)
#' @param max_chars Integer, maximum response length (default: from config)
#' @param cache Cache object from `bfhllm_cache_create()` or `bfhllm_cache_shiny()`
#'   (optional). If provided, responses are cached to reduce API calls.
#' @param validate Logical, whether to validate and sanitize response (default: TRUE)
#'
#' @return Character string with LLM response, or NULL on error
#'
#' @details
#' **Features:**
#' - Provider abstraction (currently Gemini, extensible to others)
#' - Circuit breaker protection (opens after threshold failures)
#' - Optional caching (reduces API calls and costs)
#' - Response validation (HTML removal, markdown balancing)
#' - Timeout handling
#'
#' **Configuration:**
#' Default values are read from configuration (set via `bfhllm_configure()` or
#' environment variables). Function arguments override configuration.
#'
#' **Caching:**
#' If cache is provided, responses are cached based on prompt + model hash.
#' Cache hits avoid API calls entirely. Use `bfhllm_cache_create()` for
#' standalone or `bfhllm_cache_shiny()` for Shiny apps.
#'
#' **Error Handling:**
#' Returns NULL on errors (timeout, API failure, validation failure).
#' Check circuit breaker status with `bfhllm_circuit_breaker_status()`.
#'
#' @examples
#' \dontrun{
#' # Basic usage
#' Sys.setenv(GOOGLE_API_KEY = "your_api_key")
#' response <- bfhllm_chat("Explain SPC in 2 sentences")
#' print(response)
#'
#' # With caching
#' cache <- bfhllm_cache_create()
#' response1 <- bfhllm_chat("What is variation?", cache = cache)
#' response2 <- bfhllm_chat("What is variation?", cache = cache) # Cache hit
#'
#' # Custom configuration
#' response <- bfhllm_chat(
#'   "Analyze this data pattern",
#'   model = "gemini-2.0-flash-exp",
#'   timeout = 15,
#'   max_chars = 500
#' )
#'
#' # In Shiny app
#' server <- function(input, output, session) {
#'   cache <- bfhllm_cache_shiny(session)
#'
#'   observeEvent(input$generate_btn, {
#'     response <- bfhllm_chat(
#'       input$prompt,
#'       cache = cache
#'     )
#'     output$result <- renderText(response)
#'   })
#' }
#' }
#'
#' @export
bfhllm_chat <- function(prompt,
                        model = NULL,
                        provider = "gemini",
                        timeout = NULL,
                        max_chars = NULL,
                        cache = NULL,
                        validate = TRUE) {
  # Validate inputs
  if (missing(prompt) || is.null(prompt) || !is.character(prompt) || nchar(prompt) == 0) {
    warning("prompt must be a non-empty character string", call. = FALSE)
    return(NULL)
  }

  # Get configuration
  config <- bfhllm_get_config()

  # Apply defaults from config
  if (is.null(model)) model <- config$model
  if (is.null(timeout)) timeout <- config$timeout_seconds
  if (is.null(max_chars)) max_chars <- config$max_response_chars

  # Check cache first
  if (!is.null(cache)) {
    cache_key <- bfhllm_generate_cache_key(
      prompt = prompt,
      model = model,
      provider = provider
    )

    cached_response <- cache$get(cache_key)
    if (!is.null(cached_response)) {
      return(cached_response)
    }
  }

  # Validate provider setup
  if (!validate_provider_setup(provider)) {
    warning(sprintf("Provider '%s' not properly configured", provider), call. = FALSE)
    return(NULL)
  }

  # Call provider API
  raw_response <- tryCatch(
    {
      call_provider_api(
        provider_name = provider,
        prompt = prompt,
        model = model,
        timeout = timeout
      )
    },
    error = function(e) {
      warning(sprintf("API call failed: %s", e$message), call. = FALSE)
      return(NULL)
    }
  )

  if (is.null(raw_response)) {
    return(NULL)
  }

  # Extract text from provider response
  text <- tryCatch(
    {
      extract_provider_text(provider, raw_response)
    },
    error = function(e) {
      warning(sprintf("Failed to extract text: %s", e$message), call. = FALSE)
      return(NULL)
    }
  )

  if (is.null(text)) {
    return(NULL)
  }

  # Validate and sanitize response
  if (validate) {
    text <- validate_response(text, max_chars = max_chars)

    if (is.null(text)) {
      warning("Response validation failed", call. = FALSE)
      return(NULL)
    }
  }

  # Cache response if cache provided
  if (!is.null(cache)) {
    cache$set(cache_key, text)
  }

  return(text)
}

#' Check if LLM Chat is Available
#'
#' Quick check if chat functionality is available (API key configured,
#' packages installed, etc.)
#'
#' @return Logical, TRUE if chat is available
#'
#' @examples
#' \dontrun{
#' if (bfhllm_chat_available()) {
#'   response <- bfhllm_chat("Hello")
#' } else {
#'   message("Chat not available - check API key")
#' }
#' }
#'
#' @export
bfhllm_chat_available <- function() {
  bfhllm_validate_setup()
}
