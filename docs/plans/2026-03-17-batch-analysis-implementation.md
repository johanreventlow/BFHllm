# Batch SPC Analysis Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Batch multiple SPC analysis requests into single Gemini API calls with file-based caching, reducing API usage by ~96% for large runs.

**Architecture:** BFHllm gets a new `bfhllm_spc_suggestions_batch()` function that groups N contexts into batches of 25, builds one JSON-output prompt per batch, and caches results on disk. BFHddl's pipeline is refactored to three passes: chart generation, batch analysis, PDF export.

**Tech Stack:** R, BFHllm (ellmer/Gemini), BFHddl (pipeline), digest (hashing), jsonlite (JSON parsing)

**Issues:** BFHllm#8, BFHddl#11

**Design docs:**
- `BFHllm/docs/plans/2026-03-17-batch-analysis-design.md`
- `BFHddl/docs/plans/2026-03-17-batch-analysis-pipeline-design.md`

---

## Task 1: BFHllm — Fil-cache modul

**Files:**
- Create: `R/cache-file.R`
- Test: `tests/testthat/test-cache-file.R`

**Step 1: Write failing tests for file cache**

```r
# tests/testthat/test-cache-file.R

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

  # Opret og gem
  cache1 <- bfhllm_file_cache_create(cache_dir = tmp)
  cache1$set("persistent_key", "persistent_value")

  # Ny instans, samme mappe
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
```

**Step 2: Run tests to verify they fail**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-cache-file.R')"`
Expected: FAIL — `bfhllm_file_cache_create` not found

**Step 3: Implement file cache**

```r
# R/cache-file.R

#' Opret fil-baseret cache
#'
#' Opretter en cache der gemmer data i en .rds-fil på disk.
#' Cachen overlever R-sessions og kan deles mellem kørsler.
#'
#' @param cache_dir Character, sti til cache-mappe
#' @return Liste med get/set/has/clear/stats funktioner
#' @export
bfhllm_file_cache_create <- function(cache_dir) {
  # Opret mappe hvis den ikke eksisterer
  cache_path <- file.path(cache_dir, ".bfhllm_cache")
  if (!dir.exists(cache_path)) {
    dir.create(cache_path, recursive = TRUE)
  }

  index_file <- file.path(cache_path, "cache_index.rds")

  # Indlæs eksisterende index eller opret tom

  load_index <- function() {
    if (file.exists(index_file)) {
      readRDS(index_file)
    } else {
      list()
    }
  }

  save_index <- function(index) {
    saveRDS(index, index_file)
  }

  list(
    get = function(key) {
      index <- load_index()
      entry <- index[[key]]
      if (is.null(entry)) return(NULL)
      entry$value
    },

    set = function(key, value) {
      index <- load_index()
      index[[key]] <- list(
        value = value,
        timestamp = Sys.time()
      )
      save_index(index)
      invisible(value)
    },

    has = function(key) {
      index <- load_index()
      key %in% names(index)
    },

    clear = function() {
      save_index(list())
      invisible(TRUE)
    },

    stats = function() {
      index <- load_index()
      list(
        entries = length(index),
        cache_dir = cache_path
      )
    }
  )
}
```

**Step 4: Run tests to verify they pass**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-cache-file.R')"`
Expected: All 6 tests PASS

**Step 5: Commit**

```bash
git add R/cache-file.R tests/testthat/test-cache-file.R
git commit -m "feat(cache): tilføj fil-baseret cache modul

Ny bfhllm_file_cache_create() der gemmer analyse-resultater
på disk via .rds-filer. Overlever R-sessions.

Ref: #8"
```

---

## Task 2: BFHllm — Batch prompt-builder og JSON-parser

**Files:**
- Create: `R/batch.R`
- Test: `tests/testthat/test-batch.R`

**Step 1: Write failing tests for prompt building and parsing**

