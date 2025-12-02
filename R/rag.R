# rag.R
# RAG (Retrieval-Augmented Generation) Integration

#' Query Knowledge Store
#'
#' Queries the Ragnar knowledge store for relevant information. Supports both
#' semantic search (embeddings) and keyword search (BM25), or hybrid mode
#' combining both.
#'
#' @param query Character string, the query to search for
#' @param store ragnar_store object (optional). If NULL, loads from cache/default.
#' @param top_k Integer, number of top results to return (default: 5)
#' @param method Character string, search method: "hybrid" (default), "semantic", or "bm25"
#'
#' @return Data frame with columns: chunk_id, text, score, metadata, or NULL on error
#'
#' @details
#' **Search Methods:**
#' - "hybrid": Combines semantic + BM25 (best for most queries)
#' - "semantic": Vector similarity search via embeddings
#' - "bm25": Keyword-based search (fast, good for exact terms)
#'
#' **Store Loading:**
#' If store is NULL, automatically loads via `bfhllm_load_knowledge_store()`.
#' Store is cached after first load for performance.
#'
#' **Error Handling:**
#' Returns NULL if store unavailable or query fails. Check return value before
#' using results.
#'
#' @examples
#' \dontrun{
#' # Query with default hybrid search
#' results <- bfhllm_query_knowledge("run chart interpretation")
#'
#' # Query with semantic search only
#' results <- bfhllm_query_knowledge(
#'   "special cause variation",
#'   method = "semantic",
#'   top_k = 3
#' )
#'
#' # Use existing store
#' store <- bfhllm_load_knowledge_store()
#' results <- bfhllm_query_knowledge("control limits", store = store)
#' }
#'
#' @export
bfhllm_query_knowledge <- function(query,
                                    store = NULL,
                                    top_k = 5,
                                    method = "hybrid") {
  # Validate inputs
  if (!is.character(query) || length(query) == 0 || nchar(query) == 0) {
    warning("query must be a non-empty character string", call. = FALSE)
    return(NULL)
  }

  if (!method %in% c("hybrid", "semantic", "bm25")) {
    warning("method must be 'hybrid', 'semantic', or 'bm25'", call. = FALSE)
    return(NULL)
  }

  # Load store if not provided
  if (is.null(store)) {
    store <- bfhllm_load_knowledge_store()

    if (is.null(store)) {
      warning("Knowledge store not available", call. = FALSE)
      return(NULL)
    }
  }

  # Check ragnar package
  if (!requireNamespace("ragnar", quietly = TRUE)) {
    warning("ragnar package required for RAG queries", call. = FALSE)
    return(NULL)
  }

  # Execute query with error handling
  results <- tryCatch(
    {
      ragnar::ragnar_search(
        store = store,
        query = query,
        top_k = top_k,
        method = method
      )
    },
    error = function(e) {
      warning(
        sprintf("RAG query failed: %s", e$message),
        call. = FALSE
      )
      return(NULL)
    }
  )

  return(results)
}

#' Format RAG Context for Prompt
#'
#' Formats RAG search results into a structured context string suitable for
#' inclusion in LLM prompts. Combines retrieved chunks with metadata.
#'
#' @param results Data frame from `bfhllm_query_knowledge()`, or NULL
#' @param max_chunks Integer, maximum chunks to include (default: 5)
#' @param include_scores Logical, include similarity scores in output (default: FALSE)
#'
#' @return Character string with formatted context, or NULL if no results
#'
#' @details
#' **Output Format:**
#' ```
#' Context from knowledge base:
#'
#' [1] <chunk text>
#' [2] <chunk text>
#' ...
#' ```
#'
#' **NULL Handling:**
#' Returns NULL if results is NULL or empty. Calling code should handle this
#' gracefully (e.g., proceed without RAG context).
#'
#' @examples
#' \dontrun{
#' # Query and format
#' results <- bfhllm_query_knowledge("run chart")
#' context <- bfhllm_format_rag_context(results)
#'
#' # Include scores for debugging
#' context <- bfhllm_format_rag_context(results, include_scores = TRUE)
#'
#' # Limit chunks
#' context <- bfhllm_format_rag_context(results, max_chunks = 3)
#' }
#'
#' @export
bfhllm_format_rag_context <- function(results,
                                       max_chunks = 5,
                                       include_scores = FALSE) {
  # Handle NULL or empty results
  if (is.null(results) || nrow(results) == 0) {
    return(NULL)
  }

  # Limit to max_chunks
  if (nrow(results) > max_chunks) {
    results <- results[1:max_chunks, ]
  }

  # Build formatted chunks
  chunks <- character(nrow(results))

  for (i in seq_len(nrow(results))) {
    chunk_text <- results$text[i]

    if (include_scores && !is.null(results$score)) {
      score <- round(results$score[i], 3)
      chunks[i] <- sprintf("[%d] (score: %s)\n%s", i, score, chunk_text)
    } else {
      chunks[i] <- sprintf("[%d] %s", i, chunk_text)
    }
  }

  # Combine into context string
  context <- paste(
    "Context from knowledge base:",
    "",
    paste(chunks, collapse = "\n\n"),
    sep = "\n"
  )

  return(context)
}

