# bfhcharts-integration.R
# BFHcharts + BFHllm Standalone Integration Example
#
# This example demonstrates using BFHllm with BFHcharts for SPC chart analysis
# WITHOUT requiring SPCify. Shows standalone usage for other R packages/projects.

# Load libraries
library(BFHllm)

# Note: This example requires BFHcharts for SPC visualization
# Install with: remotes::install_github("johanreventlow/BFHcharts")
if (!requireNamespace("BFHcharts", quietly = TRUE)) {
  stop(
    "This example requires BFHcharts. Install with:\n",
    "  remotes::install_github('johanreventlow/BFHcharts')"
  )
}

library(BFHcharts)

# 1. SETUP =====================================================================

# Check if BFHllm is available
if (!bfhllm_chat_available()) {
  stop(
    "BFHllm not available. Set GOOGLE_API_KEY or GEMINI_API_KEY in .Renviron ",
    "and restart R."
  )
}

cat("BFHllm + BFHcharts Standalone Integration\n")
cat("==========================================\n\n")

# 2. CREATE SPC DATA ===========================================================

# Example: Hospital waiting times (days)
set.seed(42)
dates <- seq(as.Date("2023-01-01"), as.Date("2024-12-01"), by = "month")

# Simulate improvement trend (baseline → intervention)
waiting_times <- c(
  rnorm(12, mean = 45, sd = 8),  # 2023 baseline
  rnorm(12, mean = 32, sd = 6)   # 2024 improvement
)

spc_data <- data.frame(
  month = dates,
  waiting_time = pmax(waiting_times, 10)  # Min 10 days
)

cat("SPC Data Preview:\n")
print(head(spc_data))
cat("\n")

# 3. CREATE SPC CHART WITH BFHCHARTS ===========================================

# Use BFHcharts to create run chart
# Note: bfh_qic() uses NSE (non-standard evaluation) for column names
bfh_result <- BFHcharts::bfh_qic(
  data = spc_data,
  x = month,              # Bare column name (NSE like dplyr)
  y = waiting_time,       # Bare column name (NSE like dplyr)
  chart_type = "run",
  y_axis_unit = "time",   # Y-axis unit type (count|percent|rate|time)
  target_value = 30       # Optional target line
)

cat("BFHcharts result created successfully\n")
cat("  Chart type:", bfh_result$config$chart_type, "\n")
cat("  Data points:", nrow(bfh_result$qic_data), "\n\n")

# 4. EXTRACT METADATA FOR BFHLLM ===============================================

# Extract SPC statistics from BFHcharts summary (Danish column names)
summary_stats <- bfh_result$summary

cat("Extracted SPC Statistics:\n")
cat("  Centerline:", round(summary_stats$centerlinje, 1), "\n")
cat("  Longest run:", summary_stats$længste_løb, "/", summary_stats$længste_løb_max, "\n")
cat("  Crossings:", summary_stats$antal_kryds, "/", summary_stats$antal_kryds_min, "\n")
cat("  Runs signal:", summary_stats$løbelængde_signal, "\n\n")

# Build metadata structure for BFHllm
# Note: BFHllm uses English metadata keys
spc_result <- list(
  metadata = list(
    chart_type = bfh_result$config$chart_type,
    n_points = nrow(bfh_result$qic_data),
    signals_detected = sum(summary_stats$løbelængde_signal, summary_stats$sigma_signal, na.rm = TRUE),
    anhoej_rules = list(
      longest_run = summary_stats$længste_løb,
      n_crossings = summary_stats$antal_kryds,
      n_crossings_min = summary_stats$antal_kryds_min
    )
  ),
  qic_data = bfh_result$qic_data
)

# 5. DEFINE CONTEXT FOR AI SUGGESTION ==========================================

context <- list(
  data_definition = "Ventetid til operation (dage)",
  chart_title = "Ventetid ortopædkirurgi 2023-2024",
  y_axis_unit = "time",  # Matches BFHcharts y_axis_unit parameter
  target_value = 30      # Target: max 30 days waiting time
)

# 6. GENERATE AI SUGGESTION (WITH RAG) =========================================

cat("Generating AI improvement suggestion with RAG...\n")

suggestion_rag <- bfhllm_spc_suggestion(
  spc_result = spc_result,
  context = context,
  max_chars = 350,
  use_rag = TRUE  # Use SPC knowledge base
)

cat("\n")
cat("AI Suggestion (RAG-enhanced):\n")
cat("=============================\n")
cat(suggestion_rag, "\n\n")

# 7. GENERATE AI SUGGESTION (WITHOUT RAG) ======================================

cat("Generating AI suggestion without RAG...\n")

suggestion_no_rag <- bfhllm_spc_suggestion(
  spc_result = spc_result,
  context = context,
  max_chars = 350,
  use_rag = FALSE  # No knowledge base
)

cat("\n")
cat("AI Suggestion (without RAG):\n")
cat("============================\n")
cat(suggestion_no_rag, "\n\n")

# 8. WITH CACHING FOR PERFORMANCE ==============================================

cat("Testing cache performance...\n")

# Create cache
cache <- bfhllm_cache_create(ttl_seconds = 3600)

# First call (cache miss)
start_time <- Sys.time()
suggestion1 <- bfhllm_spc_suggestion(
  spc_result = spc_result,
  context = context,
  cache = cache
)
time1 <- difftime(Sys.time(), start_time, units = "secs")

cat("First call (cache miss):", round(time1, 2), "seconds\n")

# Second call (cache hit - much faster)
start_time <- Sys.time()
suggestion2 <- bfhllm_spc_suggestion(
  spc_result = spc_result,
  context = context,
  cache = cache
)
time2 <- difftime(Sys.time(), start_time, units = "secs")

cat("Second call (cache hit):", round(time2, 2), "seconds\n")
cat("Cache speedup:", round(as.numeric(time1) / as.numeric(time2), 1), "x\n\n")

# Check cache stats
stats <- cache$stats()
cat("Cache Statistics:\n")
cat("  Hits:", stats$hits, "\n")
cat("  Misses:", stats$misses, "\n")
cat("  Size:", stats$size, "entries\n\n")

# 9. CHART TYPE MAPPING ========================================================

cat("Chart Type Mapping (English -> Danish):\n")
cat("=======================================\n")

chart_types <- c("run", "p", "c", "i", "xbar")
for (ct in chart_types) {
  danish_name <- bfhllm_map_chart_type_danish(ct)
  cat("  ", ct, "->", danish_name, "\n")
}

cat("\n")

# 10. SUMMARY ==================================================================

cat("Summary:\n")
cat("========\n")
cat("This example demonstrates:\n")
cat("  ✓ Creating SPC charts with BFHcharts\n")
cat("  ✓ Extracting metadata with bfh_extract_spc_stats()\n")
cat("  ✓ Generating AI suggestions with BFHllm\n")
cat("  ✓ RAG-enhanced vs non-RAG comparison\n")
cat("  ✓ Caching for performance\n")
cat("  ✓ Standalone usage (no SPCify dependency)\n")
cat("\n")
cat("Use case: Integrate BFHllm into your R package/Shiny app\n")
cat("that uses BFHcharts for SPC visualization.\n")
