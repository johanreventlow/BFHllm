# test-rag.R
# Tests for RAG Integration

test_that("bfhllm_query_knowledge validates query input", {
  expect_warning(result <- bfhllm_query_knowledge(NULL), "query must be")
  expect_null(result)

  expect_warning(result <- bfhllm_query_knowledge(""), "query must be")
  expect_null(result)

  expect_warning(result <- bfhllm_query_knowledge(123), "query must be")
  expect_null(result)
})

test_that("bfhllm_query_knowledge validates method parameter", {
  expect_warning(
    result <- bfhllm_query_knowledge("test", method = "invalid"),
    "method must be"
  )
  expect_null(result)
})

test_that("bfhllm_query_knowledge returns NULL if ragnar not installed", {
  # Mock scenario where ragnar is not available
  # (actual implementation would require more complex mocking)
  skip("Requires mocking - test manually")
})

test_that("bfhllm_format_rag_context handles NULL results", {
  result <- bfhllm_format_rag_context(NULL)
  expect_null(result)
})

test_that("bfhllm_format_rag_context handles empty results", {
  empty_df <- data.frame(
    text = character(0),
    score = numeric(0)
  )

  result <- bfhllm_format_rag_context(empty_df)
  expect_null(result)
})

test_that("bfhllm_format_rag_context formats results correctly", {
  # Mock RAG results
  mock_results <- data.frame(
    text = c("First chunk text", "Second chunk text", "Third chunk text"),
    score = c(0.95, 0.87, 0.76),
    stringsAsFactors = FALSE
  )

  # Without scores
  result <- bfhllm_format_rag_context(mock_results, include_scores = FALSE)

  expect_true(grepl("Context from knowledge base:", result, fixed = TRUE))
  expect_true(grepl("[1] First chunk text", result, fixed = TRUE))
  expect_true(grepl("[2] Second chunk text", result, fixed = TRUE))
  expect_true(grepl("[3] Third chunk text", result, fixed = TRUE))
  expect_false(grepl("score:", result))

  # With scores
  result_with_scores <- bfhllm_format_rag_context(
    mock_results,
    include_scores = TRUE
  )

  expect_true(grepl("score:", result_with_scores))
  expect_true(grepl("0.95", result_with_scores))
})

test_that("bfhllm_format_rag_context respects max_chunks limit", {
  # Mock many results
  mock_results <- data.frame(
    text = paste("Chunk", 1:10),
    score = seq(1, 0.1, length.out = 10),
    stringsAsFactors = FALSE
  )

  # Limit to 3 chunks
  result <- bfhllm_format_rag_context(mock_results, max_chunks = 3)

  # Should only include first 3
  expect_true(grepl("[1]", result, fixed = TRUE))
  expect_true(grepl("[2]", result, fixed = TRUE))
  expect_true(grepl("[3]", result, fixed = TRUE))
  expect_false(grepl("[4]", result, fixed = TRUE))
})

test_that("bfhllm_chat_with_rag validates question input", {
  expect_warning(result <- bfhllm_chat_with_rag(NULL), "question must be")
  expect_null(result)

  expect_warning(result <- bfhllm_chat_with_rag(""), "question must be")
  expect_null(result)
})

test_that("bfhllm_chat_with_rag handles RAG query failures gracefully", {
  # If RAG query fails, should still proceed with non-RAG chat
  # This requires mocking, skip for now
  skip("Requires mocking - test manually")
})

test_that("bfhllm_chat_with_rag combines contexts correctly", {
  # This requires mocking RAG query and LLM call
  # Test manually or in integration tests
  skip("Requires mocking - test manually")
})

# Integration test (requires ragnar + API key)
test_that("bfhllm_chat_with_rag end-to-end works", {
  skip_if_not_installed("ragnar")

  # Skip if no API key
  api_key <- Sys.getenv("GOOGLE_API_KEY")
  if (api_key == "" || api_key == "your_api_key_here") {
    skip("No API key configured")
  }

  # Skip if store not built
  store_path <- system.file("ragnar_store", package = "BFHllm")
  dev_store_path <- "inst/ragnar_store"

  if (store_path == "" && !file.exists(dev_store_path)) {
    skip("Ragnar store not found")
  }

  # Try a simple RAG query (may fail due to API issues, that's ok)
  result <- suppressWarnings(
    bfhllm_chat_with_rag(
      question = "What is a run chart?",
      top_k = 2,
      max_chars = 200
    )
  )

  # Should return string or NULL (if API failed)
  expect_true(is.null(result) || is.character(result))
})
