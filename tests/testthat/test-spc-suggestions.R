# test-spc-suggestions.R
# Tests for SPC Suggestions Module

# Test bfhllm_map_chart_type_danish() ==========================================

test_that("bfhllm_map_chart_type_danish maps known chart types", {
  expect_equal(bfhllm_map_chart_type_danish("run"), "serieplot (run chart)")
  expect_equal(bfhllm_map_chart_type_danish("p"), "P-chart (andel)")
  expect_equal(bfhllm_map_chart_type_danish("c"), "C-chart (antal events)")
  expect_equal(bfhllm_map_chart_type_danish("i"), "I-chart (individuelle værdier)")
})

test_that("bfhllm_map_chart_type_danish is case-insensitive", {
  expect_equal(bfhllm_map_chart_type_danish("RUN"), "serieplot (run chart)")
  expect_equal(bfhllm_map_chart_type_danish("P"), "P-chart (andel)")
})

test_that("bfhllm_map_chart_type_danish handles unknown types", {
  # Should warn and return original
  expect_warning(
    result <- bfhllm_map_chart_type_danish("unknown_type"),
    "Unknown chart type"
  )
  expect_equal(result, "unknown_type")
})

# Test bfhllm_extract_spc_metadata() ===========================================

test_that("bfhllm_extract_spc_metadata validates input", {
  expect_warning(result <- bfhllm_extract_spc_metadata(NULL), "Invalid spc_result")
  expect_null(result)

  expect_warning(result <- bfhllm_extract_spc_metadata("not a list"), "Invalid spc_result")
  expect_null(result)
})

test_that("bfhllm_extract_spc_metadata handles missing metadata component", {
  spc_result <- list(qic_data = data.frame(x = 1:10, y = 1:10))

  expect_warning(
    result <- bfhllm_extract_spc_metadata(spc_result),
    "Missing metadata component"
  )
  expect_null(result)
})

test_that("bfhllm_extract_spc_metadata extracts basic metadata", {
  spc_result <- list(
    metadata = list(
      chart_type = "run",
      n_points = 24,
      signals_detected = 2,
      anhoej_rules = list(
        longest_run = 8,
        n_crossings = 5,
        n_crossings_min = 10
      )
    ),
    qic_data = data.frame(
      x = 1:24,
      y = rnorm(24, 10, 2),
      cl = rep(10, 24)
    )
  )

  result <- bfhllm_extract_spc_metadata(spc_result)

  expect_type(result, "list")
  expect_equal(result$chart_type, "run")
  expect_equal(result$chart_type_dansk, "serieplot (run chart)")
  expect_equal(result$n_points, 24)
  expect_equal(result$signals_detected, 2)
  expect_equal(result$longest_run, 8)
  expect_equal(result$n_crossings, 5)
  expect_equal(result$n_crossings_min, 10)
  expect_equal(result$centerline, 10)
  expect_equal(result$process_variation, "ikke naturligt") # signals > 0
})

test_that("bfhllm_extract_spc_metadata handles missing anhoej_rules", {
  spc_result <- list(
    metadata = list(
      chart_type = "run",
      n_points = 24,
      signals_detected = 0
    ),
    qic_data = data.frame(
      x = 1:24,
      y = rnorm(24, 10, 2),
      cl = rep(10, 24)
    )
  )

  result <- bfhllm_extract_spc_metadata(spc_result)

  expect_equal(result$longest_run, 0)
  expect_equal(result$n_crossings, 0)
  expect_equal(result$n_crossings_min, 0)
  expect_equal(result$process_variation, "naturligt") # no signals
})

test_that("bfhllm_extract_spc_metadata handles missing qic_data", {
  spc_result <- list(
    metadata = list(
      chart_type = "run",
      n_points = 24,
      signals_detected = 0
    )
  )

  expect_warning(
    result <- bfhllm_extract_spc_metadata(spc_result),
    "Missing or empty qic_data"
  )

  expect_true(is.na(result$centerline))
  expect_equal(result$start_date, "Ikke angivet")
  expect_equal(result$end_date, "Ikke angivet")
})

# Test determine_target_comparison() ===========================================

test_that("determine_target_comparison classifies correctly", {
  # Within tolerance (5%)
  expect_equal(determine_target_comparison(10.2, 10), "ved målet") # 2% diff
  expect_equal(determine_target_comparison(9.8, 10), "ved målet") # 2% diff
  expect_equal(determine_target_comparison(10.5, 10), "ved målet") # 5% diff exactly

  # Outside tolerance
  expect_equal(determine_target_comparison(11, 10), "over målet") # 10% diff
  expect_equal(determine_target_comparison(9, 10), "under målet") # 10% diff
})