#' RAG-Enhanced Chat
#'
#' Performs RAG-enhanced LLM chat by retrieving relevant knowledge, injecting
#' it as context, and calling the LLM. Combines `bfhllm_query_knowledge()` and
#' `bfhllm_chat()`.
#'
#' @param question Character string, the question to answer
#' @param context Character string, additional context (optional). Will be combined
#'   with RAG-retrieved context.
#' @param store ragnar_store object (optional). If NULL, loads from cache/default.
#' @param top_k Integer, number of knowledge chunks to retrieve (default: 5)
#' @param method Character string, RAG search method: "hybrid", "semantic", "bm25"
#' @param ... Additional arguments passed to `bfhllm_chat()` (model, timeout, cache, etc.)
#'
#' @return Character string with LLM response, or NULL on error
#'
#' @details
#' **Workflow:**
#' 1. Query knowledge store for relevant chunks
#' 2. Format retrieved context
#' 3. Build structured prompt with RAG context + user context + question
#' 4. Call LLM via `bfhllm_chat()`
#'
#' **Graceful Degradation:**
#' If RAG query fails, proceeds with non-RAG chat (uses only user-provided
#' context). Logs warning but does not fail.
#'
#' **Prompt Structure:**
#' Uses `bfhllm_create_structured_prompt()` to organize:
#' - System: (optional, via ... or config)
#' - Context: RAG results + user context
#' - Question: User question
#' - Format: (optional, via ... or config)
#'
#' @examples
#' \dontrun{
#' # Basic RAG-enhanced question
#' answer <- bfhllm_chat_with_rag("What is a run chart?")
#'
#' # With additional context
#' answer <- bfhllm_chat_with_rag(
#'   question = "Should I use a run chart or SPC chart?",
#'   context = "Data: 24 observations, stable process"
#' )
#'
#' # With chat options
#' answer <- bfhllm_chat_with_rag(
#'   question = "Interpret this control chart",
#'   context = "8 points above centerline",
#'   model = "gemini-2.5-flash-lite",
#'   max_chars = 500,
#'   cache = my_cache
#' )
#' }
#'
#' @export
bfhllm_chat_with_rag <- function(question,
                                  context = NULL,
                                  store = NULL,
                                  top_k = 5,
                                  method = "hybrid",
                                  ...) {
  # Validate question
  if (!is.character(question) || length(question) == 0 || nchar(question) == 0) {
    warning("question must be a non-empty character string", call. = FALSE)
    return(NULL)
  }

  # Query knowledge store
  rag_results <- bfhllm_query_knowledge(
    query = question,
    store = store,
    top_k = top_k,
    method = method
  )

  # Format RAG context
  rag_context <- bfhllm_format_rag_context(rag_results, max_chunks = top_k)

  # Combine contexts
  combined_context <- if (!is.null(rag_context) && !is.null(context)) {
    paste(rag_context, context, sep = "\n\n")
  } else if (!is.null(rag_context)) {
    rag_context
  } else {
    context
  }

  # Build structured prompt
  prompt <- bfhllm_create_structured_prompt(
    question = question,
    context = combined_context
  )

  # Call LLM
  response <- bfhllm_chat(prompt = prompt, ...)

  return(response)
}