```r
# tests/testthat/test-batch.R

test_that("build_batch_prompt creates valid prompt with multiple contexts", {
  contexts <- list(
    "diagram_1" = list(
      spc_result = list(metadata = list(
        chart_type = "run", n_points = 100,
        signals_detected = 1L,
        anhoej_rules = list(longest_run = 9, n_crossings = 3, n_crossings_min = 5)
      )),
      llm_context = list(
        data_definition = "Andel patienter",
        chart_title = "Indikator 1",
        y_axis_unit = "%",
        target_value = 95,
        signal_examples = "Serielængde 9"
      )
    ),
    "diagram_2" = list(
      spc_result = list(metadata = list(
        chart_type = "run", n_points = 50,
        signals_detected = 0L,
        anhoej_rules = list(longest_run = 5, n_crossings = 8, n_crossings_min = 6)
      )),
      llm_context = list(
        data_definition = "Ventetid i timer",
        chart_title = "Indikator 2",
        y_axis_unit = "timer",
        target_value = 4,
        signal_examples = ""
      )
    )
  )

  prompt <- build_batch_prompt(contexts, min_chars = 300, max_chars = 375)
  expect_type(prompt, "character")
  expect_true(nchar(prompt) > 0)
  # Prompt skal indeholde begge diagram-keys
  expect_true(grepl("diagram_1", prompt))
  expect_true(grepl("diagram_2", prompt))
  # Prompt skal bede om JSON-output
  expect_true(grepl("JSON", prompt))
})

test_that("parse_batch_response parses valid JSON", {
  keys <- c("diagram_1", "diagram_2")
  json_response <- '{"1": "Analyse for diagram 1 her.", "2": "Analyse for diagram 2 her."}'

  result <- parse_batch_response(json_response, keys)
  expect_type(result, "list")
  expect_equal(length(result), 2)
  expect_equal(names(result), c("diagram_1", "diagram_2"))
  expect_true(nchar(result[["diagram_1"]]) > 0)
  expect_true(nchar(result[["diagram_2"]]) > 0)
})

test_that("parse_batch_response handles partial JSON gracefully", {
  keys <- c("diagram_1", "diagram_2", "diagram_3")
  # Kun 2 af 3 i svaret
  json_response <- '{"1": "Analyse 1.", "2": "Analyse 2."}'

  result <- parse_batch_response(json_response, keys)
  expect_equal(length(result), 3)
  expect_true(nchar(result[["diagram_1"]]) > 0)
  expect_true(nchar(result[["diagram_2"]]) > 0)
  expect_null(result[["diagram_3"]])
})

test_that("parse_batch_response handles invalid JSON gracefully", {
  keys <- c("diagram_1")
  json_response <- "Dette er ikke valid JSON"

  result <- parse_batch_response(json_response, keys)
  expect_equal(length(result), 1)
  expect_null(result[["diagram_1"]])
})

test_that("parse_batch_response extracts JSON from surrounding text", {
  keys <- c("diagram_1", "diagram_2")
  # Gemini svarer nogle gange med tekst omkring JSON
  json_response <- 'Her er analyserne:\n{"1": "Analyse 1.", "2": "Analyse 2."}\nFærdig.'

  result <- parse_batch_response(json_response, keys)
  expect_equal(length(result), 2)
  expect_true(nchar(result[["diagram_1"]]) > 0)
})
```

**Step 2: Run tests to verify they fail**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-batch.R')"`
Expected: FAIL — `build_batch_prompt` not found

**Step 3: Implement batch prompt builder and parser**

