# provider-gemini.R
# Google Gemini Provider Implementation via ellmer

# CIRCUIT BREAKER STATE =========================================================

# Package-level environment for circuit breaker state
.gemini_circuit_breaker <- new.env(parent = emptyenv())
.gemini_circuit_breaker$failures <- 0L
.gemini_circuit_breaker$last_failure_time <- NULL
.gemini_circuit_breaker$is_open <- FALSE

# GEMINI VALIDATION =============================================================

#' Validate Gemini API Setup
#'
#' Checks if all prerequisites for Gemini API are met:
#' - ellmer package installed
#' - API key configured
#'
#' @return Logical, TRUE if valid
#'
#' @keywords internal
gemini_validate_setup <- function() {
  # Check 1: ellmer package
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    warning("ellmer package not installed", call. = FALSE)
    return(FALSE)
  }

  # Check 2: API key
  api_key <- Sys.getenv("GOOGLE_API_KEY", unset = "")
  gemini_key <- Sys.getenv("GEMINI_API_KEY", unset = "")

  if (api_key == "" && gemini_key == "") {
    warning("No API key found (GOOGLE_API_KEY or GEMINI_API_KEY)", call. = FALSE)
    return(FALSE)
  }

  if (api_key == "your_api_key_here" || gemini_key == "your_api_key_here") {
    warning("API key appears to be placeholder", call. = FALSE)
    return(FALSE)
  }

  return(TRUE)
}

# GEMINI API CALL ===============================================================

#' Call Gemini API
#'
#' Wrapper for calling Google Gemini API via ellmer with circuit breaker
#' protection and timeout handling.
#'
#' @param prompt Character string, prompt to send
#' @param model Character string, model identifier
#' @param timeout Numeric, timeout in seconds
#'
#' @return Raw response from ellmer, or NULL on error
#'
#' @keywords internal
gemini_call_api <- function(prompt, model, timeout) {
  # Validate setup
  if (!gemini_validate_setup()) {
    stop("Gemini not configured. Check API key.", call. = FALSE)
  }

  # Check circuit breaker
  if (circuit_breaker_is_open()) {
    stop("Circuit breaker open - too many recent failures. Try again later.",
      call. = FALSE
    )
  }

  # Initialize chat
  api_key <- Sys.getenv("GOOGLE_API_KEY", unset = "")
  if (api_key == "") {
    api_key <- Sys.getenv("GEMINI_API_KEY")
  }

  chat <- ellmer::chat_google_gemini(
    model = model,
    credentials = api_key
  )

  # Call with timeout wrapper
  response <- NULL
  tryCatch(
    {
      setTimeLimit(elapsed = timeout, transient = TRUE)
      response <- chat$chat(prompt)
      setTimeLimit(elapsed = Inf, transient = FALSE)
    },
    error = function(e) {
      setTimeLimit(elapsed = Inf, transient = FALSE)

      # Record failure
      circuit_breaker_record_failure()

      if (grepl("reached elapsed time limit|time limit", e$message)) {
        stop("API call timeout exceeded", call. = FALSE)
      }
      stop(e$message, call. = FALSE)
    }
  )

  # Record success
  circuit_breaker_record_success()

  return(response)
}

# GEMINI TEXT EXTRACTION ========================================================

#' Extract Text from Gemini Response
#'
#' Handles different ellmer response formats:
#' - ellmer 0.2.0+: character vector
#' - Older versions: list with $text
#'
#' @param response Raw response from ellmer
#'
#' @return Character string with extracted text
#'
#' @keywords internal
gemini_extract_text <- function(response) {
  if (is.character(response)) {
    return(response)
  }

  if (is.list(response) && !is.null(response$text)) {
    return(response$text)
  }

  stop("Unexpected response format from ellmer", call. = FALSE)
}

# CIRCUIT BREAKER IMPLEMENTATION ================================================

#' Check if Circuit Breaker is Open
#'
#' Returns TRUE if circuit breaker is currently blocking API calls.
#' Circuit breaker opens after threshold failures and auto-resets after timeout.
#'
#' @return Logical
#'
#' @keywords internal
circuit_breaker_is_open <- function() {
  config <- bfhllm_get_config()
  threshold <- config$circuit_breaker$failure_threshold
  reset_timeout <- config$circuit_breaker$reset_timeout_seconds

  if (!.gemini_circuit_breaker$is_open) {
    return(FALSE)
  }

  # Check if reset timeout has passed
  if (!is.null(.gemini_circuit_breaker$last_failure_time)) {
    elapsed <- as.numeric(
      difftime(
        Sys.time(),
        .gemini_circuit_breaker$last_failure_time,
        units = "secs"
      )
    )

    if (elapsed > reset_timeout) {
      .gemini_circuit_breaker$is_open <- FALSE
      .gemini_circuit_breaker$failures <- 0L
      return(FALSE)
    }
  }

  return(TRUE)
}

#' Record Circuit Breaker Failure
#'
#' Records API failure and opens circuit breaker if threshold is reached.
#'
#' @keywords internal
circuit_breaker_record_failure <- function() {
  config <- bfhllm_get_config()
  threshold <- config$circuit_breaker$failure_threshold

  .gemini_circuit_breaker$failures <- .gemini_circuit_breaker$failures + 1L
  .gemini_circuit_breaker$last_failure_time <- Sys.time()

  if (.gemini_circuit_breaker$failures >= threshold) {
    .gemini_circuit_breaker$is_open <- TRUE
    warning(sprintf("Circuit breaker opened after %d failures", threshold),
      call. = FALSE
    )
  }
}

#' Record Circuit Breaker Success
#'
#' Records successful API call and resets circuit breaker state.
#'
#' @keywords internal
circuit_breaker_record_success <- function() {
  .gemini_circuit_breaker$failures <- 0L
  .gemini_circuit_breaker$is_open <- FALSE
}

#' Get Circuit Breaker Status
#'
#' Returns current circuit breaker state for monitoring and debugging.
#'
#' @return List with circuit breaker status:
#' \describe{
#'   \item{is_open}{Logical, TRUE if circuit breaker is open}
#'   \item{failures}{Integer, current failure count}
#'   \item{last_failure_time}{POSIXct, timestamp of last failure (or NULL)}
#' }
#'
#' @examples
#' \dontrun{
#' status <- bfhllm_circuit_breaker_status()
#' if (status$is_open) {
#'   message("Circuit breaker is open - API calls blocked")
#' }
#' }
#'
#' @export
bfhllm_circuit_breaker_status <- function() {
  list(
    is_open = .gemini_circuit_breaker$is_open,
    failures = .gemini_circuit_breaker$failures,
    last_failure_time = .gemini_circuit_breaker$last_failure_time
  )
}

#' Reset Circuit Breaker
#'
#' Manually resets circuit breaker state. Useful for testing or administrative
#' intervention after resolving API issues.
#'
#' @examples
#' \dontrun{
#' # After fixing API connectivity issues
#' bfhllm_circuit_breaker_reset()
#' }
#'
#' @export
bfhllm_circuit_breaker_reset <- function() {
  .gemini_circuit_breaker$failures <- 0L
  .gemini_circuit_breaker$last_failure_time <- NULL
  .gemini_circuit_breaker$is_open <- FALSE

  message("Circuit breaker manually reset")
}
