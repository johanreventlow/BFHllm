# rate-limiter.R
# Rate Limiting for BFHllm API Calls
#
# Beskytter mod at overskride Gemini Free Tier grænser:
# - RPM (Requests Per Minute): 15 (default)
# - RPD (Requests Per Day): 1.500 (default)
# Konfigurerbar via bfhllm_configure(rate_limit = list(...))

# RATE LIMITER STATE ===========================================================

# Package-level environment for rate limiter state
.bfhllm_rate_limiter <- new.env(parent = emptyenv())
.bfhllm_rate_limiter$request_timestamps <- list()
.bfhllm_rate_limiter$daily_count <- 0L
.bfhllm_rate_limiter$daily_reset_date <- Sys.Date()

# INTERNAL FUNCTIONS ===========================================================

#' Fjern RPM timestamps ældre end 60 sekunder
#'
#' @keywords internal
rate_limiter_cleanup_rpm <- function() {
  now <- Sys.time()
  cutoff <- now - 60

  .bfhllm_rate_limiter$request_timestamps <- Filter(
    function(ts) ts > cutoff,
    .bfhllm_rate_limiter$request_timestamps
  )
}

#' Nulstil daglig tæller hvis ny dag (midnat lokal tid)
#'
#' @keywords internal
rate_limiter_reset_daily_if_needed <- function() {
  today <- Sys.Date()

  if (.bfhllm_rate_limiter$daily_reset_date < today) {
    .bfhllm_rate_limiter$daily_count <- 0L
    .bfhllm_rate_limiter$daily_reset_date <- today
  }
}

#' Registrer et nyt API request
#'
#' @keywords internal
rate_limiter_record_request <- function() {
  now <- Sys.time()

  # Tilføj timestamp for RPM tracking
  .bfhllm_rate_limiter$request_timestamps <- c(
    .bfhllm_rate_limiter$request_timestamps,
    list(now)
  )

  # Inkrementer daglig tæller
  .bfhllm_rate_limiter$daily_count <- .bfhllm_rate_limiter$daily_count + 1L
}

#' Tjek om et nyt request er tilladt
#'
#' @return Liste med: allowed (logical), reason (character/NULL), wait_seconds (numeric/NULL)
#'
#' @keywords internal
rate_limiter_check <- function() {
  config <- bfhllm_get_config()

  # Hvis rate limiting er deaktiveret
  if (!isTRUE(config$rate_limit$enabled)) {
    return(list(allowed = TRUE, reason = NULL, wait_seconds = NULL))
  }

  rpm_limit <- config$rate_limit$rpm
  rpd_limit <- config$rate_limit$rpd

  # Nulstil daglig tæller hvis ny dag
  rate_limiter_reset_daily_if_needed()

  # Cleanup gamle RPM timestamps
  rate_limiter_cleanup_rpm()

  # Tjek RPD først (mere alvorlig - kan ikke vente)
  if (.bfhllm_rate_limiter$daily_count >= rpd_limit) {
    return(list(
      allowed = FALSE,
      reason = "rpd",
      wait_seconds = NULL
    ))
  }

  # Tjek RPM
  current_rpm <- length(.bfhllm_rate_limiter$request_timestamps)
  if (current_rpm >= rpm_limit) {
    # Beregn ventetid: tid til ældste timestamp udløber
    oldest <- .bfhllm_rate_limiter$request_timestamps[[1]]
    wait_seconds <- as.numeric(difftime(oldest + 60, Sys.time(), units = "secs"))
    wait_seconds <- max(wait_seconds, 0.1)  # Mindst 0.1 sekund

    return(list(
      allowed = FALSE,
      reason = "rpm",
      wait_seconds = ceiling(wait_seconds)
    ))
  }

  return(list(allowed = TRUE, reason = NULL, wait_seconds = NULL))
}

