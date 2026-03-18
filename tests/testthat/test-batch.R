# test-batch.R
# Tests for batch SPC analysis functions

# HELPERS =====================================================================

# Opret test-kontekst for et enkelt diagram
make_test_context <- function(key = "diagram_1",
                              chart_type = "run",
                              n_points = 24L,
                              signals = 0L) {
  list(
    spc_result = list(
      metadata = list(
        chart_type = chart_type,
        n_points = n_points,
        signals_detected = signals,
        anhoej_rules = list(
          longest_run = 5L,
          n_crossings = 10L,
          n_crossings_min = 8L
        )
      )
    ),
    llm_context = list(
      data_definition = paste("Indikator for", key),
      chart_title = paste("Titel", key),
      y_axis_unit = "procent",
      target_value = 95,
      signal_examples = "Ingen"
    )
  )
}

# Opret named list af test-kontekster
make_test_contexts <- function(n = 3) {
  keys <- paste0("diagram_", seq_len(n))
  contexts <- lapply(keys, function(k) make_test_context(key = k))
  names(contexts) <- keys
  contexts
}

# HELPERS V2 (med baseline_analysis) ==========================================

# Opdater make_test_context til at inkludere baseline_analysis
make_test_context_v2 <- function(key = "diagram_1",
                                  chart_type = "run",
                                  n_points = 24L,
                                  signals = 0L) {
  list(
    spc_result = list(
      metadata = list(
        chart_type = chart_type,
        n_points = n_points,
        signals_detected = signals,
        anhoej_rules = list(
          longest_run = 5L,
          n_crossings = 10L,
          n_crossings_min = 8L
        )
      )
    ),
    llm_context = list(
      data_definition = paste("Indikator for", key),
      chart_title = paste("Titel", key),
      y_axis_unit = "procent",
      target_value = 95,
      department = paste("Afdeling", key),
      baseline_analysis = paste("Processen viser stabil adfaerd for", key, ". Niveauet er ved maalet (95)."),
      signal_examples = "Ingen"
    )
  )
}

make_test_contexts_v2 <- function(n = 3) {
  keys <- paste0("diagram_", seq_len(n))
  contexts <- lapply(keys, function(k) make_test_context_v2(key = k))
  names(contexts) <- keys
  contexts
}

# BUILD BATCH PROMPT ==========================================================

test_that("build_batch_prompt uses rewrite approach when baseline_analysis present", {
  contexts <- make_test_contexts_v2(2)

  prompt <- build_batch_prompt(contexts, min_chars = 300, max_chars = 375)

  # Skal indeholde baseline-analyser
  expect_true(grepl("Processen viser stabil", prompt, fixed = TRUE))
  # Skal indeholde afdeling
  expect_true(grepl("Afdeling diagram_1", prompt, fixed = TRUE))
  # Skal instruere omskrivning, ikke fri generering
  expect_true(grepl("omskriv", prompt, ignore.case = TRUE))
  # Skal IKKE indeholde gammel "generer" instruktion
  expect_false(grepl("Generer en kort, positivt", prompt, fixed = TRUE))
})

test_that("build_batch_prompt creates prompt with all diagram keys", {
  contexts <- make_test_contexts(3)

  prompt <- build_batch_prompt(contexts, min_chars = 300, max_chars = 375)

  expect_true(is.character(prompt))
  expect_true(nchar(prompt) > 0)

  # Alle diagram-nogler skal vaere nævnt i prompten
  for (key in names(contexts)) {
    expect_true(grepl(key, prompt, fixed = TRUE),
      info = paste("Prompt mangler key:", key))
  }
})

test_that("build_batch_prompt includes JSON instruction", {
  contexts <- make_test_contexts(2)

  prompt <- build_batch_prompt(contexts, min_chars = 300, max_chars = 375)

  # Skal instruere JSON output
  expect_true(grepl("JSON", prompt, ignore.case = TRUE))
})

test_that("build_batch_prompt includes metadata from each context", {
  contexts <- make_test_contexts(1)

  prompt <- build_batch_prompt(contexts, min_chars = 300, max_chars = 375)

  # Metadata fra konteksten skal vaere inkluderet
  expect_true(grepl("Indikator for diagram_1", prompt, fixed = TRUE))
  expect_true(grepl("Titel diagram_1", prompt, fixed = TRUE))
  expect_true(grepl("procent", prompt, fixed = TRUE))
})