```r
# R/batch.R

#' Byg batch-prompt for multiple SPC-analyser
#'
#' Konstruerer ét samlet prompt der beder Gemini generere
#' N individuelle analyser og returnere dem som JSON.
#'
#' @param contexts Named list: diagram_key -> list(spc_result, llm_context)
#' @param min_chars Integer, minimum tegn per analyse
#' @param max_chars Integer, maximum tegn per analyse
#' @return Character string, det samlede prompt
#' @keywords internal
build_batch_prompt <- function(contexts, min_chars = 300, max_chars = 375) {
  keys <- names(contexts)
  n <- length(keys)

  # Systembesked
  header <- sprintf(
    paste0(
      "Du er en SPC-ekspert der skriver korte, handlingsorienterede analyser ",
      "paa dansk for sundhedsprofessionelle.\n\n",
      "Generer en analyse for HVERT af de %d diagrammer herunder.\n",
      "Hver analyse skal vaere %d-%d tegn lang.\n",
      "Brug **fed skrift** til vigtigste anbefaling.\n\n",
      "Svar KUN med valid JSON i dette format:\n",
      "{\"1\": \"analyse for diagram 1\", \"2\": \"analyse for diagram 2\", ...}\n\n",
      "VIGTIGT: Returner KUN JSON, ingen anden tekst.\n\n",
      "---\n\n"
    ),
    n, min_chars, max_chars
  )

  # Byg kontekst per diagram
  diagram_sections <- vapply(seq_along(keys), function(idx) {
    key <- keys[[idx]]
    ctx <- contexts[[key]]
    meta <- ctx$spc_result$metadata
    llm <- ctx$llm_context

    sprintf(
      paste0(
        "Diagram %d (key: \"%s\"):\n",
        "- Chart type: %s\n",
        "- Antal datapunkter: %s\n",
        "- Signaler detekteret: %s\n",
        "- Longest run: %s\n",
        "- Krydsninger: %s (forventet minimum: %s)\n",
        "- Maalvaerdi: %s\n",
        "- Y-akse enhed: %s\n",
        "- Titel: %s\n",
        "- Definition: %s\n",
        "- Signal-fortolkning: %s\n"
      ),
      idx, key,
      meta$chart_type %||% "ukendt",
      meta$n_points %||% "ukendt",
      meta$signals_detected %||% 0L,
      meta$anhoej_rules$longest_run %||% "ukendt",
      meta$anhoej_rules$n_crossings %||% "ukendt",
      meta$anhoej_rules$n_crossings_min %||% "ukendt",
      llm$target_value %||% "ingen",
      llm$y_axis_unit %||% "ukendt",
      llm$chart_title %||% "ukendt",
      llm$data_definition %||% "ukendt",
      llm$signal_examples %||% "ingen signaler"
    )
  }, character(1))

  paste0(header, paste(diagram_sections, collapse = "\n"))
}


#' Parse batch JSON-response fra Gemini
#'
#' Ekstraherer individuelle analyser fra Gemini's JSON-svar
#' og mapper dem tilbage til diagram-keys.
#'
#' @param response Character string, rå response fra Gemini
#' @param keys Character vector, diagram-keys i samme rækkefølge som promptet
#' @return Named list: diagram_key -> analyse tekst (eller NULL hvis fejlet)
#' @keywords internal
parse_batch_response <- function(response, keys) {
  # Initialisér resultat med NULLs
  result <- stats::setNames(vector("list", length(keys)), keys)

  # Forsøg at ekstrahere JSON fra response
  parsed <- tryCatch({
    # Prøv direkte parsing først
    jsonlite::fromJSON(response, simplifyVector = FALSE)
  }, error = function(e) {
    # Prøv at finde JSON i teksten
    json_match <- regmatches(response, regexpr("\\{[^{}]*\\}", response))
    if (length(json_match) > 0) {
      tryCatch(
        jsonlite::fromJSON(json_match[[1]], simplifyVector = FALSE),
        error = function(e2) NULL
      )
    } else {
      NULL
    }
  })

  if (is.null(parsed)) return(result)

  # Map nummererede keys (1, 2, ...) til diagram_keys
  for (idx in seq_along(keys)) {
    idx_str <- as.character(idx)
    if (idx_str %in% names(parsed) && nchar(parsed[[idx_str]]) > 0) {
      result[[keys[[idx]]]] <- parsed[[idx_str]]
    }
  }

  result
}
```

**Step 4: Run tests to verify they pass**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-batch.R')"`
Expected: All 5 tests PASS

**Step 5: Commit**

```bash
git add R/batch.R tests/testthat/test-batch.R
git commit -m "feat(batch): tilføj batch prompt-builder og JSON-parser

Interne funktioner build_batch_prompt() og parse_batch_response()
til at samle N SPC-analyser i ét Gemini API-kald.

Ref: #8"
```

---

## Task 3: BFHllm — Hovedfunktion `bfhllm_spc_suggestions_batch()`