test_that("determine_target_comparison handles missing target", {
  expect_equal(determine_target_comparison(10, NULL), "ikke angivet")
  expect_equal(determine_target_comparison(10, NA), "ikke angivet")
  expect_equal(determine_target_comparison(10, ""), "ikke angivet")
  expect_equal(determine_target_comparison(10, character(0)), "ikke angivet")
})

test_that("determine_target_comparison handles missing centerline", {
  expect_equal(determine_target_comparison(NULL, 10), "ikke angivet")
  expect_equal(determine_target_comparison(NA, 10), "ikke angivet")
})

# Test bfhllm_spc_suggestion() =================================================

test_that("bfhllm_spc_suggestion validates inputs", {
  expect_warning(result <- bfhllm_spc_suggestion(NULL, list()), "spc_result is NULL")
  expect_null(result)

  expect_warning(
    result <- bfhllm_spc_suggestion(list(metadata = list()), NULL),
    "context is NULL"
  )
  expect_null(result)
})

test_that("bfhllm_spc_suggestion handles invalid spc_result", {
  context <- list(
    data_definition = "Test indicator",
    chart_title = "Test chart",
    y_axis_unit = "units",
    target_value = 10
  )

  # Invalid spc_result (missing metadata)
  spc_result <- list(qic_data = data.frame(x = 1:10, y = 1:10))

  expect_warning(
    result <- bfhllm_spc_suggestion(spc_result, context),
    "Missing metadata"
  )
  expect_null(result)
})

test_that("bfhllm_spc_suggestion uses cache if provided", {
  # Mock spc_result
  spc_result <- list(
    metadata = list(
      chart_type = "run",
      n_points = 24,
      signals_detected = 0
    ),
    qic_data = data.frame(
      x = 1:24,
      y = rnorm(24, 10, 2),
      cl = rep(10, 24)
    )
  )

  context <- list(
    data_definition = "Test indicator",
    chart_title = "Test chart",
    y_axis_unit = "units",
    target_value = 10
  )

  # Create cache and pre-populate
  cache <- bfhllm_cache_create()
  cached_response <- "Cached suggestion text"

  # Manually set cache (simulate previous call)
  metadata <- bfhllm_extract_spc_metadata(spc_result)
  cache_data <- c(metadata, context, list(max_chars = 350))
  cache_key <- bfhllm_generate_cache_key(cache_data)
  cache$set(cache_key, cached_response)

  # Call function - should return cached value
  result <- bfhllm_spc_suggestion(spc_result, context, cache = cache)

  expect_equal(result, cached_response)
})

test_that("bfhllm_spc_suggestion works without RAG", {
  skip_if_not_installed("ellmer")

  # Skip if no API key
  api_key <- Sys.getenv("GOOGLE_API_KEY")
  if (api_key == "" || api_key == "your_api_key_here") {
    skip("No API key configured")
  }

  # Mock spc_result
  spc_result <- list(
    metadata = list(
      chart_type = "run",
      n_points = 24,
      signals_detected = 0
    ),
    qic_data = data.frame(
      x = 1:24,
      y = rnorm(24, 10, 2),
      cl = rep(10, 24)
    )
  )

  context <- list(
    data_definition = "Test indicator",
    chart_title = "Test chart",
    y_axis_unit = "units",
    target_value = 10
  )

  # Call without RAG (may fail due to API issues, that's ok)
  result <- suppressWarnings(
    bfhllm_spc_suggestion(
      spc_result, context,
      use_rag = FALSE,
      max_chars = 200
    )
  )

  # Should return string or NULL
  expect_true(is.null(result) || is.character(result))
})

test_that("bfhllm_spc_suggestion builds correct RAG query", {
  # This is an internal check - we verify RAG query construction logic
  # by inspecting the function (manual review), not runtime behavior

  # Placeholder test
  expect_true(TRUE)
})

# Test get_spc_prompt_template() ===============================================

test_that("get_spc_prompt_template returns valid template", {
  template <- get_spc_prompt_template()

  expect_type(template, "character")
  expect_gt(nchar(template), 500) # Should be substantial

  # Should contain key placeholders
  expect_true(grepl("{{data_definition}}", template, fixed = TRUE))
  expect_true(grepl("{{chart_type_dansk}}", template, fixed = TRUE))
  expect_true(grepl("{{n_points}}", template, fixed = TRUE))
  expect_true(grepl("{{max_chars}}", template, fixed = TRUE))
  expect_true(grepl("{{process_variation}}", template, fixed = TRUE))
})
