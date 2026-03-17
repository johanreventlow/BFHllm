# batch.R
# Batch SPC Analysis - Flere diagrammer i et enkelt LLM-kald

# INTERNAL FUNCTIONS ===========================================================

#' Byg batch-prompt for flere diagrammer
#'
#' Opretter en prompt der instruerer LLM til at generere analyser
#' for flere SPC-diagrammer i JSON-format.
#'
#' @param contexts Named list af kontekster (diagram_key -> list(spc_result, llm_context))
#' @param min_chars Integer, minimum tegn per analyse
#' @param max_chars Integer, maksimum tegn per analyse
#'
#' @return Character string med samlet prompt
#'
#' @keywords internal
build_batch_prompt <- function(contexts, min_chars, max_chars) {
  keys <- names(contexts)

  # Byg diagram-sektioner

  diagram_sections <- vapply(keys, function(key) {
    ctx <- contexts[[key]]
    meta <- ctx$spc_result$metadata
    llm <- ctx$llm_context

    # Udtræk metadata med sikre defaults
    chart_type <- meta$chart_type %||% "unknown"
    chart_type_dansk <- bfhllm_map_chart_type_danish(chart_type)
    n_points <- meta$n_points %||% 0L
    signals_detected <- meta$signals_detected %||% 0L

    # Anhoej-regler
    anhoej <- meta$anhoej_rules %||% list()
    longest_run <- anhoej$longest_run %||% 0L
    n_crossings <- anhoej$n_crossings %||% 0L
    n_crossings_min <- anhoej$n_crossings_min %||% 0L

    # Procesvariation
    process_variation <- if (signals_detected > 0) {
      "ikke naturligt"
    } else {
      "naturligt"
    }

    # LLM kontekst
    data_definition <- llm$data_definition %||% "Ikke angivet"
    chart_title <- llm$chart_title %||% "Ikke angivet"
    y_axis_unit <- llm$y_axis_unit %||% "enheder"
    target_value <- llm$target_value %||% "Ikke angivet"
    signal_examples <- llm$signal_examples %||% "Ingen"

    sprintf(
      paste0(
        "### %s\n",
        "- Indikator: %s\n",
        "- Titel: %s\n",
        "- Enhed: %s\n",
        "- Chart type: %s\n",
        "- Antal observationer: %s\n",
        "- Signaler: %s\n",
        "- Proces varierer: %s\n",
        "- L\u00e6ngste serie: %s punkter\n",
        "- Krydsninger: %s (forventet: %s)\n",
        "- Target: %s\n",
        "- Signaleksempler: %s"
      ),
      key,
      data_definition,
      chart_title,
      y_axis_unit,
      chart_type_dansk,
      n_points,
      signals_detected,
      process_variation,
      longest_run,
      n_crossings, n_crossings_min,
      target_value,
      signal_examples
    )
  }, character(1))

  diagrams_text <- paste(diagram_sections, collapse = "\n\n")

  # JSON eksempel baseret paa keys
  json_example_entries <- paste(
    vapply(keys, function(k) sprintf('  "%s": "analyse tekst..."', k), character(1)),
    collapse = ",\n"
  )
  json_example <- paste0("{\n", json_example_entries, "\n}")

  # Samlet prompt
  prompt <- sprintf(
    paste0(
      "Du er en ekspert i Statistical Process Control (SPC) og klinisk kvalitetsforbedring.\n\n",
      "Generer en kort, positivt og handlingsorienteret analyse for HVERT af de %d SPC-diagrammer nedenfor.\n\n",
      "KRITISKE REGLER:\n",
      "- Hver analyse skal v\u00e6re mellem %d og %d tegn\n",
      "- Dansk sprog\n",
      "- Konkret og handlingsorienteret\n",
      "- Brug **fed** til 1-2 forslag\n",
      "- Afslut ALTID med en komplet s\u00e6tning\n\n",
      "OUTPUT FORMAT:\n",
      "Returner UDELUKKENDE valid JSON med f\u00f8lgende struktur (ingen anden tekst):\n",
      "%s\n\n",
      "DIAGRAMMER:\n\n",
      "%s"
    ),
    length(keys),
    min_chars,
    max_chars,
    json_example,
    diagrams_text
  )

  prompt
}


