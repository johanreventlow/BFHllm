# test-cache-file.R
# Tests for File-Based Cache

test_that("bfhllm_file_cache_create creates cache object", {
  tmp <- tempdir()
  cache <- bfhllm_file_cache_create(cache_dir = tmp)
  expect_true(is.list(cache))
  expect_true(all(c("get", "set", "has", "clear", "stats") %in% names(cache)))
})

test_that("file cache set and get works", {
  tmp <- file.path(tempdir(), "test_cache_1")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cache <- bfhllm_file_cache_create(cache_dir = tmp)

  cache$set("key1", "analyse tekst her")
  result <- cache$get("key1")
  expect_equal(result, "analyse tekst her")
})

test_that("file cache returns NULL for missing key", {
  tmp <- file.path(tempdir(), "test_cache_2")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cache <- bfhllm_file_cache_create(cache_dir = tmp)

  result <- cache$get("nonexistent")
  expect_null(result)
})

test_that("file cache has() returns TRUE/FALSE correctly", {
  tmp <- file.path(tempdir(), "test_cache_3")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cache <- bfhllm_file_cache_create(cache_dir = tmp)

  expect_false(cache$has("key1"))
  cache$set("key1", "value")
  expect_true(cache$has("key1"))
})

test_that("file cache persists across instances", {
  tmp <- file.path(tempdir(), "test_cache_4")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  cache1 <- bfhllm_file_cache_create(cache_dir = tmp)
  cache1$set("persistent_key", "persistent_value")

  cache2 <- bfhllm_file_cache_create(cache_dir = tmp)
  result <- cache2$get("persistent_key")
  expect_equal(result, "persistent_value")
})

test_that("file cache clear removes all entries", {
  tmp <- file.path(tempdir(), "test_cache_5")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cache <- bfhllm_file_cache_create(cache_dir = tmp)

  cache$set("a", "1")
  cache$set("b", "2")
  cache$clear()
  expect_null(cache$get("a"))
  expect_null(cache$get("b"))
})

test_that("file cache stats returns counts", {
  tmp <- file.path(tempdir(), "test_cache_6")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cache <- bfhllm_file_cache_create(cache_dir = tmp)

  cache$set("a", "1")
  cache$set("b", "2")
  stats <- cache$stats()
  expect_equal(stats$entries, 2L)
})

test_that("file cache stats returns user-supplied cache_dir", {
  tmp <- file.path(tempdir(), "test_cache_7")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cache <- bfhllm_file_cache_create(cache_dir = tmp)

  stats <- cache$stats()
  expect_equal(normalizePath(stats$cache_dir, mustWork = FALSE),
               normalizePath(tmp, mustWork = FALSE))
})

test_that("file cache set overwrites existing key", {
  tmp <- file.path(tempdir(), "test_cache_8")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  cache <- bfhllm_file_cache_create(cache_dir = tmp)

  cache$set("key1", "A")
  cache$set("key1", "B")
  expect_equal(cache$get("key1"), "B")
})
