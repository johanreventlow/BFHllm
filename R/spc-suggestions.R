# spc-suggestions.R
# SPC-Specific AI Improvement Suggestions

#' Map Chart Type to Danish Name
#'
#' Translates English SPC chart type codes to Danish display names.
#'
#' @param chart_type Character string, chart type code (e.g., "run", "p", "c")
#'
#' @return Character string with Danish chart type name
#'
#' @details
#' **Supported Chart Types:**
#' - run: Serieplot (run chart)
#' - i: I-chart (individuelle værdier)
#' - mr: MR-chart (moving range)
#' - xbar: X-bar chart (gennemsnit)
#' - s: S-chart (standardafvigelse)
#' - t: T-chart (tid mellem events)
#' - p: P-chart (andel)
#' - pp: PP-chart (andel per periode)
#' - c: C-chart (antal events)
#' - u: U-chart (rate per enhed)
#' - g: G-chart (events mellem)
#' - prime: Prime chart
#'
#' **Unknown Types:**
#' Returns original English name if chart type not recognized.
#'
#' @examples
#' bfhllm_map_chart_type_danish("run")
#' # "serieplot (run chart)"
#'
#' bfhllm_map_chart_type_danish("p")
#' # "P-chart (andel)"
#'
#' bfhllm_map_chart_type_danish("unknown")
#' # "unknown"
#'
#' @export
bfhllm_map_chart_type_danish <- function(chart_type) {
  # Danish name mapping
  mapping <- list(
    "run" = "serieplot (run chart)",
    "i" = "I-chart (individuelle værdier)",
    "mr" = "MR-chart (moving range)",
    "xbar" = "X-bar chart (gennemsnit)",
    "s" = "S-chart (standardafvigelse)",
    "t" = "T-chart (tid mellem events)",
    "p" = "P-chart (andel)",
    "pp" = "PP-chart (andel per periode)",
    "c" = "C-chart (antal events)",
    "u" = "U-chart (rate per enhed)",
    "g" = "G-chart (events mellem)",
    "prime" = "Prime chart"
  )

  danish_name <- mapping[[tolower(chart_type)]]

  if (is.null(danish_name)) {
    warning(
      sprintf("Unknown chart type: %s. Using English name as fallback.", chart_type),
      call. = FALSE
    )
    return(chart_type)
  }

  return(danish_name)
}