**Files:**
- Modify: `R/batch.R` (tilføj hovedfunktion)
- Modify: `tests/testthat/test-batch.R` (tilføj tests)

**Step 1: Write failing tests for batch function**

Tilføj til `tests/testthat/test-batch.R`:

```r
# --- Tests for bfhllm_spc_suggestions_batch() ---

# Hjælpefunktion til at lave test-kontekster
make_test_contexts <- function(n = 3) {
  contexts <- list()
  for (i in seq_len(n)) {
    key <- paste0("test_diagram_", i)
    contexts[[key]] <- list(
      spc_result = list(metadata = list(
        chart_type = "run",
        n_points = 100 + i,
        signals_detected = i %% 2L,
        anhoej_rules = list(longest_run = 5 + i, n_crossings = 3, n_crossings_min = 5)
      )),
      llm_context = list(
        data_definition = paste("Definition", i),
        chart_title = paste("Titel", i),
        y_axis_unit = "%",
        target_value = 90 + i,
        signal_examples = paste("Signal", i)
      )
    )
  }
  contexts
}

test_that("bfhllm_spc_suggestions_batch returns correct structure", {
  # Mock bfhllm_chat for at undgå rigtige API-kald
  mock_response <- '{"1": "Analyse en.", "2": "Analyse to.", "3": "Analyse tre."}'
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_response)

  contexts <- make_test_contexts(3)
  tmp <- file.path(tempdir(), "test_batch_1")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  result <- bfhllm_spc_suggestions_batch(
    contexts = contexts,
    batch_size = 25,
    use_cache = FALSE,
    cache_dir = tmp
  )

  expect_true(is.list(result))
  expect_true(all(c("analyses", "from_cache", "from_api", "failed", "rpd_exhausted") %in% names(result)))
  expect_equal(length(result$analyses), 3)
  expect_equal(result$from_api, 3L)
  expect_equal(result$from_cache, 0L)
  expect_false(result$rpd_exhausted)
})

test_that("bfhllm_spc_suggestions_batch uses file cache", {
  mock_response <- '{"1": "Cached analyse."}'
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_response)

  contexts <- make_test_contexts(1)
  tmp <- file.path(tempdir(), "test_batch_2")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # Første kald: fra API
  result1 <- bfhllm_spc_suggestions_batch(
    contexts = contexts, cache_dir = tmp, use_cache = TRUE
  )
  expect_equal(result1$from_api, 1L)
  expect_equal(result1$from_cache, 0L)

  # Andet kald: fra cache (mock bør ikke kaldes)
  call_count <- 0
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", function(...) {
    call_count <<- call_count + 1
    mock_response
  })

  result2 <- bfhllm_spc_suggestions_batch(
    contexts = contexts, cache_dir = tmp, use_cache = TRUE
  )
  expect_equal(result2$from_cache, 1L)
  expect_equal(result2$from_api, 0L)
})

test_that("bfhllm_spc_suggestions_batch respects force_refresh", {
  mock_response <- '{"1": "Ny analyse."}'
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", mock_response)

  contexts <- make_test_contexts(1)
  tmp <- file.path(tempdir(), "test_batch_3")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # Første kald
  bfhllm_spc_suggestions_batch(
    contexts = contexts, cache_dir = tmp, use_cache = TRUE
  )

  # Force refresh: bør kalde API igen
  result <- bfhllm_spc_suggestions_batch(
    contexts = contexts, cache_dir = tmp,
    use_cache = TRUE, force_refresh = TRUE
  )
  expect_equal(result$from_api, 1L)
  expect_equal(result$from_cache, 0L)
})

test_that("bfhllm_spc_suggestions_batch splits into batches", {
  # 5 kontekster, batch_size = 2 → 3 API-kald
  call_count <- 0
  mockery::stub(bfhllm_spc_suggestions_batch, "bfhllm_chat", function(...) {
    call_count <<- call_count + 1
    # Returner JSON for 2 (eller 1 for sidste batch)
    if (call_count <= 2) {
      '{"1": "A.", "2": "B."}'
    } else {
      '{"1": "C."}'
    }
  })

  contexts <- make_test_contexts(5)
  tmp <- file.path(tempdir(), "test_batch_4")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  result <- bfhllm_spc_suggestions_batch(
    contexts = contexts,
    batch_size = 2,
    use_cache = FALSE,
    cache_dir = tmp
  )
  expect_equal(result$from_api, 5L)
})
```