test_that("build_batch_prompt includes char limits", {
  contexts <- make_test_contexts(1)

  prompt <- build_batch_prompt(contexts, min_chars = 250, max_chars = 400)

  expect_true(grepl("250", prompt, fixed = TRUE))
  expect_true(grepl("400", prompt, fixed = TRUE))
})

# PARSE BATCH RESPONSE ========================================================

test_that("parse_batch_response handles valid JSON", {
  keys <- c("diagram_1", "diagram_2")
  response <- '{"diagram_1": "Analyse tekst 1", "diagram_2": "Analyse tekst 2"}'

  result <- parse_batch_response(response, keys)

  expect_true(is.list(result))
  expect_equal(length(result), 2)
  expect_equal(result[["diagram_1"]], "Analyse tekst 1")
  expect_equal(result[["diagram_2"]], "Analyse tekst 2")
})

test_that("parse_batch_response handles partial JSON (missing keys -> NULL)", {
  keys <- c("diagram_1", "diagram_2", "diagram_3")
  response <- '{"diagram_1": "Tekst 1", "diagram_3": "Tekst 3"}'

  result <- parse_batch_response(response, keys)

  expect_equal(length(result), 3)
  expect_equal(result[["diagram_1"]], "Tekst 1")
  expect_null(result[["diagram_2"]])
  expect_equal(result[["diagram_3"]], "Tekst 3")
})

test_that("parse_batch_response handles invalid JSON (returns all NULL)", {
  keys <- c("diagram_1", "diagram_2")
  response <- "This is not valid JSON at all {broken"

  result <- parse_batch_response(response, keys)

  expect_equal(length(result), 2)
  expect_null(result[["diagram_1"]])
  expect_null(result[["diagram_2"]])
})

test_that("parse_batch_response extracts JSON from surrounding text", {
  keys <- c("diagram_1", "diagram_2")
  response <- 'Her er analysen:\n```json\n{"diagram_1": "Tekst 1", "diagram_2": "Tekst 2"}\n```\nDet var alt.'

  result <- parse_batch_response(response, keys)

  expect_equal(result[["diagram_1"]], "Tekst 1")
  expect_equal(result[["diagram_2"]], "Tekst 2")
})

test_that("parse_batch_response handles empty response", {
  keys <- c("diagram_1")
  response <- ""

  result <- parse_batch_response(response, keys)

  expect_equal(length(result), 1)
  expect_null(result[["diagram_1"]])
})

test_that("parse_batch_response handles NULL response", {
  keys <- c("diagram_1")

  result <- parse_batch_response(NULL, keys)

  expect_equal(length(result), 1)
  expect_null(result[["diagram_1"]])
})

# BFHLLM_SPC_SUGGESTIONS_BATCH ================================================

test_that("bfhllm_spc_suggestions_batch returns correct structure", {
  contexts <- make_test_contexts(2)

  # Mock bfhllm_chat til at returnere valid JSON
  mock_chat <- function(prompt, ...) {
    '{"diagram_1": "Batch analyse 1.", "diagram_2": "Batch analyse 2."}'
  }

  # Mock rate limit status (RPD remaining)
  mock_status <- function() {
    list(rpd_remaining = 100L, enabled = TRUE)
  }

  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  tmp <- file.path(tempdir(), "test_batch_struct")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  result <- bfhllm_spc_suggestions_batch(
    contexts,
    cache_dir = tmp,
    use_cache = FALSE
  )

  # Tjek struktur
  expect_true(is.list(result))
  expect_true(all(c("analyses", "from_cache", "from_api", "failed", "rpd_exhausted") %in% names(result)))
  expect_true(is.list(result$analyses))
  expect_true(is.integer(result$from_cache) || is.numeric(result$from_cache))
  expect_true(is.integer(result$from_api) || is.numeric(result$from_api))
  expect_true(is.character(result$failed))
  expect_true(is.logical(result$rpd_exhausted))
})

