# cache-file.R
# Fil-baseret Cache for LLM Responses

#' Opret fil-baseret cache
#'
#' Opretter en cache der gemmer data i en .rds-fil paa disk.
#' Cachen overlever R-sessions og kan deles mellem koersler.
#'
#' @param cache_dir Character, sti til cache-mappe
#'
#' @return Liste med get/set/has/clear/stats funktioner:
#' \describe{
#'   \item{get(key)}{Hent vaerdi fra cache, eller NULL hvis ikke fundet}
#'   \item{set(key, value)}{Gem vaerdi i cache}
#'   \item{has(key)}{Returnerer TRUE/FALSE om key eksisterer}
#'   \item{clear()}{Fjern alle cache-entries}
#'   \item{stats()}{Returnerer cache-statistik}
#' }
#'
#' @details
#' Cachen bruger en enkelt RDS index-fil til at gemme alle entries.
#' Filen placeres i en `.bfhllm_cache` undermappe af `cache_dir`.
#'
#' Fordi data gemmes paa disk, overlever cachen R-sessions og kan
#' tilgaas af flere separate koersler der peger paa samme `cache_dir`.
#'
#' @examples
#' \dontrun{
#' # Opret cache i midlertidig mappe
#' cache <- bfhllm_file_cache_create(cache_dir = tempdir())
#'
#' # Gem og hent vaerdi
#' cache$set("key1", "analyse tekst")
#' cache$get("key1")  # "analyse tekst"
#'
#' # Tjek om key eksisterer
#' cache$has("key1")  # TRUE
#'
#' # Statistik
#' cache$stats()  # list(entries = 1L, cache_dir = "...")
#'
#' # Ryd cache
#' cache$clear()
#' }
#'
#' @export
bfhllm_file_cache_create <- function(cache_dir) {
  cache_path <- file.path(cache_dir, ".bfhllm_cache")
  if (!dir.exists(cache_path)) {
    dir.create(cache_path, recursive = TRUE)
  }

  index_file <- file.path(cache_path, "cache_index.rds")

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
        cache_dir = cache_dir
      )
    }
  )
}