**Step 2: Run tests to verify they fail**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-batch.R')"`
Expected: New tests FAIL — `bfhllm_spc_suggestions_batch` not found

**Step 3: Implement the batch function**

Tilføj til `R/batch.R`:

```r
#' Batch-generer SPC-analyser
#'
#' Samler multiple SPC-analyse-forespørgsler i grupper og sender
#' ét Gemini API-kald per gruppe. Bruger fil-baseret cache.
#'
#' @param contexts Named list: diagram_key -> list(spc_result, llm_context)
#' @param batch_size Integer, antal analyser per API-kald (default: 25)
#' @param use_cache Logical, brug fil-baseret cache (default: TRUE)
#' @param cache_dir Character, cache-mappe (default: tempdir())
#' @param force_refresh Logical, ignorer cache (default: FALSE)
#' @param min_chars Integer, minimum tegn per analyse (default: 300)
#' @param max_chars Integer, maximum tegn per analyse (default: 375)
#' @return Liste med: analyses, from_cache, from_api, failed, rpd_exhausted
#' @export
bfhllm_spc_suggestions_batch <- function(
  contexts,
  batch_size = 25L,
  use_cache = TRUE,
  cache_dir = NULL,
  force_refresh = FALSE,
  min_chars = 300,
  max_chars = 375
) {
  if (is.null(cache_dir)) cache_dir <- tempdir()

  keys <- names(contexts)
  analyses <- stats::setNames(vector("list", length(keys)), keys)
  from_cache <- 0L
  from_api <- 0L
  failed <- character(0)
  rpd_exhausted <- FALSE

  # --- Cache lookup ---
  cache <- NULL
  keys_to_fetch <- keys

  if (use_cache && !force_refresh) {
    cache <- bfhllm_file_cache_create(cache_dir)

    keys_to_fetch <- character(0)
    for (key in keys) {
      cache_key <- bfhllm_generate_cache_key(contexts[[key]])
      cached_value <- cache$get(cache_key)
      if (!is.null(cached_value)) {
        analyses[[key]] <- cached_value
        from_cache <- from_cache + 1L
      } else {
        keys_to_fetch <- c(keys_to_fetch, key)
      }
    }
  }

  # Alt cached? Returner tidligt
  if (length(keys_to_fetch) == 0) {
    return(list(
      analyses = analyses,
      from_cache = from_cache,
      from_api = from_api,
      failed = failed,
      rpd_exhausted = rpd_exhausted
    ))
  }

  # --- Opdel i batches ---
  batch_indices <- split(
    seq_along(keys_to_fetch),
    ceiling(seq_along(keys_to_fetch) / batch_size)
  )

  # Opret cache til at gemme nye resultater
  if (is.null(cache) && use_cache) {
    cache <- bfhllm_file_cache_create(cache_dir)
  }

  for (batch_idx in seq_along(batch_indices)) {
    indices <- batch_indices[[batch_idx]]
    batch_keys <- keys_to_fetch[indices]
    batch_contexts <- contexts[batch_keys]

    # --- RPD check ---
    rpd_status <- tryCatch(
      bfhllm_rate_limit_status(),
      error = function(e) list(rpd_remaining = Inf, enabled = FALSE)
    )

    if (rpd_status$enabled && rpd_status$rpd_remaining < 1) {
      rpd_exhausted <- TRUE
      failed <- c(failed, keys_to_fetch[unlist(batch_indices[batch_idx:length(batch_indices)])])
      break
    }

    # --- Byg prompt og kald API ---
    prompt <- build_batch_prompt(batch_contexts, min_chars = min_chars, max_chars = max_chars)

    response <- tryCatch({
      bfhllm_chat(
        prompt = prompt,
        max_chars = NULL,
        validate = FALSE
      )
    }, error = function(e) {
      NULL
    })

    if (is.null(response)) {
      failed <- c(failed, batch_keys)
      next
    }

    # --- Parse response ---
    parsed <- parse_batch_response(response, batch_keys)

    for (key in batch_keys) {
      if (!is.null(parsed[[key]]) && nchar(parsed[[key]]) > 0) {
        analyses[[key]] <- parsed[[key]]
        from_api <- from_api + 1L

        # Gem i fil-cache
        if (use_cache && !is.null(cache)) {
          cache_key <- bfhllm_generate_cache_key(contexts[[key]])
          cache$set(cache_key, parsed[[key]])
        }
      } else {
        failed <- c(failed, key)
      }
    }
  }

  list(
    analyses = analyses,
    from_cache = from_cache,
    from_api = from_api,
    failed = failed,
    rpd_exhausted = rpd_exhausted
  )
}
```

