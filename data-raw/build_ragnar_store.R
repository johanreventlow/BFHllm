# build_ragnar_store.R
# Builds Ragnar knowledge store from SPC methodology documentation
# Run during package installation or manually to rebuild store
#
# Requirements:
# - GOOGLE_API_KEY environment variable set
# - ragnar package installed
# - inst/spc_knowledge/*.md files present

# Load required packages -------------------------------------------------------

if (!requireNamespace("ragnar", quietly = TRUE)) {
  stop("ragnar package not installed. Install with: install.packages('ragnar')")
}

if (!requireNamespace("fs", quietly = TRUE)) {
  stop("fs package not installed. Install with: install.packages('fs')")
}

library(ragnar)
library(fs)

# Configuration ----------------------------------------------------------------

# Paths (relative to package root)
store_path <- "inst/ragnar_store"
docs_path <- "inst/spc_knowledge"

# Chunking parameters (Ragnar defaults)
chunk_size <- 1600  # ~1600 characters per chunk
chunk_overlap <- 200  # Overlap for context continuity

# Validation -------------------------------------------------------------------

cat("\n=== Ragnar Knowledge Store Build ===\n\n")

# Check 1: Google/Gemini API key (Ragnar uses GEMINI_API_KEY)
api_key <- Sys.getenv("GEMINI_API_KEY")
if (api_key == "") {
  # Fallback to GOOGLE_API_KEY for backwards compatibility
  api_key <- Sys.getenv("GOOGLE_API_KEY")
  if (api_key != "" && api_key != "your_api_key_here") {
    # Set GEMINI_API_KEY from GOOGLE_API_KEY
    Sys.setenv(GEMINI_API_KEY = api_key)
    cat("✓ Using GOOGLE_API_KEY as GEMINI_API_KEY\n")
  }
}

if (api_key == "" || api_key == "your_api_key_here") {
  stop(
    "GEMINI_API_KEY or GOOGLE_API_KEY environment variable not set.\n",
    "Cannot build knowledge store without API key.\n\n",
    "Setup:\n",
    "1. Get API key: https://makersuite.google.com/app/apikey\n",
    "2. Set in .Renviron: GEMINI_API_KEY=your_actual_key\n",
    "   (or GOOGLE_API_KEY for backwards compatibility)\n",
    "3. Restart R session\n",
    "4. Rerun this script\n"
  )
}

cat("✓ API key found\n")

# Check 2: Documentation directory exists
if (!dir.exists(docs_path)) {
  stop(
    "Documentation directory not found: ", docs_path, "\n",
    "Expected to find SPC methodology markdown files.\n",
    "Ensure inst/spc_knowledge/ exists with *.md files.\n"
  )
}

cat("✓ Documentation directory found:", docs_path, "\n")

# Check 3: Markdown files present
md_files <- fs::dir_ls(docs_path, glob = "*.md")
if (length(md_files) == 0) {
  stop(
    "No markdown files found in ", docs_path, "\n",
    "Expected *.md files with SPC methodology documentation.\n"
  )
}

cat("✓ Found", length(md_files), "documentation files\n\n")

# Initialize Ragnar Store ------------------------------------------------------

cat("Initializing Ragnar store with Google Gemini embeddings...\n")

tryCatch(
  {
    # Create store with Google Gemini embeddings
    store <- ragnar::ragnar_store_create(
      location = store_path,
      embed = ragnar::embed_google_gemini(
        model = "gemini-embedding-001",
        api_key = api_key
      ),
      overwrite = TRUE,  # Overwrite if exists
      name = "spc_knowledge",
      title = "SPC Methodology Knowledge Base"
    )

    cat("✓ Ragnar store initialized\n")
  },
  error = function(e) {
    stop(
      "Failed to initialize Ragnar store:\n",
      e$message, "\n\n",
      "Possible causes:\n",
      "- Invalid API key (GEMINI_API_KEY or GOOGLE_API_KEY)\n",
      "- Network connectivity issues\n",
      "- API rate limit exceeded\n",
      "- Insufficient disk space at: ", store_path, "\n"
    )
  }
)

# Ingest Documents -------------------------------------------------------------

cat("\nIngesting SPC methodology documentation...\n")
cat("  Chunk size:", chunk_size, "characters\n")
cat("  Files to process:", length(md_files), "\n\n")

tryCatch(
  {
    # Ingest all markdown files at once using high-level API
    ragnar:::ragnar_store_ingest(
      store = store,
      paths = as.character(md_files),
      target_size = chunk_size,
      target_overlap = chunk_overlap / chunk_size  # Convert to proportion
    )

    cat("✓ All documents ingested successfully\n")
    doc_count <- length(md_files)
  },
  error = function(e) {
    stop(
      "Failed to ingest documents:\n",
      e$message, "\n\n",
      "Check:\n",
      "- Markdown files are valid\n",
      "- API key has sufficient quota\n",
      "- Network connectivity\n"
    )
  }
)

# Build Search Index -----------------------------------------------------------

cat("\nBuilding search index for BM25 functionality...\n")

tryCatch(
  {
    ragnar::ragnar_store_build_index(store = store)
    cat("✓ Search index built successfully\n")
  },
  error = function(e) {
    stop(
      "Failed to build search index:\n",
      e$message, "\n\n",
      "BM25 search may not work without index.\n"
    )
  }
)

# Completion -------------------------------------------------------------------

cat("=== Knowledge Store Build Complete ===\n\n")
cat("Store location:", normalizePath(store_path, mustWork = FALSE), "\n")
cat("Documents indexed:", doc_count, "\n")
cat("Source files:\n")
for (file in md_files) {
  cat("  -", fs::path_file(file), "\n")
}
cat("\nThe knowledge store is ready for use with RAG-enhanced AI suggestions.\n")