#' Parse batch-respons fra LLM
#'
#' Parser JSON-respons tilbage til named list med analyser per diagram.
#' Haandterer valid JSON, partial JSON, invalid JSON, og JSON
#' indlejret i omgivende tekst.
#'
#' @param response Character string, raa respons fra LLM
#' @param keys Character vector, diagram-nogler der forventes i responsen
#'
#' @return Named list: diagram_key -> analyse tekst (eller NULL hvis manglende)
#'
#' @keywords internal
parse_batch_response <- function(response, keys) {
  # Initialiser resultat med NULL for alle keys
  result <- stats::setNames(
    vector("list", length(keys)),
    keys
  )

  # Haandter NULL eller tom respons
  if (is.null(response) || !is.character(response) || nchar(response) == 0) {
    return(result)
  }

  # Forsoeg at parse JSON direkte
  parsed <- tryCatch(
    jsonlite::fromJSON(response, simplifyVector = TRUE),
    error = function(e) NULL
  )

  # Hvis direkte parsing fejler, forsoeg at ekstrahere JSON fra tekst
  if (is.null(parsed)) {
    # Forsoeg at finde JSON objekt i teksten
    # Match indhold mellem foerste { og sidste }
    json_match <- regmatches(
      response,
      regexpr("\\{[^{}]*(?:\\{[^{}]*\\}[^{}]*)*\\}", response, perl = TRUE)
    )

    if (length(json_match) > 0) {
      parsed <- tryCatch(
        jsonlite::fromJSON(json_match[1], simplifyVector = TRUE),
        error = function(e) NULL
      )
    }
  }

  # Hvis parsing lykkedes, map vaerdier til keys

  if (!is.null(parsed) && is.list(parsed)) {
    for (key in keys) {
      value <- parsed[[key]]
      if (!is.null(value) && is.character(value) && nchar(value) > 0) {
        result[[key]] <- value
      }
    }
  }

  result
}


# EXPORTED FUNCTIONS ===========================================================