**Step 4: Run tests to verify they pass**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-batch.R')"`
Expected: All tests PASS

**Step 5: Update NAMESPACE**

Run: `Rscript -e "devtools::document()"`
Verify: `bfhllm_spc_suggestions_batch` og `bfhllm_file_cache_create` er i NAMESPACE

**Step 6: Run full test suite**

Run: `Rscript -e "devtools::test()"`
Expected: All existing + new tests PASS

**Step 7: Commit**

```bash
git add R/batch.R tests/testthat/test-batch.R NAMESPACE man/
git commit -m "feat(batch): implementer bfhllm_spc_suggestions_batch()

Hovedfunktion der:
- Samler N kontekster i grupper á batch_size
- Tjekker fil-cache før API-kald
- Bygger batch-prompt med JSON-output
- Parser individuelle analyser fra response
- Returnerer rpd_exhausted ved daglig grænse

Ref: #8"
```

---

## Task 4: BFHllm — Tilføj jsonlite dependency

**Files:**
- Modify: `DESCRIPTION`

**Step 1: Add jsonlite to Imports**

I `DESCRIPTION`, tilføj `jsonlite` til Imports-listen (bruges til JSON-parsing i batch.R).

**Step 2: Run check**

Run: `Rscript -e "devtools::check()"`
Verify: Ingen nye warnings/errors

**Step 3: Commit**

```bash
git add DESCRIPTION
git commit -m "chore: tilføj jsonlite til Imports for batch JSON-parsing

Ref: #8"
```

---

## Task 5: BFHddl — Tre-pass pipeline refaktorering

**Files:**
- Modify: `R/pipeline.R:43-567` (run_pipeline funktion)
- Test: Manuelt via `source("run_spc_charts.R")` fra ddl-projektet

**Step 1: Tilføj nye parametre til run_pipeline()**

Tilføj `batch_analysis`, `force_refresh`, `analysis_batch_size` til funktionssignaturen ved linje 43.

```r
# Eksisterende parametre bevares, tilføj disse tre:
run_pipeline <- function(output_dir = NULL,
                         format = "png",
                         from_date = NULL,
                         to_date = NULL,
                         width_mm = 254,
                         height_mm = 152,
                         dpi = 300,
                         verbose = TRUE,
                         dry_run = FALSE,
                         debug = FALSE,
                         diagram_filter = NULL,
                         config_file = "config.yml",
                         batch_analysis = TRUE,
                         force_refresh = FALSE,
                         analysis_batch_size = 25L) {
```

**Step 2: Refaktorér Fase 5 — Chart-generering (Pass 1)**

Erstat den eksisterende for-loop (linje 339-567) med tre separate faser.

Pass 1 bevarer eksisterende data-load + chart-generering logik, men gemmer resultater i en `prepared` liste i stedet for at eksportere straks.

Nøgleændring: Efter chart_create_single() (linje 468), gem chart + kontekst + metadata i `prepared[[diagram_key]]`. Flyt eksport-koden (linje 500-558) ud af loopet.

**Step 3: Tilføj Fase 5b — Batch-analyse (Pass 2)**