#' Tjek rate limit og vent eller degradér afhængigt af konfiguration
#'
#' Returnerer NULL hvis request er tilladt, en fallback-besked (character) i
#' degrade mode, eller venter og returnerer NULL i wait mode.
#' Kaster fejl ved RPD-grænse i wait mode.
#'
#' @return NULL (request tilladt), character (fallback-besked), eller fejl
#'
#' @keywords internal
rate_limiter_check_and_wait <- function() {
  config <- bfhllm_get_config()

  # Hvis deaktiveret, tillad altid
  if (!isTRUE(config$rate_limit$enabled)) {
    return(NULL)
  }

  behavior <- config$rate_limit$behavior
  fallback_msg <- "AI-forslag er midlertidigt utilg\u00e6ngeligt (rate limit n\u00e5et). Pr\u00f8v igen senere."

  check <- rate_limiter_check()

  if (check$allowed) {
    return(NULL)
  }

  # RPD grænse nået
  if (check$reason == "rpd") {
    if (behavior == "degrade") {
      return(fallback_msg)
    }
    # I wait mode: kan ikke vente til midnat - giv fejl
    stop(
      sprintf(
        "Daglige API-gr\u00e6nse n\u00e5et (%d requests). Nulstilles ved midnat.",
        config$rate_limit$rpd
      ),
      call. = FALSE
    )
  }

  # RPM grænse nået
  if (check$reason == "rpm") {
    if (behavior == "degrade") {
      return(fallback_msg)
    }

    # Wait mode: vent til der er kapacitet
    wait_secs <- check$wait_seconds
    message(sprintf("Rate limit (RPM): venter %d sekund(er)...", wait_secs))
    Sys.sleep(wait_secs)

    # Cleanup og tjek igen efter ventetid
    rate_limiter_cleanup_rpm()
    return(NULL)
  }

  return(NULL)
}

# EXPORTED FUNCTIONS ===========================================================

#' Get Rate Limit Status
#'
#' Returns current rate limit usage, remaining capacity, and configuration.
#'
#' @return List with rate limit status:
#' \describe{
#'   \item{requests_this_minute}{Integer, requests in current sliding window}
#'   \item{requests_today}{Integer, requests since midnight}
#'   \item{rpm_limit}{Integer, configured RPM limit}
#'   \item{rpd_limit}{Integer, configured RPD limit}
#'   \item{rpm_remaining}{Integer, remaining RPM capacity}
#'   \item{rpd_remaining}{Integer, remaining RPD capacity}
#'   \item{daily_reset_date}{Date, when daily counter was last reset}
#'   \item{enabled}{Logical, whether rate limiting is active}
#'   \item{behavior}{Character, "wait" or "degrade"}
#' }
#'
#' @examples
#' \dontrun{
#' status <- bfhllm_rate_limit_status()
#' message(sprintf("RPM: %d/%d, RPD: %d/%d",
#'   status$requests_this_minute, status$rpm_limit,
#'   status$requests_today, status$rpd_limit))
#' }
#'
#' @export
bfhllm_rate_limit_status <- function() {
  config <- bfhllm_get_config()
  rpm_limit <- config$rate_limit$rpm
  rpd_limit <- config$rate_limit$rpd

  # Cleanup for korrekt RPM count
  rate_limiter_cleanup_rpm()
  rate_limiter_reset_daily_if_needed()

  current_rpm <- length(.bfhllm_rate_limiter$request_timestamps)
  current_rpd <- .bfhllm_rate_limiter$daily_count

  list(
    requests_this_minute = as.integer(current_rpm),
    requests_today = as.integer(current_rpd),
    rpm_limit = as.integer(rpm_limit),
    rpd_limit = as.integer(rpd_limit),
    rpm_remaining = as.integer(max(0L, rpm_limit - current_rpm)),
    rpd_remaining = as.integer(max(0L, rpd_limit - current_rpd)),
    daily_reset_date = .bfhllm_rate_limiter$daily_reset_date,
    enabled = isTRUE(config$rate_limit$enabled),
    behavior = config$rate_limit$behavior
  )
}

#' Reset Rate Limiter
#'
#' Manually resets all rate limiter state. Useful for testing or after
#' resolving rate limit issues.
#'
#' @examples
#' \dontrun{
#' bfhllm_rate_limit_reset()
#' }
#'
#' @export
bfhllm_rate_limit_reset <- function() {
  .bfhllm_rate_limiter$request_timestamps <- list()
  .bfhllm_rate_limiter$daily_count <- 0L
  .bfhllm_rate_limiter$daily_reset_date <- Sys.Date()

  message("Rate limiter reset")
}
