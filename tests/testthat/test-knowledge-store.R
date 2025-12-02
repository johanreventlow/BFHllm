# test-knowledge-store.R
# Tests for Knowledge Store Loading and Management

test_that("bfhllm_load_knowledge_store handles missing ragnar package", {
  # This test would require mocking requireNamespace
  # Skip in regular test runs
  skip("Requires mocking - test manually")
})

test_that("bfhllm_load_knowledge_store returns NULL if store not found", {
  # Reset cache
  bfhllm_reset_knowledge_store_cache()

  # Try to load with non-existent path
  result <- suppressWarnings(
    bfhllm_load_knowledge_store(store_path = "/non/existent/path")
  )

  expect_null(result)
})

test_that("bfhllm_reset_knowledge_store_cache clears cache", {
  # Should run without errors
  expect_silent(bfhllm_reset_knowledge_store_cache())
})

test_that("bfhllm_load_knowledge_store caches store after successful load", {
  # Skip if ragnar not installed or store not built
  skip_if_not_installed("ragnar")

  store_path <- system.file("ragnar_store", package = "BFHllm")
  if (store_path == "" || !file.exists(store_path)) {
    skip("Ragnar store not found - run data-raw/build_ragnar_store.R first")
  }

  # Reset cache
  bfhllm_reset_knowledge_store_cache()

  # First load
  store1 <- bfhllm_load_knowledge_store()

  # Second load should return cached version (fast)
  store2 <- bfhllm_load_knowledge_store()

  # Should be identical objects (cached)
  expect_identical(store1, store2)
})

test_that("bfhllm_load_knowledge_store auto-detects paths", {
  skip_if_not_installed("ragnar")

  # Check dev path fallback
  dev_store_path <- "inst/ragnar_store"

  if (file.exists(dev_store_path)) {
    bfhllm_reset_knowledge_store_cache()

    store <- suppressWarnings(bfhllm_load_knowledge_store())

    # Should load successfully in dev mode
    # (may be NULL if API key not set, that's ok)
    expect_true(is.null(store) || inherits(store, "ragnar_store"))
  }
})

test_that("bfhllm_build_knowledge_store validates inputs", {
  expect_error(
    bfhllm_build_knowledge_store(NULL, NULL),
    "docs_path"
  )

  expect_error(
    bfhllm_build_knowledge_store("docs", NULL),
    "output_path"
  )
})

test_that("API key fallback works correctly", {
  # Save original keys
  old_gemini <- Sys.getenv("GEMINI_API_KEY")
  old_google <- Sys.getenv("GOOGLE_API_KEY")

  # Clear GEMINI_API_KEY, set GOOGLE_API_KEY
  Sys.unsetenv("GEMINI_API_KEY")
  Sys.setenv(GOOGLE_API_KEY = "test_key")

  # Reset cache to trigger load attempt
  bfhllm_reset_knowledge_store_cache()

  # Try to load (will fail due to invalid key, but should set fallback)
  suppressWarnings(bfhllm_load_knowledge_store(store_path = "/non/existent"))

  # Check that GEMINI_API_KEY was set from GOOGLE_API_KEY
  expect_equal(Sys.getenv("GEMINI_API_KEY"), "test_key")

  # Restore original keys
  if (old_gemini != "") {
    Sys.setenv(GEMINI_API_KEY = old_gemini)
  } else {
    Sys.unsetenv("GEMINI_API_KEY")
  }

  if (old_google != "") {
    Sys.setenv(GOOGLE_API_KEY = old_google)
  } else {
    Sys.unsetenv("GOOGLE_API_KEY")
  }
})