Mellem Pass 1 og Pass 3, indsæt batch-analyse logik:
- Tjek om "pdf" er i format OG batch_analysis == TRUE OG BFHllm er tilgængelig
- Saml kontekster fra `prepared`
- Kald `BFHllm::bfhllm_spc_suggestions_batch()`
- Håndter `rpd_exhausted` med `readline()` prompt
- Log resultater med `cli::cli_alert_success()`

**Step 4: Tilføj Fase 5c — Eksport (Pass 3)**

Ny loop over `prepared` der:
- Indsætter batch-analyse i `pdf_metadata$analysis` (hvis tilgængelig)
- Kalder `bfh_export_pdf()` med `auto_analysis = is.null(analysis)`
- Kalder `bfh_export_png()` uændret for PNG

**Step 5: Test manuelt**

Fra ddl-projektet:
```r
source("run_spc_charts.R")
# Forventet: Tre-fase output med batch-analyser
```

**Step 6: Test backward compatibility**

```r
# batch_analysis = FALSE → single-pass (eksisterende adfærd)
run_pipeline(..., batch_analysis = FALSE)

# PNG-only → ingen batch-analyse
run_pipeline(..., format = "png")
```

**Step 7: Commit**

```bash
git add R/pipeline.R
git commit -m "feat(pipeline): refaktorér til tre-pass med batch-analyse

- Fase 5a: chart-generering med kontekst-samling
- Fase 5b: batch-analyse via BFHllm (ny)
- Fase 5c: eksport med pre-udfyldte analyser
- Nye parametre: batch_analysis, force_refresh, analysis_batch_size
- Interaktiv bruger-prompt ved RPD-loft
- Backward compatible: batch_analysis=FALSE → single-pass

Ref: #11"
```

---

## Task 6: BFHddl — Tilføj BFHllm som Suggests dependency

**Files:**
- Modify: `DESCRIPTION`

**Step 1: Tilføj BFHllm til Suggests**

```
Suggests:
  BFHllm (>= 0.1.1)
```

Og tilføj remote:
```
Remotes:
  johanreventlow/BFHcharts,
  johanreventlow/BFHllm
```

**Step 2: Commit**

```bash
git add DESCRIPTION
git commit -m "chore: tilføj BFHllm som Suggests dependency

Pipeline bruger BFHllm::bfhllm_spc_suggestions_batch() når tilgængelig.
Graceful degradation når BFHllm ikke er installeret.

Ref: #11"
```

---

## Task 7: Integration test — End-to-end

**Files:** Ingen nye filer, test via ddl-projektet

**Step 1: Test med cache (default)**

```r
# Fra ddl/
source("run_spc_charts.R")
# Forventet:
# - Fase 5a: charts genereret
# - Fase 5b: analyser fra API (første kørsel)
# - Fase 5c: PDFs eksporteret med AI-analyser
```

**Step 2: Test genkørsel (cache hit)**

```r
# Kør igen
source("run_spc_charts.R")
# Forventet:
# - Fase 5b: "X analyser fra cache, 0 sendes til API"
```

**Step 3: Test force_refresh**

```r
# Modificer run_spc_charts.R til at sende force_refresh = TRUE
# Forventet: alle analyser genereres på ny
```

**Step 4: Commit alle ændringer og push**

```bash
# BFHllm
cd BFHllm && git push

# BFHddl
cd BFHddl && git push
```

**Step 5: Luk GitHub issues**

Luk BFHllm#8 og BFHddl#11 med reference til commits.

---

## Opgaverækkefølge og afhængigheder

```
Task 1: Fil-cache modul (BFHllm)
  ↓
Task 2: Batch prompt + parser (BFHllm)
  ↓
Task 3: Hovedfunktion bfhllm_spc_suggestions_batch (BFHllm)
  ↓
Task 4: jsonlite dependency (BFHllm)
  ↓
Task 5: Tre-pass pipeline (BFHddl) ← afhænger af Task 1-4
  ↓
Task 6: BFHllm som Suggests (BFHddl)
  ↓
Task 7: Integration test (ddl)
```

**Tasks 1-4:** Kan implementeres og testes isoleret i BFHllm.
**Tasks 5-6:** Kræver at BFHllm er opdateret og installeret.
**Task 7:** End-to-end test i ddl-projektet.