#' Batch SPC Analyse for Flere Diagrammer
#'
#' Genererer AI-drevne analyser for flere SPC-diagrammer i batch.
#' Bruger fil-baseret cache til at undgaa gentagne API-kald og
#' respekterer rate limits.
#'
#' @param contexts Named list: diagram_key -> list(spc_result, llm_context).
#'   Hver kontekst indeholder:
#'   \describe{
#'     \item{spc_result}{Liste med metadata (chart_type, n_points, signals_detected, anhoej_rules)}
#'     \item{llm_context}{Liste med data_definition, chart_title, y_axis_unit, target_value, signal_examples}
#'   }
#' @param batch_size Integer, antal diagrammer per API-kald (default: 25)
#' @param use_cache Logical, brug fil-baseret cache (default: TRUE)
#' @param cache_dir Character, sti til cache-mappe (default: tempdir())
#' @param force_refresh Logical, ignorer cache og kald API igen (default: FALSE)
#' @param min_chars Integer, minimum tegn per analyse (default: 300)
#' @param max_chars Integer, maksimum tegn per analyse (default: 375)
#'
#' @return Liste med:
#' \describe{
#'   \item{analyses}{Named list: diagram_key -> analyse tekst}
#'   \item{from_cache}{Integer, antal analyser hentet fra cache}
#'   \item{from_api}{Integer, antal analyser genereret via API}
#'   \item{failed}{Character vector, diagram_keys der fejlede}
#'   \item{rpd_exhausted}{Logical, TRUE hvis daglig rate limit var opbrugt}
#' }
#'
#' @examples
#' \dontrun{
#' # Opret kontekster for 3 diagrammer
#' contexts <- list(
#'   diagram_1 = list(
#'     spc_result = list(metadata = list(chart_type = "run", n_points = 24, signals_detected = 0)),
#'     llm_context = list(data_definition = "Ventetid", chart_title = "Ventetid 2024",
#'                        y_axis_unit = "dage", target_value = 30)
#'   ),
#'   diagram_2 = list(
#'     spc_result = list(metadata = list(chart_type = "p", n_points = 12, signals_detected = 2)),
#'     llm_context = list(data_definition = "Infektionsrate", chart_title = "Infektioner Q1",
#'                        y_axis_unit = "procent", target_value = 5)
#'   )
#' )
#'
#' result <- bfhllm_spc_suggestions_batch(contexts)
#' print(result$analyses)
#' }
#'
#' @export
bfhllm_spc_suggestions_batch <- function(contexts,
                                          batch_size = 25L,
                                          use_cache = TRUE,
                                          cache_dir = NULL,
                                          force_refresh = FALSE,
                                          min_chars = 300,
                                          max_chars = 375) {
  # Valider input
  if (!is.list(contexts) || length(contexts) == 0 || is.null(names(contexts))) {
    stop("contexts must be a non-empty named list", call. = FALSE)
  }

  all_keys <- names(contexts)

  # Initialiser resultat
  analyses <- stats::setNames(
    vector("list", length(all_keys)),
    all_keys
  )
  from_cache <- 0L
  from_api <- 0L
  failed <- character(0)
  rpd_exhausted <- FALSE

  # Setup fil-cache
  cache_dir <- cache_dir %||% tempdir()
  file_cache <- bfhllm_file_cache_create(cache_dir)

  # Step 1: Tjek cache for alle keys
  uncached_keys <- all_keys

  if (use_cache && !force_refresh) {
    for (key in all_keys) {
      cache_key <- bfhllm_generate_cache_key(contexts[[key]])
      cached_value <- file_cache$get(cache_key)

      if (!is.null(cached_value)) {
        analyses[[key]] <- cached_value
        from_cache <- from_cache + 1L
      }
    }

    # Identificer keys der mangler i cache
    uncached_keys <- all_keys[vapply(
      all_keys,
      function(k) is.null(analyses[[k]]),
      logical(1)
    )]
  }

  # Step 2: Returner tidligt hvis alt er cachet
  if (length(uncached_keys) == 0) {
    return(list(
      analyses = analyses,
      from_cache = from_cache,
      from_api = from_api,
      failed = failed,
      rpd_exhausted = rpd_exhausted
    ))
  }

  # Step 3: Split uncached keys i batches
  n_batches <- ceiling(length(uncached_keys) / batch_size)
  batches <- split(
    uncached_keys,
    rep(seq_len(n_batches), each = batch_size, length.out = length(uncached_keys))
  )

  # Step 4: Process hver batch

  for (i in seq_along(batches)) {
    batch_keys <- batches[[i]]

    # Tjek RPD foer hvert kald
    status <- bfhllm_rate_limit_status()
    if (status$rpd_remaining < 1) {
      rpd_exhausted <- TRUE
      # Tilfoej alle resterende keys (denne batch + efterfoelgende) som failed
      remaining_keys <- unlist(batches[seq(i, length(batches))], use.names = FALSE)
      failed <- c(failed, remaining_keys)
      break
    }

    # Byg prompt for denne batch
    batch_contexts <- contexts[batch_keys]
    prompt <- build_batch_prompt(batch_contexts, min_chars, max_chars)

    # Kald LLM
    response <- bfhllm_chat(prompt, max_chars = NULL, validate = FALSE)

    # Haandter fejl fra API
    if (is.null(response)) {
      failed <- c(failed, batch_keys)
      next
    }

    # Parse respons
    parsed <- parse_batch_response(response, batch_keys)

    # Fordel resultater
    for (key in batch_keys) {
      value <- parsed[[key]]
      if (!is.null(value)) {
        analyses[[key]] <- value
        from_api <- from_api + 1L

        # Gem i cache
        if (use_cache) {
          cache_key <- bfhllm_generate_cache_key(contexts[[key]])
          file_cache$set(cache_key, value)
        }
      } else {
        failed <- c(failed, key)
      }
    }
  }

  # Dedupliker failed keys
  failed <- unique(failed)

  list(
    analyses = analyses,
    from_cache = from_cache,
    from_api = from_api,
    failed = failed,
    rpd_exhausted = rpd_exhausted
  )
}
