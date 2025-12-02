# cache.R
# Generic In-Memory Caching for LLM Responses

#' Create Generic In-Memory Cache
#'
#' Creates a generic cache object for storing LLM responses. Cache uses
#' hash-based keys and enforces TTL (time-to-live) on retrieval.
#'
#' @param ttl_seconds Numeric, time-to-live in seconds (default: 3600 = 1 hour)
#'
#' @return Cache object (environment) with methods:
#' \describe{
#'   \item{get(key)}{Retrieve cached value, or NULL if not found/expired}
#'   \item{set(key, value)}{Store value with current timestamp}
#'   \item{clear()}{Remove all cached entries}
#'   \item{stats()}{Return cache statistics}
#' }
#'
#' @details
#' **Cache Structure:**
#' Each cache entry is stored as:
#' ```r
#' list(value = response_text, timestamp = Sys.time())
#' ```
#'
#' **TTL Enforcement:**
#' Cache entries are checked on retrieval. If age exceeds TTL, NULL is returned
#' (cache miss). Expired entries are not automatically removed - use `clear()`
#' for manual cleanup.
#'
#' **Thread Safety:**
#' Cache is stored in an R environment. Not thread-safe - use separate cache
#' instances per thread/process.
#'
#' @examples
#' \dontrun{
#' # Create cache with 1 hour TTL
#' cache <- bfhllm_cache_create(ttl_seconds = 3600)
#'
#' # Store value
#' cache$set("key1", "response text")
#'
#' # Retrieve value
#' value <- cache$get("key1")
#'
#' # Check stats
#' stats <- cache$stats()
#' print(stats$entries) # 1
#'
#' # Clear cache
#' cache$clear()
#' }
#'
#' @export
bfhllm_cache_create <- function(ttl_seconds = 3600) {
  # Create environment for cache storage
  cache_env <- new.env(parent = emptyenv())
  cache_env$data <- list()
  cache_env$ttl_seconds <- ttl_seconds

  # Return cache object with methods
  structure(
    list(
      get = function(key) {
        cache_get(cache_env, key)
      },
      set = function(key, value) {
        cache_set(cache_env, key, value)
      },
      clear = function() {
        cache_clear(cache_env)
      },
      stats = function() {
        cache_stats(cache_env)
      }
    ),
    class = "bfhllm_cache"
  )
}

#' Generate Cache Key
#'
#' Creates deterministic hash from input data using xxhash64 algorithm.
#' Ensures same inputs always produce same cache key.
#'
#' @param ... Named arguments to include in cache key
#'
#' @return Character string (hex hash)
#'
#' @details
#' **Usage:**
#' Pass all relevant parameters that should distinguish cached responses.
#' Exclude volatile data (timestamps, random values, reactive triggers).
#'
#' **Hash Algorithm:**
#' Uses xxhash64 via digest package - fast and collision-resistant.
#'
#' @examples
#' \dontrun{
#' # Basic key generation
#' key <- bfhllm_generate_cache_key(
#'   prompt = "What is SPC?",
#'   model = "gemini-2.5-flash-lite"
#' )
#'
#' # With metadata
#' key <- bfhllm_generate_cache_key(
#'   prompt = prompt_text,
#'   metadata = list(chart_type = "run", n_points = 24),
#'   context = list(title = "Chart Title")
#' )
#' }
#'
#' @export
bfhllm_generate_cache_key <- function(...) {
  args <- list(...)

  # Serialize and hash
  key <- digest::digest(args, algo = "xxhash64")

  return(key)
}

# INTERNAL CACHE METHODS ========================================================

#' Get Value from Cache
#'
#' @param cache_env Environment, cache storage
#' @param key Character string, cache key
#'
#' @return Cached value, or NULL if not found/expired
#'
#' @keywords internal
cache_get <- function(cache_env, key) {
  data <- cache_env$data

  # Check if key exists
  if (!key %in% names(data)) {
    return(NULL)
  }

  entry <- data[[key]]

  # Check TTL
  age_seconds <- as.numeric(
    difftime(Sys.time(), entry$timestamp, units = "secs")
  )

  if (age_seconds > cache_env$ttl_seconds) {
    # Expired - return NULL
    return(NULL)
  }

  return(entry$value)
}

#' Set Value in Cache
#'
#' @param cache_env Environment, cache storage
#' @param key Character string, cache key
#' @param value Any R object to cache
#'
#' @keywords internal
cache_set <- function(cache_env, key, value) {
  cache_env$data[[key]] <- list(
    value = value,
    timestamp = Sys.time()
  )

  invisible(NULL)
}

#' Clear Cache
#'
#' @param cache_env Environment, cache storage
#'
#' @keywords internal
cache_clear <- function(cache_env) {
  n_entries <- length(cache_env$data)
  cache_env$data <- list()

  invisible(n_entries)
}

#' Get Cache Statistics
#'
#' @param cache_env Environment, cache storage
#'
#' @return List with statistics
#'
#' @keywords internal
cache_stats <- function(cache_env) {
  data <- cache_env$data

  list(
    entries = length(data),
    ttl_seconds = cache_env$ttl_seconds,
    oldest_entry = if (length(data) > 0) {
      min(vapply(data, function(e) e$timestamp, numeric(1)))
    } else {
      NA_real_
    }
  )
}

#' Print Cache Object
#'
#' @param x Cache object
#' @param ... Unused
#'
#' @export
print.bfhllm_cache <- function(x, ...) {
  stats <- x$stats()

  cat("<bfhllm_cache>\n")
  cat(sprintf("  Entries: %d\n", stats$entries))
  cat(sprintf("  TTL: %d seconds\n", stats$ttl_seconds))

  if (!is.na(stats$oldest_entry)) {
    age <- round(as.numeric(difftime(Sys.time(), stats$oldest_entry, units = "secs")))
    cat(sprintf("  Oldest entry: %d seconds ago\n", age))
  }

  invisible(x)
}