#' Extract SPC Metadata for AI Prompts
#'
#' Extracts structured SPC metadata from BFHcharts/qicharts2 result objects
#' for use in AI prompt generation.
#'
#' @param spc_result List from BFHcharts or qicharts2 with components:
#'   - metadata: list with chart_type, n_points, signals_detected, anhoej_rules
#'   - qic_data: data.frame with x, y, cl, ucl, lcl columns
#'
#' @return Named list with extracted metadata:
#'   - chart_type: Chart type code
#'   - chart_type_dansk: Danish name
#'   - n_points: Number of observations
#'   - signals_detected: Anhøj rule violations
#'   - longest_run: Longest run above/below centerline
#'   - n_crossings: Centerline crossings
#'   - n_crossings_min: Expected minimum crossings
#'   - centerline: Mean centerline value
#'   - start_date: First x value
#'   - end_date: Last x value
#'   - process_variation: "naturligt" or "ikke naturligt"
#'
#' Returns NULL if spc_result is invalid or missing required components.
#'
#' @examples
#' \dontrun{
#' # With BFHcharts result
#' spc_result <- BFHcharts::create_spc_chart(data, ...)
#' metadata <- bfhllm_extract_spc_metadata(spc_result)
#'
#' # With qicharts2 result
#' qic_result <- qicharts2::qic(x, y, chart = "run", return.data = TRUE)
#' metadata <- bfhllm_extract_spc_metadata(qic_result)
#' }
#'
#' @export
bfhllm_extract_spc_metadata <- function(spc_result) {
  # Validate input
  if (is.null(spc_result) || !is.list(spc_result)) {
    warning("Invalid spc_result: NULL or not a list", call. = FALSE)
    return(NULL)
  }

  metadata <- list()

  # Extract from metadata component
  if (!is.null(spc_result$metadata)) {
    meta <- spc_result$metadata

    metadata$chart_type <- meta$chart_type %||% "unknown"
    metadata$chart_type_dansk <- bfhllm_map_chart_type_danish(metadata$chart_type)
    metadata$n_points <- meta$n_points %||% 0
    metadata$signals_detected <- meta$signals_detected %||% 0

    # Anhøj rules (qicharts2 output structure)
    if (!is.null(meta$anhoej_rules)) {
      rules <- meta$anhoej_rules
      metadata$longest_run <- rules$longest_run %||% 0
      metadata$n_crossings <- rules$n_crossings %||% 0
      metadata$n_crossings_min <- rules$n_crossings_min %||% 0
    } else {
      metadata$longest_run <- 0
      metadata$n_crossings <- 0
      metadata$n_crossings_min <- 0
    }
  } else {
    warning("Missing metadata component in spc_result", call. = FALSE)
    return(NULL)
  }

  # Extract from qic_data (time period + centerline)
  if (!is.null(spc_result$qic_data) && nrow(spc_result$qic_data) > 0) {
    qic <- spc_result$qic_data

    # Centerline (mean of cl column)
    if ("cl" %in% names(qic) && !all(is.na(qic$cl))) {
      metadata$centerline <- round(mean(qic$cl, na.rm = TRUE), 2)
    } else {
      metadata$centerline <- NA_real_
    }

    # Time period (first and last x value)
    if ("x" %in% names(qic) && nrow(qic) > 0) {
      metadata$start_date <- as.character(qic$x[1])
      metadata$end_date <- as.character(qic$x[nrow(qic)])
    } else {
      metadata$start_date <- "Ikke angivet"
      metadata$end_date <- "Ikke angivet"
    }
  } else {
    warning("Missing or empty qic_data in spc_result", call. = FALSE)
    metadata$centerline <- NA_real_
    metadata$start_date <- "Ikke angivet"
    metadata$end_date <- "Ikke angivet"
  }

  # Process variation status based on Anhøj signals
  metadata$process_variation <- if (metadata$signals_detected > 0) {
    "ikke naturligt"
  } else {
    "naturligt"
  }

  return(metadata)
}

#' Determine Target Comparison Status
#'
#' Compares centerline with target value and returns Danish description.
#' Uses 5% tolerance for "ved målet" classification.
#'
#' @param centerline Numeric centerline value
#' @param target_value Numeric target value (can be NULL or NA)
#'
#' @return Character string:
#'   - "over målet": centerline > target (outside tolerance)
#'   - "under målet": centerline < target (outside tolerance)
#'   - "ved målet": within 5% of target
#'   - "ikke angivet": target missing or invalid
#'
#' @keywords internal
determine_target_comparison <- function(centerline, target_value) {
  # Check if target is missing or invalid
  if (is.null(target_value) || length(target_value) == 0) {
    return("ikke angivet")
  }

  target <- suppressWarnings(as.numeric(target_value))

  if (is.na(target) || (is.character(target_value) && target_value == "")) {
    return("ikke angivet")
  }

  # Check if centerline is missing or invalid
  if (is.null(centerline) || is.na(centerline)) {
    return("ikke angivet")
  }

  # Calculate tolerance (5% of target value)
  tolerance <- abs(target * 0.05)
  diff <- centerline - target

  # Classify based on tolerance
  if (abs(diff) <= tolerance) {
    return("ved målet")
  } else if (centerline > target) {
    return("over målet")
  } else {
    return("under målet")
  }
}

