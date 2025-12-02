# test-cache.R
# Tests for Generic Cache

test_that("bfhllm_cache_create creates cache with default TTL", {
  cache <- bfhllm_cache_create()

  expect_s3_class(cache, "bfhllm_cache")
  expect_type(cache$get, "closure")
  expect_type(cache$set, "closure")
  expect_type(cache$clear, "closure")
  expect_type(cache$stats, "closure")
})

test_that("cache stores and retrieves values", {
  cache <- bfhllm_cache_create()

  # Store value
  cache$set("key1", "value1")

  # Retrieve value
  value <- cache$get("key1")
  expect_equal(value, "value1")
})

test_that("cache returns NULL for missing keys", {
  cache <- bfhllm_cache_create()

  value <- cache$get("nonexistent")
  expect_null(value)
})

test_that("cache respects TTL", {
  # Create cache with 1 second TTL
  cache <- bfhllm_cache_create(ttl_seconds = 1)

  # Store value
  cache$set("key1", "value1")

  # Should be available immediately
  expect_equal(cache$get("key1"), "value1")

  # Wait for TTL to expire
  Sys.sleep(1.5)

  # Should return NULL (expired)
  expect_null(cache$get("key1"))
})

test_that("cache clear removes all entries", {
  cache <- bfhllm_cache_create()

  # Store multiple values
  cache$set("key1", "value1")
  cache$set("key2", "value2")
  cache$set("key3", "value3")

  # Check stats before clear
  stats <- cache$stats()
  expect_equal(stats$entries, 3)

  # Clear cache
  cache$clear()

  # Check stats after clear
  stats <- cache$stats()
  expect_equal(stats$entries, 0)

  # Values should be gone
  expect_null(cache$get("key1"))
  expect_null(cache$get("key2"))
  expect_null(cache$get("key3"))
})

test_that("cache stats returns correct information", {
  cache <- bfhllm_cache_create(ttl_seconds = 7200)

  # Empty cache
  stats <- cache$stats()
  expect_equal(stats$entries, 0)
  expect_equal(stats$ttl_seconds, 7200)
  expect_true(is.na(stats$oldest_entry))

  # Add entries
  cache$set("key1", "value1")
  Sys.sleep(0.1)
  cache$set("key2", "value2")

  # Stats with entries
  stats <- cache$stats()
  expect_equal(stats$entries, 2)
  expect_false(is.na(stats$oldest_entry))
})

test_that("bfhllm_generate_cache_key creates deterministic hashes", {
  # Same inputs should produce same key
  key1 <- bfhllm_generate_cache_key(prompt = "test", model = "gemini")
  key2 <- bfhllm_generate_cache_key(prompt = "test", model = "gemini")
  expect_equal(key1, key2)

  # Different inputs should produce different keys
  key3 <- bfhllm_generate_cache_key(prompt = "different", model = "gemini")
  expect_false(key1 == key3)
})

test_that("bfhllm_generate_cache_key handles complex objects", {
  key <- bfhllm_generate_cache_key(
    prompt = "test",
    metadata = list(a = 1, b = 2),
    context = list(x = "foo", y = "bar")
  )

  expect_type(key, "character")
  expect_true(nchar(key) > 0)
})

test_that("cache print method works", {
  cache <- bfhllm_cache_create()
  cache$set("key1", "value1")

  expect_output(print(cache), "bfhllm_cache")
  expect_output(print(cache), "Entries: 1")
})
