# response-validation.R
# Response Validation and Sanitization

#' Validate and Sanitize LLM Response
#'
#' Validates API response text and sanitizes it by:
#' - Checking for NULL or empty responses
#' - Removing HTML tags
#' - Normalizing whitespace
#' - Trimming to maximum character limit
#' - Balancing markdown formatting
#'
#' @param text Character string, raw response from LLM
#' @param max_chars Integer, maximum allowed characters (default: 350)
#'
#' @return Character string with sanitized text, or NULL if invalid
#'
#' @details
#' **Sanitization Steps:**
#' 1. Check for NULL/empty input
#' 2. Remove HTML tags
#' 3. Normalize whitespace (collapse multiple spaces)
#' 4. Trim to max_chars (preserving word boundaries)
#' 5. Balance markdown asterisks (ensure even count)
#'
#' **Character Limit:**
#' When text exceeds max_chars, it is truncated at the last complete word
#' before the limit, and "..." is appended. Markdown formatting is balanced
#' to avoid broken bold/italic markers.
#'
#' @examples
#' \dontrun{
#' # Valid response
#' text <- validate_response(
#'   "This is a **valid** response",
#'   max_chars = 100
#' )
#'
#' # Long response (will be truncated)
#' long_text <- paste(rep("word", 100), collapse = " ")
#' text <- validate_response(long_text, max_chars = 50)
#' }
#'
#' @export
validate_response <- function(text, max_chars = 350) {
  # Check for NULL or empty
  if (is.null(text) || !is.character(text) || length(text) == 0) {
    warning("Empty or invalid response", call. = FALSE)
    return(NULL)
  }

  # Handle character vectors (collapse to single string)
  if (length(text) > 1) {
    text <- paste(text, collapse = " ")
  }

  # Check if empty after length check
  if (nchar(text) == 0) {
    warning("Empty response text", call. = FALSE)
    return(NULL)
  }

  # Sanitize: Remove HTML tags
  text <- gsub("<[^>]+>", "", text)

  # Sanitize: Normalize whitespace
  text <- gsub("\\s+", " ", text)
  text <- trimws(text)

  # Check if empty after sanitization
  if (nchar(text) == 0) {
    warning("Response empty after sanitization", call. = FALSE)
    return(NULL)
  }

  # Trim if needed
  if (nchar(text) > max_chars) {
    text <- trim_to_limit(text, max_chars)
  }

  return(text)
}

#' Trim Text to Character Limit
#'
#' Trims text to maximum character limit while:
#' - Preserving complete sentences (finds last sentence-ending punctuation)
#' - Balancing markdown asterisks
#' - Never appending "..." - text ends with complete sentence
#'
#' @param text Character string to trim
#' @param max_chars Integer, maximum allowed characters
#'
#' @return Character string, trimmed text ending with complete sentence
#'
#' @keywords internal
trim_to_limit <- function(text, max_chars) {
  # Trim to max length first
  trimmed <- substr(text, 1, max_chars)

  # Find the last sentence-ending punctuation (. ! ?)

  # Also handle sentences ending with ** (bold markdown) before punctuation
  sentence_end_pattern <- "[.!?](?:\\*\\*)?\\s*$|[.!?](?:\\*\\*)?(?=\\s)"

  # Find all sentence endings
  matches <- gregexpr("[.!?](?:\\*\\*)?", trimmed)[[1]]

  if (matches[1] != -1) {
    # Get the last sentence ending position
    last_match <- max(matches)
    match_length <- attr(matches, "match.length")[which.max(matches)]

    # Cut at end of last complete sentence
    text <- substr(trimmed, 1, last_match + match_length - 1)
  } else {
    # No sentence ending found - keep as is but trim at word boundary
    last_space <- regexpr("\\s[^\\s]*$", trimmed)
    if (last_space > 0) {
      text <- substr(trimmed, 1, last_space)
    } else {
      text <- trimmed
    }
  }

  # Trim trailing whitespace
  text <- trimws(text)

  # Balance markdown asterisks
  text <- balance_markdown_asterisks(text)

  return(text)
}

#' Balance Markdown Asterisks
#'
#' Ensures even number of asterisks to avoid broken markdown formatting.
#' Removes trailing asterisk if count is odd.
#'
#' @param text Character string
#'
#' @return Character string with balanced asterisks
#'
#' @keywords internal
balance_markdown_asterisks <- function(text) {
  # Count asterisks
  asterisk_count <- lengths(regmatches(text, gregexpr("\\*", text)))

  # If odd count, remove last asterisk
  if (asterisk_count %% 2 == 1) {
    text <- sub("\\*([^*]*)$", "\\1", text)
    text <- trimws(text)
  }

  return(text)
}

#' Validate Response Length
#'
#' Simple check if response is within character limit.
#'
#' @param text Character string
#' @param max_chars Integer, maximum allowed characters
#'
#' @return Logical, TRUE if within limit
#'
#' @examples
#' \dontrun{
#' validate_response_length("Short text", max_chars = 100) # TRUE
#' validate_response_length(paste(rep("word", 100), collapse = " "), max_chars = 50) # FALSE
#' }
#'
#' @export
validate_response_length <- function(text, max_chars = 350) {
  if (is.null(text) || !is.character(text)) {
    return(FALSE)
  }

  nchar(text) <= max_chars
}
