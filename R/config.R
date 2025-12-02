# config.R
# Configuration Management for BFHllm

# PACKAGE ENVIRONMENT ===========================================================

# Package-level environment for storing configuration
.bfhllm_env <- new.env(parent = emptyenv())

# Default configuration
.bfhllm_env$config <- list(
  provider = "gemini",
  model = "gemini-2.5-flash-lite",
  timeout_seconds = 10,
  max_response_chars = 350,
  circuit_breaker = list(
    enabled = TRUE,
    failure_threshold = 5,
    reset_timeout_seconds = 300
  ),
  cache = list(
    enabled = TRUE,
    ttl_seconds = 3600
  )
)

# CONFIGURATION FUNCTIONS =======================================================

#' Configure BFHllm Settings
#'
#' Set runtime configuration for LLM provider, model, and behavior.
#' Configuration is stored in package environment and persists for the session.
#'
#' @param provider Character string, LLM provider name (default: "gemini")
#' @param model Character string, model identifier (default: "gemini-2.5-flash-lite")
#' @param timeout_seconds Numeric, API timeout in seconds (default: 10)
#' @param max_response_chars Integer, maximum response length (default: 350)
#' @param circuit_breaker List with circuit breaker settings (optional)
#' @param cache List with cache settings (optional)
#'
#' @return Invisibly returns the updated configuration list
#'
#' @examples
#' \dontrun{
#' # Basic configuration
#' bfhllm_configure(
#'   model = "gemini-2.0-flash-exp",
#'   timeout_seconds = 15
#' )
#'
#' # Advanced configuration
#' bfhllm_configure(
#'   circuit_breaker = list(
#'     enabled = TRUE,
#'     failure_threshold = 3,
#'     reset_timeout_seconds = 180
#'   ),
#'   cache = list(
#'     enabled = TRUE,
#'     ttl_seconds = 7200
#'   )
#' )
#' }
#'
#' @export
bfhllm_configure <- function(provider = NULL,
                              model = NULL,
                              timeout_seconds = NULL,
                              max_response_chars = NULL,
                              circuit_breaker = NULL,
                              cache = NULL) {
  # Get current config
  config <- .bfhllm_env$config

  # Update top-level settings
  if (!is.null(provider)) config$provider <- provider
  if (!is.null(model)) config$model <- model
  if (!is.null(timeout_seconds)) config$timeout_seconds <- timeout_seconds
  if (!is.null(max_response_chars)) config$max_response_chars <- max_response_chars

  # Update circuit breaker settings
  if (!is.null(circuit_breaker)) {
    config$circuit_breaker <- modifyList(config$circuit_breaker, circuit_breaker)
  }

  # Update cache settings
  if (!is.null(cache)) {
    config$cache <- modifyList(config$cache, cache)
  }

  # Store updated config
  .bfhllm_env$config <- config

  invisible(config)
}

#' Get BFHllm Configuration
#'
#' Retrieve current configuration with environment variable fallbacks.
#'
#' @return List with current configuration settings
#'
#' @examples
#' \dontrun{
#' config <- bfhllm_get_config()
#' print(config$model)
#' }
#'
#' @export
bfhllm_get_config <- function() {
  config <- .bfhllm_env$config

  # Apply environment variable overrides
  env_model <- Sys.getenv("BFHLLM_MODEL", unset = "")
  if (env_model != "") {
    config$model <- env_model
  }

  env_timeout <- Sys.getenv("BFHLLM_TIMEOUT", unset = "")
  if (env_timeout != "") {
    config$timeout_seconds <- as.numeric(env_timeout)
  }

  return(config)
}

#' Validate BFHllm Setup
#'
#' Checks if all prerequisites for using BFHllm are met:
#' - Required packages installed (ellmer)
#' - API key configured
#' - Configuration valid
#'
#' @return Logical, TRUE if setup is valid, FALSE otherwise (with warnings)
#'
#' @examples
#' \dontrun{
#' if (bfhllm_validate_setup()) {
#'   # Proceed with LLM operations
#' } else {
#'   # Handle setup issues
#' }
#' }
#'
#' @export
bfhllm_validate_setup <- function() {
  valid <- TRUE

  # Check 1: ellmer package installed
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    warning("ellmer package not installed. Install with: install.packages('ellmer')",
      call. = FALSE
    )
    valid <- FALSE
  }

  # Check 2: API key present
  api_key <- Sys.getenv("GOOGLE_API_KEY", unset = "")
  gemini_key <- Sys.getenv("GEMINI_API_KEY", unset = "")

  if (api_key == "" && gemini_key == "") {
    warning("No API key found. Set GOOGLE_API_KEY or GEMINI_API_KEY environment variable.",
      call. = FALSE
    )
    valid <- FALSE
  }

  if (api_key == "your_api_key_here" || gemini_key == "your_api_key_here") {
    warning("API key appears to be placeholder. Set valid API key.",
      call. = FALSE
    )
    valid <- FALSE
  }

  # Check 3: Configuration valid
  config <- bfhllm_get_config()

  if (!is.numeric(config$timeout_seconds) || config$timeout_seconds <= 0) {
    warning("Invalid timeout_seconds in configuration.",
      call. = FALSE
    )
    valid <- FALSE
  }

  if (!is.numeric(config$max_response_chars) || config$max_response_chars <= 0) {
    warning("Invalid max_response_chars in configuration.",
      call. = FALSE
    )
    valid <- FALSE
  }

  if (valid) {
    message("BFHllm setup validated successfully")
  }

  return(valid)
}

#' Reset Configuration to Defaults
#'
#' Resets configuration to package defaults. Useful for testing.
#'
#' @return Invisibly returns the default configuration
#'
#' @keywords internal
bfhllm_reset_config <- function() {
  .bfhllm_env$config <- list(
    provider = "gemini",
    model = "gemini-2.5-flash-lite",
    timeout_seconds = 10,
    max_response_chars = 350,
    circuit_breaker = list(
      enabled = TRUE,
      failure_threshold = 5,
      reset_timeout_seconds = 300
    ),
    cache = list(
      enabled = TRUE,
      ttl_seconds = 3600
    )
  )

  invisible(.bfhllm_env$config)
}
