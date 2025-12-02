# basic-chat.R
# Basic LLM Chat Example with BFHllm

# Load library
library(BFHllm)

# 1. SETUP =====================================================================

# Check if setup is complete (API key, provider available)
if (!bfhllm_chat_available()) {
  stop(
    "BFHllm chat not available. Please set GOOGLE_API_KEY or GEMINI_API_KEY ",
    "in your .Renviron file and restart R."
  )
}

# 2. BASIC CHAT ================================================================

# Simple chat call
response <- bfhllm_chat(
  prompt = "Explain statistical process control in 2 sentences",
  max_chars = 200
)

cat("Response:\n")
cat(response, "\n\n")

# 3. CONFIGURATION =============================================================

# Configure BFHllm (optional - uses sensible defaults)
bfhllm_configure(
  provider = "gemini",
  model = "gemini-2.5-flash-lite",
  timeout_seconds = 10,
  max_response_chars = 350
)

# Get current config
config <- bfhllm_get_config()
cat("Current configuration:\n")
print(config)

# 4. WITH CACHING ==============================================================

# Create cache for repeated queries
cache <- bfhllm_cache_create(ttl_seconds = 3600) # 1 hour TTL

# First call (cache miss - hits API)
response1 <- bfhllm_chat(
  prompt = "What is a run chart?",
  cache = cache
)

cat("\nFirst call (cache miss):\n")
cat(response1, "\n\n")

# Second call (cache hit - no API call)
response2 <- bfhllm_chat(
  prompt = "What is a run chart?",
  cache = cache
)

cat("Second call (cache hit):\n")
cat(response2, "\n\n")

# Check cache stats
stats <- cache$stats()
cat("Cache stats:\n")
cat("  Hits:", stats$hits, "\n")
cat("  Misses:", stats$misses, "\n")
cat("  Size:", stats$size, "entries\n")

# 5. PROMPT UTILITIES ==========================================================

# Build structured prompt
prompt <- bfhllm_create_structured_prompt(
  question = "How do I interpret an SPC chart?",
  context = "24 data points, no special cause variation detected",
  system = "You are an SPC methodology expert",
  format = "Respond in Danish, max 3 sentences"
)

response <- bfhllm_chat(prompt = prompt, max_chars = 300)

cat("\nStructured prompt response:\n")
cat(response, "\n\n")

# Template interpolation
template <- "Explain {{concept}} in the context of {{field}}"
data <- list(concept = "centerline", field = "SPC charts")
prompt <- bfhllm_interpolate(template, data)

cat("Interpolated prompt:\n")
cat(prompt, "\n")

# 6. CIRCUIT BREAKER ===========================================================

# Check circuit breaker status (protects against API failures)
status <- bfhllm_circuit_breaker_status()
cat("\nCircuit breaker status:\n")
print(status)

# Reset if needed (e.g., after API is back online)
# bfhllm_circuit_breaker_reset()
