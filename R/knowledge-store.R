# knowledge-store.R
# Knowledge Store Loading and Management

# MODULE STATE ==================================================================

# Package-level environment for session-scoped store caching
.ragnar_store_cache <- new.env(parent = emptyenv())
.ragnar_store_cache$store <- NULL
.ragnar_store_cache$load_attempted <- FALSE

# KNOWLEDGE STORE LOADING =======================================================

#' Load Ragnar Knowledge Store
#'
#' Loads the pre-built Ragnar knowledge store. Store is loaded once per session
#' and cached for performance. Automatically detects development vs production
#' mode and adjusts paths accordingly.
#'
#' @param store_path Character string, path to store (optional). If NULL,
#'   auto-detects based on package installation status.
#'
#' @return ragnar_store object, or NULL if store not found/cannot be loaded
#'
#' @details
#' **Path Detection:**
#' - Production: `system.file("ragnar_store", package = "BFHllm")`
#' - Development: `inst/ragnar_store` (relative to package root)
#'
#' **API Key Setup:**
#' Ragnar requires `GEMINI_API_KEY`. If not set, automatically falls back to
#' `GOOGLE_API_KEY` if available.
#'
#' **Caching:**
#' Store is cached in package environment after first successful load.
#' Subsequent calls return cached store (fast).
#'
#' **Error Handling:**
#' Returns NULL on errors (store not found, ragnar not installed, load failure).
#' Check return value before querying.
#'
#' @examples
#' \dontrun{
#' # Load store (auto-detect path)
#' store <- bfhllm_load_knowledge_store()
#'
#' if (!is.null(store)) {
#'   # Query store
#'   results <- bfhllm_query_knowledge("run chart", store)
#' }
#'
#' # Force reload (clears cache)
#' bfhllm_reset_knowledge_store_cache()
#' store <- bfhllm_load_knowledge_store()
#' }
#'
#' @export
bfhllm_load_knowledge_store <- function(store_path = NULL) {
  # Return cached store if already loaded
  if (!is.null(.ragnar_store_cache$store)) {
    return(.ragnar_store_cache$store)
  }

  # Don't retry if previous load attempt failed
  if (.ragnar_store_cache$load_attempted) {
    return(NULL)
  }

  # Mark load attempt
  .ragnar_store_cache$load_attempted <- TRUE

  # API Key Setup: Ragnar requires GEMINI_API_KEY
  # Fallback from GOOGLE_API_KEY if GEMINI_API_KEY not set
  if (Sys.getenv("GEMINI_API_KEY") == "") {
    google_key <- Sys.getenv("GOOGLE_API_KEY")
    if (google_key != "" && google_key != "your_api_key_here") {
      Sys.setenv(GEMINI_API_KEY = google_key)
    } else {
      warning(
        "No API key found - RAG requires GEMINI_API_KEY or GOOGLE_API_KEY",
        call. = FALSE
      )
      # Don't return NULL - store can still be loaded for inspection
    }
  }

  # Check 1: Ragnar package installed
  if (!requireNamespace("ragnar", quietly = TRUE)) {
    warning(
      "ragnar package not installed - RAG disabled. Install with: install.packages('ragnar')",
      call. = FALSE
    )
    return(NULL)
  }

  # Check 2: Determine store path
  if (is.null(store_path)) {
    # Try installed package location first
    store_path <- system.file("ragnar_store", package = "BFHllm")

    # Development mode fallback
    if (store_path == "" || !file.exists(store_path)) {
      dev_store_path <- "inst/ragnar_store"
      if (file.exists(dev_store_path)) {
        store_path <- dev_store_path
      } else {
        warning(
          "Ragnar knowledge store not found. Expected: inst/ragnar_store. Run data-raw/build_ragnar_store.R to build.",
          call. = FALSE
        )
        return(NULL)
      }
    }
  }

  # Load store with error handling
  store <- tryCatch(
    {
      ragnar::ragnar_store_connect(location = store_path)
    },
    error = function(e) {
      warning(
        sprintf("Failed to load Ragnar store: %s", e$message),
        call. = FALSE
      )
      return(NULL)
    }
  )

  if (is.null(store)) {
    return(NULL)
  }

  # Cache successfully loaded store
  .ragnar_store_cache$store <- store

  return(store)
}

#' Reset Knowledge Store Cache
#'
#' Clears cached store and load attempt flag. Use for testing or forcing reload
#' after store rebuild.
#'
#' @return invisible(NULL)
#'
#' @examples
#' \dontrun{
#' # Force reload after rebuilding store
#' bfhllm_reset_knowledge_store_cache()
#' store <- bfhllm_load_knowledge_store()
#' }
#'
#' @export
bfhllm_reset_knowledge_store_cache <- function() {
  .ragnar_store_cache$store <- NULL
  .ragnar_store_cache$load_attempted <- FALSE

  invisible(NULL)
}

#' Build Knowledge Store
#'
#' Builds Ragnar knowledge store from markdown documents. This is typically
#' run once during package development, not at runtime.
#'
#' @param docs_path Character string, path to markdown documents directory
#' @param output_path Character string, path to output store directory
#'
#' @return invisible(NULL)
#'
#' @details
#' **Requirements:**
#' - ragnar package installed
#' - GOOGLE_API_KEY or GEMINI_API_KEY set (for embeddings)
#' - Markdown documents in docs_path
#'
#' **Process:**
#' 1. Initialize Ragnar store with Gemini embeddings
#' 2. Read markdown files
#' 3. Chunk documents (markdown-aware)
#' 4. Generate embeddings via Gemini API
#' 5. Build BM25 search index
#' 6. Persist store to output_path
#'
#' @examples
#' \dontrun{
#' # Build store (typically run in data-raw/build_ragnar_store.R)
#' bfhllm_build_knowledge_store(
#'   docs_path = "inst/spc_knowledge",
#'   output_path = "inst/ragnar_store"
#' )
#' }
#'
#' @export
bfhllm_build_knowledge_store <- function(docs_path, output_path) {
  if (!requireNamespace("ragnar", quietly = TRUE)) {
    stop("ragnar package required for building store", call. = FALSE)
  }

  # Check API key
  api_key <- Sys.getenv("GOOGLE_API_KEY")
  gemini_key <- Sys.getenv("GEMINI_API_KEY")

  if (api_key == "" && gemini_key == "") {
    stop("GOOGLE_API_KEY or GEMINI_API_KEY required for building store", call. = FALSE)
  }

  # Set GEMINI_API_KEY from GOOGLE_API_KEY if needed
  if (gemini_key == "" && api_key != "") {
    Sys.setenv(GEMINI_API_KEY = api_key)
  }

  message("Building Ragnar knowledge store...")
  message("Docs path: ", docs_path)
  message("Output path: ", output_path)

  # Initialize store
  store <- ragnar::ragnar_store_create(
    location = output_path,
    embedding_provider = "gemini"
  )

  # Add documents
  ragnar::ragnar_add_documents(
    store = store,
    path = docs_path,
    chunk_method = "markdown"
  )

  message("Knowledge store built successfully")
  invisible(NULL)
}
