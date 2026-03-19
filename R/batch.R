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

  # Diagrammer uden baseline haandteres af rewrite-prompten
  build_batch_prompt_rewrite(contexts, keys, min_chars, max_chars)
}

# NY: Omskriv-baseret batch-prompt
build_batch_prompt_rewrite <- function(contexts, keys, min_chars, max_chars) {
  diagram_sections <- vapply(keys, function(key) {
    ctx <- contexts[[key]]
    llm <- ctx$llm_context

    target_line <- if (!is.null(llm$target_display) &&
                       nchar(llm$target_display) > 0) {
      sprintf("- Maal (som vist i diagram): %s\n", llm$target_display)
    } else {
      ""
    }

    # Centerline og maalstatus fra pipeline
    centerline_line <- if (!is.null(llm$centerline) &&
                           nchar(as.character(llm$centerline)) > 0) {
      sprintf("- Aktuel centerlinje: %s\n", llm$centerline)
    } else {
      ""
    }

    target_status_line <- if (isTRUE(llm$at_target)) {
      "- Maalstatus: OPFYLDT (processen er paa eller over maalet)\n"
    } else if (!is.null(llm$at_target) && !llm$at_target) {
      "- Maalstatus: IKKE OPFYLDT\n"
    } else {
      ""
    }

    action_line <- if (!is.null(llm$action_text) &&
                       nchar(llm$action_text) > 0) {
      sprintf("- Anbefalet handling: %s\n", llm$action_text)
    } else {
      ""
    }

    sprintf(
      paste0(
        "### %s\n",
        "BASELINE: \"%s\"\n",
        "- Indikator: %s\n",
        "- Definition: %s\n",
        "- Afdeling: %s\n",
        "- Enhed: %s\n",
        "%s",
        "%s",
        "%s",
        "%s"
      ),
      key,
      llm$baseline_analysis %||% "",
      llm$chart_title %||% "Ikke angivet",
      llm$data_definition %||% "Ikke angivet",
      llm$department %||% "Ikke angivet",
      llm$y_axis_unit %||% "enheder",
      target_line,
      centerline_line,
      target_status_line,
      action_line
    )
  }, character(1))

  diagrams_text <- paste(diagram_sections, collapse = "\n\n")

  # JSON eksempel
  json_example_entries <- paste(
    vapply(keys, function(k) sprintf('  "%s": "omskrevet analyse..."', k), character(1)),
    collapse = ",\n"
  )
  json_example <- paste0("{\n", json_example_entries, "\n}")

  sprintf(
    paste0(
      "Du skal omformulere SPC-analysetekster. Du omskriver BASELINE-teksten saa den naevner den konkrete indikator ved navn - men du AENDRER IKKE BUDSKABET.\n\n",
      "For HVERT af de %d diagrammer nedenfor:\n\n",
      "HVAD DU SKAL:\n",
      "- Goer teksten specifik ved at naevne indikatoren (fx 'antibiotikabehandling inden 3 timer' i stedet for 'processen')\n",
      "- Bevar ALLE konklusioner og talvaerdier fra baseline praecist\n",
      "- Omformuler til naturligt, professionelt dansk\n",
      "- Brug **fed** til at fremhaeve den centrale konklusion (fx '**en bevidst procesaendring er noedvendig**')\n",
      "- Naar et maal naevnes, brug vaerdien fra 'Maal (som vist i diagram)' feltet\n",
      "- Respekt\u00e9r 'Maalstatus': Hvis OPFYLDT, skriv om at fastholde niveauet - ALDRIG om at 'naa maalet'\n",
      "- Hvis BASELINE er tom: skriv en kort tekst baseret KUN paa 'Anbefalet handling' og 'Maalstatus' - opfind INTET\n\n",
      "HVAD DU ABSOLUT IKKE MAA:\n",
      "- ALDRIG foreslaa specifikke tiltag (checklister, traening, audits, systemer, procedurer, interventioner)\n",
      "- ALDRIG tilfoeje aarsagsforklaringer eller hypoteser\n",
      "- ALDRIG tilfoeje information der ikke staar i baseline\n",
      "- Din tekst skal have PRAECIS SAMME informationsindhold som baseline - bare bedre formuleret og specifik for indikatoren\n\n",
      "EKSEMPLER PAA KORREKT OMSKRIVNING:\n\n",
      "Eksempel 1 (stabil, under maal):\n",
      "Baseline: \"Processen viser stabil adfaerd. Niveauet ligger under maalet (60%%). Forbedring kraever en bevidst aendring af processen - den nuvaerende praksis vil levere samme resultat.\"\n",
      "Definition: \"Andelen af patienter der modtager antibiotika inden 3 timer\"\n",
      "God omskrivning: \"Andelen af patienter der modtager antibiotika inden 3 timer er stabil, men naar endnu ikke maalet paa 60%%. **En bevidst processaendring er noedvendig** for at loefte niveauet - den nuvaerende tilgang vil fortsaette med at levere de samme resultater.\"\n\n",
      "Eksempel 2 (stabil, maal opfyldt):\n",
      "Baseline: \"Processen viser stabil adfaerd. Niveauet ligger taet paa maalet (97%%). Fortsaet den nuvaerende praksis og overvaag processen loebende for at fastholde det gode niveau.\"\n",
      "Definition: \"Registreret komplet klinisk TNM\"\n",
      "God omskrivning: \"Registrering af klinisk TNM er stabil og ligger taet paa maalet paa 97%%. **Fortsaet den nuvaerende praksis** og overvaag processen loebende for at fastholde det gode niveau.\"\n\n",
      "Eksempel 3 (ustabil):\n",
      "Baseline: \"Processen viser systematisk ustabilitet. Baade serielaengde (9 > 8) og antal krydsninger (12 < 13) afviger. Prioriter at identificere og fjerne de saerlige aarsager til variationen foer yderligere forbedringstiltag ivaerksaettes.\"\n",
      "Definition: \"Andel patienter med ambulant opfoelgning inden 2 uger\"\n",
      "God omskrivning: \"Ambulant opfoelgning inden 2 uger viser systematisk ustabilitet - baade serielaengde (9 > 8) og antal krydsninger (12 < 13) afviger fra det forventede. **Identificer og fjern de saerlige aarsager til variationen** foer yderligere forbedringstiltag ivaerksaettes.\"\n\n",
      "FORMAT:\n",
      "- Hver analyse: mellem %d og %d tegn\n",
      "- Dansk sprog, professionel tone\n",
      "- Afslut ALTID med en komplet saetning\n\n",
      "OUTPUT FORMAT:\n",
      "Returner UDELUKKENDE valid JSON (ingen anden tekst):\n",
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

    # Log prompt + response til debug-fil (hvis log_dir sat)
    if (!is.null(cache_dir)) {
      log_dir <- file.path(cache_dir, "llm_debug")
      if (!dir.exists(log_dir)) {
        dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
      }
      log_file <- file.path(
        log_dir,
        sprintf("batch_%s_%02d.json",
                format(Sys.time(), "%Y%m%d_%H%M%S"), i)
      )
      log_entry <- list(
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        batch_index = i,
        diagram_keys = batch_keys,
        prompt = prompt,
        raw_response = as.character(response %||% "NULL"),
        per_diagram_input = lapply(batch_keys, function(k) {
          llm <- batch_contexts[[k]]$llm_context
          list(
            key = k,
            baseline_analysis = llm$baseline_analysis %||% "",
            chart_title = llm$chart_title %||% "",
            data_definition = llm$data_definition %||% "",
            department = llm$department %||% "",
            y_axis_unit = llm$y_axis_unit %||% ""
          )
        })
      )
      tryCatch(
        writeLines(
          jsonlite::toJSON(log_entry, auto_unbox = TRUE, pretty = TRUE),
          log_file
        ),
        error = function(e) NULL
      )
    }

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

    # Log parsed resultater per diagram (tilfoej til debug-fil)
    if (!is.null(cache_dir)) {
      parsed_log <- file.path(
        cache_dir, "llm_debug",
        sprintf("batch_%s_%02d_parsed.json",
                format(Sys.time(), "%Y%m%d_%H%M%S"), i)
      )
      parsed_entries <- lapply(batch_keys, function(k) {
        llm <- batch_contexts[[k]]$llm_context
        list(
          key = k,
          input_baseline = llm$baseline_analysis %||% "",
          input_title = llm$chart_title %||% "",
          input_definition = llm$data_definition %||% "",
          input_department = llm$department %||% "",
          output_from_llm = as.character(parsed[[k]] %||% "FAILED")
        )
      })
      tryCatch(
        writeLines(
          jsonlite::toJSON(parsed_entries, auto_unbox = TRUE, pretty = TRUE),
          parsed_log
        ),
        error = function(e) NULL
      )
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
