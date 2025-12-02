# cache-shiny.R
# Shiny Session-Scoped Cache Adapter

#' Create Shiny Session Cache
#'
#' Creates a cache object that stores data in Shiny session's userData.
#' Cache is automatically cleaned up when session ends.
#'
#' @param session Shiny session object
#' @param ttl_seconds Numeric, time-to-live in seconds (default: 3600)
#'
#' @return Cache object with same interface as `bfhllm_cache_create()`
#'
#' @details
#' **Storage Location:**
#' Cache is stored in `session$userData$bfhllm_cache` as a reactiveVal.
#' This ensures cache is session-scoped and automatically cleaned on disconnect.
#'
#' **Automatic Cleanup:**
#' Registers `session$onSessionEnded()` callback to clear cache when user
#' disconnects, preventing memory leaks.
#'
#' **Idempotent:**
#' Safe to call multiple times - will reuse existing cache if already initialized.
#'
#' **Use Cases:**
#' - Shiny applications using BFHllm for AI suggestions
#' - Reduce API calls and costs within a user session
#' - Consistent responses for repeated queries
#'
#' @examples
#' \dontrun{
#' # In Shiny server function
#' server <- function(input, output, session) {
#'   # Create session cache (call once per session)
#'   cache <- bfhllm_cache_shiny(session, ttl_seconds = 3600)
#'
#'   # Use cache with LLM calls
#'   observeEvent(input$generate_btn, {
#'     key <- bfhllm_generate_cache_key(
#'       prompt = input$prompt_text,
#'       model = "gemini-2.5-flash-lite"
#'     )
#'
#'     # Check cache first
#'     cached <- cache$get(key)
#'     if (!is.null(cached)) {
#'       output$result <- renderText(cached)
#'       return()
#'     }
#'
#'     # Make API call
#'     response <- bfhllm_chat(input$prompt_text)
#'
#'     # Cache response
#'     cache$set(key, response)
#'
#'     output$result <- renderText(response)
#'   })
#' }
#' }
#'
#' @export
bfhllm_cache_shiny <- function(session, ttl_seconds = 3600) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("shiny package required for session cache", call. = FALSE)
  }

  # Check session object
  if (missing(session) || is.null(session)) {
    stop("session object required", call. = FALSE)
  }

  # Initialize cache if not already present
  if (is.null(session$userData$bfhllm_cache)) {
    # Create reactiveVal for cache storage
    session$userData$bfhllm_cache <- shiny::reactiveVal(list())
    session$userData$bfhllm_cache_ttl <- ttl_seconds

    # Setup cleanup on session end
    session$onSessionEnded(function() {
      if (!is.null(session$userData$bfhllm_cache)) {
        shiny::isolate({
          cache_data <- session$userData$bfhllm_cache()
          n_entries <- length(cache_data)

          # Clear cache
          session$userData$bfhllm_cache(list())

          message(sprintf("BFHllm cache cleared on session end (%d entries)", n_entries))
        })
      }
    })
  }

  # Return cache object with methods
  structure(
    list(
      get = function(key) {
        shiny_cache_get(session, key)
      },
      set = function(key, value) {
        shiny_cache_set(session, key, value)
      },
      clear = function() {
        shiny_cache_clear(session)
      },
      stats = function() {
        shiny_cache_stats(session)
      }
    ),
    class = c("bfhllm_cache_shiny", "bfhllm_cache")
  )
}

# INTERNAL SHINY CACHE METHODS ==================================================

#' Get Value from Shiny Session Cache
#'
#' @param session Shiny session object
#' @param key Character string, cache key
#'
#' @return Cached value, or NULL if not found/expired
#'
#' @keywords internal
shiny_cache_get <- function(session, key) {
  # Isolate to avoid requiring reactive context
  shiny::isolate({
    cache_data <- session$userData$bfhllm_cache()
    ttl_seconds <- session$userData$bfhllm_cache_ttl

    # Check if key exists
    if (!key %in% names(cache_data)) {
      return(NULL)
    }

    entry <- cache_data[[key]]

    # Check TTL
    age_seconds <- as.numeric(
      difftime(Sys.time(), entry$timestamp, units = "secs")
    )

    if (age_seconds > ttl_seconds) {
      # Expired
      return(NULL)
    }

    return(entry$value)
  })
}

#' Set Value in Shiny Session Cache
#'
#' @param session Shiny session object
#' @param key Character string, cache key
#' @param value Any R object to cache
#'
#' @keywords internal
shiny_cache_set <- function(session, key, value) {
  shiny::isolate({
    cache_data <- session$userData$bfhllm_cache()

    # Add entry
    cache_data[[key]] <- list(
      value = value,
      timestamp = Sys.time()
    )

    # Update reactiveVal
    session$userData$bfhllm_cache(cache_data)
  })

  invisible(NULL)
}

#' Clear Shiny Session Cache
#'
#' @param session Shiny session object
#'
#' @keywords internal
shiny_cache_clear <- function(session) {
  shiny::isolate({
    cache_data <- session$userData$bfhllm_cache()
    n_entries <- length(cache_data)

    # Clear
    session$userData$bfhllm_cache(list())

    return(n_entries)
  })
}

#' Get Shiny Session Cache Statistics
#'
#' @param session Shiny session object
#'
#' @return List with statistics
#'
#' @keywords internal
shiny_cache_stats <- function(session) {
  shiny::isolate({
    cache_data <- session$userData$bfhllm_cache()
    ttl_seconds <- session$userData$bfhllm_cache_ttl

    list(
      entries = length(cache_data),
      ttl_seconds = ttl_seconds,
      oldest_entry = if (length(cache_data) > 0) {
        min(vapply(cache_data, function(e) e$timestamp, numeric(1)))
      } else {
        NA_real_
      }
    )
  })
}

#' Print Shiny Cache Object
#'
#' @param x Shiny cache object
#' @param ... Unused
#'
#' @export
print.bfhllm_cache_shiny <- function(x, ...) {
  stats <- x$stats()

  cat("<bfhllm_cache_shiny>\n")
  cat(sprintf("  Entries: %d\n", stats$entries))
  cat(sprintf("  TTL: %d seconds\n", stats$ttl_seconds))
  cat("  Storage: Shiny session userData\n")

  if (!is.na(stats$oldest_entry)) {
    age <- round(as.numeric(difftime(Sys.time(), stats$oldest_entry, units = "secs")))
    cat(sprintf("  Oldest entry: %d seconds ago\n", age))
  }

  invisible(x)
}