test_that("bfhllm_spc_suggestions_batch uses file cache", {
  contexts <- make_test_contexts(2)

  call_count <- 0L

  mock_chat <- function(prompt, ...) {
    call_count <<- call_count + 1L
    '{"diagram_1": "Cached analyse 1.", "diagram_2": "Cached analyse 2."}'
  }

  mock_status <- function() {
    list(rpd_remaining = 100L, enabled = TRUE)
  }

  tmp <- file.path(tempdir(), "test_batch_cache")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # Foerste kald: API
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  result1 <- bfhllm_spc_suggestions_batch(
    contexts,
    cache_dir = tmp,
    use_cache = TRUE
  )

  expect_equal(result1$from_api, 2L)
  expect_equal(result1$from_cache, 0L)
  api_calls_first <- call_count

  # Andet kald: fra cache (nulstil call_count)
  call_count <- 0L
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  result2 <- bfhllm_spc_suggestions_batch(
    contexts,
    cache_dir = tmp,
    use_cache = TRUE
  )

  expect_equal(result2$from_cache, 2L)
  expect_equal(result2$from_api, 0L)
  expect_equal(call_count, 0L)  # Ingen API kald
})

test_that("bfhllm_spc_suggestions_batch respects force_refresh", {
  contexts <- make_test_contexts(1)

  call_count <- 0L

  mock_chat <- function(prompt, ...) {
    call_count <<- call_count + 1L
    '{"diagram_1": "Refreshed analyse."}'
  }

  mock_status <- function() {
    list(rpd_remaining = 100L, enabled = TRUE)
  }

  tmp <- file.path(tempdir(), "test_batch_force")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  # Foerste kald: populer cache
  bfhllm_spc_suggestions_batch(contexts, cache_dir = tmp, use_cache = TRUE)
  first_calls <- call_count

  # Andet kald med force_refresh: skal kalde API igen
  call_count <- 0L
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  result <- bfhllm_spc_suggestions_batch(
    contexts,
    cache_dir = tmp,
    use_cache = TRUE,
    force_refresh = TRUE
  )

  expect_equal(result$from_api, 1L)
  expect_equal(call_count, 1L)
})

test_that("bfhllm_spc_suggestions_batch splits into correct batches", {
  # 5 diagrammer med batch_size = 2 => 3 batches (2+2+1)
  contexts <- make_test_contexts(5)

  call_count <- 0L

  mock_chat <- function(prompt, ...) {
    call_count <<- call_count + 1L
    # Returner JSON for de nogler der er i prompten
    # (vi returnerer alle - parse_batch_response haandterer mismatch)
    '{"diagram_1": "A1", "diagram_2": "A2", "diagram_3": "A3", "diagram_4": "A4", "diagram_5": "A5"}'
  }

  mock_status <- function() {
    list(rpd_remaining = 100L, enabled = TRUE)
  }

  tmp <- file.path(tempdir(), "test_batch_split")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  result <- bfhllm_spc_suggestions_batch(
    contexts,
    batch_size = 2L,
    cache_dir = tmp,
    use_cache = FALSE
  )

  # 3 batches => 3 API kald
  expect_equal(call_count, 3L)
  expect_equal(result$from_api, 5L)
})

test_that("bfhllm_spc_suggestions_batch stops on rpd_exhausted", {
  contexts <- make_test_contexts(3)

  mock_chat <- function(prompt, ...) {
    '{"diagram_1": "A1"}'
  }

  # RPD er opbrugt
  mock_status <- function() {
    list(rpd_remaining = 0L, enabled = TRUE)
  }

  tmp <- file.path(tempdir(), "test_batch_rpd")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  result <- bfhllm_spc_suggestions_batch(
    contexts,
    cache_dir = tmp,
    use_cache = FALSE
  )

  expect_true(result$rpd_exhausted)
  expect_equal(result$from_api, 0L)
  expect_equal(length(result$failed), 3L)
})

test_that("bfhllm_spc_suggestions_batch handles API returning NULL", {
  contexts <- make_test_contexts(2)

  mock_chat <- function(prompt, ...) {
    NULL
  }

  mock_status <- function() {
    list(rpd_remaining = 100L, enabled = TRUE)
  }

  tmp <- file.path(tempdir(), "test_batch_null")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_chat)
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_rate_limit_status", mock_status)

  result <- bfhllm_spc_suggestions_batch(
    contexts,
    cache_dir = tmp,
    use_cache = FALSE
  )

  # Alle keys skal vaere i failed
  expect_equal(length(result$failed), 2L)
  expect_equal(result$from_api, 0L)
})

test_that("bfhllm_spc_suggestions_batch rejects invalid input", {
  expect_error(bfhllm_spc_suggestions_batch(list()), "non-empty named list")
  expect_error(bfhllm_spc_suggestions_batch(NULL), "non-empty named list")
})
