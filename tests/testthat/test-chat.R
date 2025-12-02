# test-chat.R
# Tests for Chat Function

test_that("bfhllm_chat validates prompt input", {
  # Missing prompt
  expect_warning(bfhllm_chat(), "prompt must be")
  expect_null(suppressWarnings(bfhllm_chat()))

  # NULL prompt
  expect_warning(bfhllm_chat(NULL), "prompt must be")
  expect_null(suppressWarnings(bfhllm_chat(NULL)))

  # Empty prompt
  expect_warning(bfhllm_chat(""), "prompt must be")
  expect_null(suppressWarnings(bfhllm_chat("")))
})

test_that("bfhllm_chat uses configuration defaults", {
  # Reset config to known state
  bfhllm_reset_config()

  config <- bfhllm_get_config()

  expect_equal(config$model, "gemini-2.5-flash-lite")
  expect_equal(config$timeout_seconds, 10)
  expect_equal(config$max_response_chars, 350)
})

test_that("bfhllm_chat_available checks setup", {
  # Should return FALSE if no API key
  old_key <- Sys.getenv("GOOGLE_API_KEY")
  Sys.unsetenv("GOOGLE_API_KEY")
  Sys.unsetenv("GEMINI_API_KEY")

  expect_warning(result <- bfhllm_chat_available())
  expect_false(result)

  # Restore key
  if (old_key != "") {
    Sys.setenv(GOOGLE_API_KEY = old_key)
  }
})

# Note: Full integration tests with actual API calls should be in
# tests/manual/ to avoid API costs and rate limits in CI/CD
