# prompts.R
# Prompt Template Utilities

#' Interpolate Prompt Template
#'
#' Replaces placeholders in prompt template with values from data list.
#' Placeholders use `{{variable}}` syntax (double curly braces).
#'
#' @param template Character string, prompt template with `{{placeholders}}`
#' @param data Named list with values to interpolate
#'
#' @return Character string with interpolated prompt
#'
#' @details
#' **Placeholder Syntax:**
#' Use `{{variable_name}}` in template. Spaces inside braces are allowed
#' (`{{ variable }}` works).
#'
#' **Missing Variables:**
#' If a placeholder variable is not found in data, it is left unchanged
#' in the output (no error thrown).
#'
#' **Type Coercion:**
#' All values are coerced to character strings via `as.character()`.
#'
#' @examples
#' \dontrun{
#' # Basic interpolation
#' template <- "Hello {{name}}, you are {{age}} years old"
#' data <- list(name = "Alice", age = 30)
#' prompt <- bfhllm_interpolate(template, data)
#' # "Hello Alice, you are 30 years old"
#'
#' # SPC prompt template
#' template <- paste(
#'   "Analyze this {{chart_type}} chart with {{n_points}} data points.",
#'   "The process shows {{variation_type}} variation.",
#'   "Suggest improvements."
#' )
#' data <- list(
#'   chart_type = "run chart",
#'   n_points = 24,
#'   variation_type = "stable"
#' )
#' prompt <- bfhllm_interpolate(template, data)
#' }
#'
#' @export
bfhllm_interpolate <- function(template, data) {
  if (!is.character(template) || length(template) == 0) {
    stop("template must be a non-empty character string", call. = FALSE)
  }

  if (!is.list(data)) {
    stop("data must be a named list", call. = FALSE)
  }

  # Collapse to single string if vector
  if (length(template) > 1) {
    template <- paste(template, collapse = " ")
  }

  # Replace each placeholder
  result <- template

  for (name in names(data)) {
    value <- data[[name]]

    # Coerce to character
    value_str <- if (is.null(value)) {
      ""
    } else {
      as.character(value)
    }

    # Replace {{name}} or {{ name }} (with optional spaces)
    pattern <- sprintf("\\{\\{\\s*%s\\s*\\}\\}", name)
    result <- gsub(pattern, value_str, result)
  }

  return(result)
}

#' Build Prompt from Components
#'
#' Concatenates multiple prompt components into a single prompt string.
#' Useful for building complex prompts from modular pieces.
#'
#' @param ... Character strings or named list, prompt components
#' @param sep Character string, separator between components (default: "\\n\\n")
#'
#' @return Character string with concatenated prompt
#'
#' @details
#' **Named Arguments:**
#' If using named arguments, names are ignored (only values are used).
#'
#' **NULL Handling:**
#' NULL components are automatically filtered out.
#'
#' **Whitespace:**
#' Leading/trailing whitespace is trimmed from each component before concatenation.
#'
#' @examples
#' \dontrun{
#' # Build SPC analysis prompt
#' system_msg <- "You are an SPC analysis expert."
#' context <- "Chart type: run chart. Data points: 24."
#' question <- "What does stable variation indicate?"
#'
#' prompt <- bfhllm_build_prompt(
#'   system_msg,
#'   context,
#'   question,
#'   sep = "\n\n"
#' )
#'
#' # With conditional components
#' prompt <- bfhllm_build_prompt(
#'   "Analyze this chart:",
#'   if (has_signals) "Signals detected: Run of 8",
#'   "Suggest actions."
#' )
#' }
#'
#' @export
bfhllm_build_prompt <- function(..., sep = "\n\n") {
  components <- list(...)

  # Flatten if list of lists
  components <- unlist(components, recursive = FALSE)

  # Filter out NULL
  components <- Filter(Negate(is.null), components)

  # Trim whitespace from each
  components <- vapply(components, trimws, character(1))

  # Filter out empty strings
  components <- components[nchar(components) > 0]

  # Concatenate
  paste(components, collapse = sep)
}

#' Create Structured Prompt
#'
#' Creates a prompt with structured sections (system, context, question).
#' Useful for RAG-enhanced prompts or complex multi-part queries.
#'
#' @param question Character string, main question or instruction
#' @param context Character string, additional context (optional)
#' @param system Character string, system message or role (optional)
#' @param format Character string, desired output format instructions (optional)
#'
#' @return Character string with structured prompt
#'
#' @examples
#' \dontrun{
#' prompt <- bfhllm_create_structured_prompt(
#'   question = "What causes special cause variation?",
#'   context = "Run chart shows 8 consecutive points above centerline",
#'   system = "You are an SPC methodology expert",
#'   format = "Respond in Danish, max 2 sentences"
#' )
#' }
#'
#' @export
bfhllm_create_structured_prompt <- function(question,
                                             context = NULL,
                                             system = NULL,
                                             format = NULL) {
  components <- list()

  if (!is.null(system)) {
    components <- c(components, list(paste("System:", system)))
  }

  if (!is.null(context)) {
    components <- c(components, list(paste("Context:", context)))
  }

  components <- c(components, list(paste("Question:", question)))

  if (!is.null(format)) {
    components <- c(components, list(paste("Format:", format)))
  }

  bfhllm_build_prompt(components, sep = "\n\n")
}