#' Get SPC Improvement Suggestion Prompt Template
#'
#' Returns the Danish prompt template for SPC improvement suggestions.
#'
#' @return Character string with prompt template containing {{placeholders}}
#'
#' @keywords internal
get_spc_prompt_template <- function() {
  template <- "
Du er en ekspert i Statistical Process Control (SPC) og klinisk kvalitetsforbedring. Du vurderer SPC-processer efter Anhøj-reglerne.

Baseret på følgende SPC-data, skal du generere en kort positivt og handlingsorienteret analyse af et seriediagram (mellem {{min_chars}} og {{max_chars}} tegn) på dansk. Formater target_values i samme enhed som {{y_axis_unit}}.

KONTEKST:
- Indikator: {{data_definition}}
- Titel: {{chart_title}}
- Enhed: {{y_axis_unit}}
- Chart type: {{chart_type_dansk}}
- Antal observationer: {{n_points}}
- Periode: {{start_date}} til {{end_date}}
- Target: {{target_value}}
- Centerline: {{centerline}}

SPC ANALYSE:
- Proces varierer {{process_variation}}
- Antal særligt afvigende punkter: {{signals_detected}}
- Længste serie: {{longest_run}} punkter
- Antal krydsninger: {{n_crossings}} (forventet: {{n_crossings_min}})
- Niveau vs. mål: {{target_comparison}}

STRUKTUR (følg dette format):
1. Start med kontekst (fx \"Mere end X gange om måneden...\")
2. Beskriv processens variation (naturlig/ikke-naturlig, særlige punkter)
3. Forhold til mål (over/under/ved)
4. Konkret forslag markeret med **fed** (fx \"**Identificér årsager...**\")

EKSEMPEL:
\"Mere end 35.000 gange om måneden administreres medicin ikke korrekt. Processen varierer ikke naturligt, og indeholder 3 særligt afvigende målepunkter. Niveauet er under målet. Forslag: **Identificér årsager bag de afvigende målepunkter**, og understøt faktorer der kan forbedre målopfyldelsen. Stabilisér processen når niveauet er tilfredsstillende.\"

VIGTIGE REGLER:
- KRITISK: Svaret SKAL være mellem {{min_chars}} og {{max_chars}} tegn. Tæl tegnene nøje!
- Afslut ALTID med en komplet sætning - aldrig med '...' eller afbrudte ord
- Planlæg din tekst så den passer inden for grænsen og slutter naturligt
- Dansk sprog
- Konkret og handlingsorienteret
- Brug fed (**tekst**) til forslag, men vær selektiv - kun 1-2 forslag, max 3 i sjældnere tilfælde.
- Fokusér på forbedringsmuligheder
- Undgå teknisk jargon - men hold professionel distance
"

  return(template)
}

#' Generate SPC Improvement Suggestion
#'
#' Main function for generating AI-powered improvement suggestions for SPC charts.
#' Combines metadata extraction, RAG context retrieval, prompt building, and
#' LLM generation into a single high-level interface.
#'
#' @param spc_result List from BFHcharts/qicharts2 with metadata and qic_data
#' @param context Named list with user context:
#'   - data_definition: Indicator description (character)
#'   - chart_title: Chart title (character)
#'   - y_axis_unit: Unit of measurement (e.g., "dage", "antal", "procent")
#'   - target_value: Target value (numeric, optional)
#' @param min_chars Minimum characters in response (default: 300)
#' @param max_chars Maximum characters in response (default: 375)
#' @param use_rag Logical, use RAG for SPC methodology context (default: TRUE)
#' @param cache Cache object from bfhllm_cache_create() or bfhllm_cache_shiny() (optional)
#' @param ... Additional arguments passed to bfhllm_chat() (model, timeout, etc.)
#'
#' @return Character string with AI-generated improvement suggestion in Danish,
#'   or NULL on error
#'
#' @details
#' **Workflow:**
#' 1. Extract SPC metadata from result object
#' 2. Query RAG knowledge store (if use_rag = TRUE)
#' 3. Build structured prompt with metadata + context + RAG
#' 4. Call LLM via bfhllm_chat()
#' 5. Validate and return response
#'
#' **Caching:**
#' If cache provided, checks cache before API call and stores result after.
#' Cache key includes metadata, context, and RAG content for uniqueness.
#'
#' **RAG Integration:**
#' When use_rag = TRUE, queries knowledge store for relevant SPC methodology
#' based on chart type, signals detected, and target comparison.
#'
#' @examples
#' \dontrun{
#' # Basic usage
#' spc_result <- BFHcharts::create_spc_chart(data, ...)
#' context <- list(
#'   data_definition = "Ventetid til operation",
#'   chart_title = "Ventetid ortopædkirurgi 2024",
#'   y_axis_unit = "dage",
#'   target_value = 30
#' )
#'
#' suggestion <- bfhllm_spc_suggestion(spc_result, context)
#'
#' # With caching (Shiny)
#' cache <- bfhllm_cache_shiny(session)
#' suggestion <- bfhllm_spc_suggestion(
#'   spc_result, context,
#'   cache = cache
#' )
#'
#' # Without RAG
#' suggestion <- bfhllm_spc_suggestion(
#'   spc_result, context,
#'   use_rag = FALSE
#' )
#' }
#'
#' @export
bfhllm_spc_suggestion <- function(spc_result,
                                   context,
                                   min_chars = 300,
                                   max_chars = 375,
                                   use_rag = TRUE,
                                   cache = NULL,
                                   ...) {
  # Step 1: Validate inputs
  if (is.null(spc_result)) {
    warning("spc_result is NULL", call. = FALSE)
    return(NULL)
  }

  if (is.null(context)) {
    warning("context is NULL", call. = FALSE)
    return(NULL)
  }

  # Step 2: Extract metadata
  metadata <- bfhllm_extract_spc_metadata(spc_result)

  if (is.null(metadata)) {
    warning("Failed to extract SPC metadata", call. = FALSE)
    return(NULL)
  }

  # Step 3: Check cache (if provided)
  if (!is.null(cache)) {
    # Build cache key from metadata + context
    cache_data <- c(metadata, context, list(min_chars = min_chars, max_chars = max_chars))
    cache_key <- bfhllm_generate_cache_key(cache_data)

    cached <- cache$get(cache_key)

    if (!is.null(cached)) {
      return(cached)
    }
  }

  # Step 4: Query RAG knowledge store (if enabled)
  rag_context <- NULL

  if (use_rag) {
    # Determine target comparison
    target_comparison <- determine_target_comparison(
      metadata$centerline,
      context$target_value
    )

    # Build RAG query from chart characteristics
    rag_query <- sprintf(
      "%s chart with %s variation, %d signals detected, level %s target",
      metadata$chart_type,
      metadata$process_variation,
      metadata$signals_detected,
      target_comparison
    )

    # Query knowledge store (graceful fallback on error)
    rag_results <- suppressWarnings(
      bfhllm_query_knowledge(
        query = rag_query,
        top_k = 3,
        method = "hybrid"
      )
    )

    # Format RAG context if results available
    if (!is.null(rag_results)) {
      rag_context <- bfhllm_format_rag_context(rag_results, max_chunks = 3)
    }
  }

  # Step 5: Build prompt
  template <- get_spc_prompt_template()

  # Determine target comparison for prompt
  target_comparison <- determine_target_comparison(
    metadata$centerline,
    context$target_value
  )

  # Combine all prompt data
  prompt_data <- c(
    metadata,
    context,
    list(
      target_comparison = target_comparison,
      min_chars = min_chars,
      max_chars = max_chars
    )
  )

  # Interpolate template
  prompt <- bfhllm_interpolate(template, prompt_data)

  # Append RAG context if available
  if (!is.null(rag_context)) {
    rag_section <- sprintf(
      "\n\n## SPC Metodologi Reference\n\nBrug følgende autoritativ SPC metodologi som reference til at grunde dit svar:\n\n%s\n",
      rag_context
    )
    prompt <- paste0(prompt, rag_section)
  }

  # Step 6: Call LLM
  response <- bfhllm_chat(
    prompt = prompt,
    max_chars = max_chars,
    validate = TRUE,
    ...
  )

  # Step 7: Cache result (if cache provided and response successful)
  if (!is.null(cache) && !is.null(response)) {
    cache$set(cache_key, response)
  }

  return(response)
}
