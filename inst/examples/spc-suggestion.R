# spc-suggestion.R
# SPC Improvement Suggestion Example with BFHllm

# Load libraries
library(BFHllm)

# Note: This example requires BFHcharts or qicharts2 for SPC result objects
# Install with: install.packages("qicharts2")
if (!requireNamespace("qicharts2", quietly = TRUE)) {
  stop("This example requires qicharts2. Install with: install.packages('qicharts2')")
}

library(qicharts2)

# 1. SETUP =====================================================================

# Check if setup is complete
if (!bfhllm_chat_available()) {
  stop(
    "BFHllm not available. Set GOOGLE_API_KEY or GEMINI_API_KEY in .Renviron ",
    "and restart R."
  )
}

# 2. CREATE SPC DATA ===========================================================

# Example: Monthly medication errors
set.seed(42)
dates <- seq(as.Date("2023-01-01"), as.Date("2024-12-01"), by = "month")
errors <- c(
  rpois(12, lambda = 45), # 2023 baseline
  rpois(12, lambda = 38) # 2024 improvement
)

spc_data <- data.frame(
  month = dates,
  errors = errors,
  administrations = rpois(24, lambda = 35000)
)

spc_data$error_rate <- (spc_data$errors / spc_data$administrations) * 1000

cat("SPC Data:\n")
print(head(spc_data))
cat("\n")

# 3. COMPUTE SPC CHART =========================================================

# Create P-chart (proportion chart)
qic_result <- qic(
  x = spc_data$month,
  y = spc_data$errors,
  n = spc_data$administrations,
  chart = "p",
  multiply = 1000, # Per 1000 administrations
  title = "Medicineringsfejl pr. 1000 administrationer",
  ylab = "Fejlrate (‰)",
  xlab = "Måned",
  return.data = TRUE
)

# Extract metadata structure for BFHllm
spc_result <- list(
  metadata = list(
    chart_type = "p",
    n_points = nrow(spc_data),
    signals_detected = sum(qic_result$signal, na.rm = TRUE),
    anhoej_rules = list(
      longest_run = max(rle(qic_result$y > qic_result$cl)$lengths, na.rm = TRUE),
      n_crossings = sum(diff(sign(qic_result$y - qic_result$cl)) != 0, na.rm = TRUE),
      n_crossings_min = floor(nrow(spc_data) / 2)
    )
  ),
  qic_data = qic_result
)

cat("SPC Metadata:\n")
cat("  Chart type:", spc_result$metadata$chart_type, "\n")
cat("  Data points:", spc_result$metadata$n_points, "\n")
cat("  Signals:", spc_result$metadata$signals_detected, "\n\n")

# 4. DEFINE CONTEXT ============================================================

context <- list(
  data_definition = "Medicineringsfejl pr. 1000 medicineringsadministrationer",
  chart_title = "Medicineringsfejl 2023-2024",
  y_axis_unit = "promille (‰)",
  target_value = 1.0 # Target: max 1 error per 1000 administrations
)

# 5. GENERATE SUGGESTION (WITH RAG) ============================================

cat("Generating AI suggestion with RAG...\n")

suggestion_rag <- bfhllm_spc_suggestion(
  spc_result = spc_result,
  context = context,
  max_chars = 350,
  use_rag = TRUE
)

cat("\nSuggestion (with RAG):\n")
cat(suggestion_rag, "\n\n")

# 6. GENERATE SUGGESTION (WITHOUT RAG) =========================================

cat("Generating AI suggestion without RAG...\n")

suggestion_no_rag <- bfhllm_spc_suggestion(
  spc_result = spc_result,
  context = context,
  max_chars = 350,
  use_rag = FALSE
)

cat("\nSuggestion (without RAG):\n")
cat(suggestion_no_rag, "\n\n")

# 7. WITH CACHING ==============================================================

# Create cache for performance
cache <- bfhllm_cache_create()

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
cat("Speedup:", round(as.numeric(time1) / as.numeric(time2), 1), "x\n\n")

# 8. METADATA EXTRACTION =======================================================

# Extract metadata directly
metadata <- bfhllm_extract_spc_metadata(spc_result)

cat("Extracted Metadata:\n")
cat("  Chart type (Danish):", metadata$chart_type_dansk, "\n")
cat("  Process variation:", metadata$process_variation, "\n")
cat("  Centerline:", metadata$centerline, "\n")
cat("  Period:", metadata$start_date, "to", metadata$end_date, "\n")

# 9. CHART TYPE MAPPING ========================================================

chart_types <- c("run", "p", "c", "i", "xbar")
danish_names <- sapply(chart_types, bfhllm_map_chart_type_danish)

cat("\nChart Type Mapping:\n")
for (i in seq_along(chart_types)) {
  cat("  ", chart_types[i], "->", danish_names[i], "\n")
}
