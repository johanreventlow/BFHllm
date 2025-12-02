# provider-interface.R
# Abstract Provider Interface for LLM Providers

#' Provider Interface Documentation
#'
#' BFHllm uses a provider abstraction to support multiple LLM providers.
#' Currently supports Google Gemini via ellmer. Future providers (OpenAI,
#' Anthropic, etc.) can be added by implementing this interface.
#'
#' @section Required Functions:
#'
#' Each provider implementation must provide:
#'
#' * `provider_validate_setup()` - Check if provider prerequisites are met
#' * `provider_call_api()` - Call provider API with error handling
#' * `provider_extract_text()` - Extract text from provider response
#'
#' @section Provider Registry:
#'
#' Providers are registered in `.bfhllm_env$providers` with:
#' * `name` - Provider identifier (e.g., "gemini")
#' * `validate` - Validation function
#' * `call` - API call function
#' * `extract` - Text extraction function
#'
#' @name provider-interface
#' @keywords internal
NULL

# PROVIDER REGISTRY =============================================================

#' Get Provider Implementation
#'
#' Retrieves provider implementation by name. Currently only supports "gemini".
#'
#' @param provider_name Character string, provider identifier
#'
#' @return List with provider functions, or NULL if not found
#'
#' @keywords internal
get_provider <- function(provider_name) {
  # Currently only Gemini is implemented
  if (provider_name == "gemini") {
    return(list(
      name = "gemini",
      validate = gemini_validate_setup,
      call = gemini_call_api,
      extract = gemini_extract_text
    ))
  }

  # Future providers can be added here
  # if (provider_name == "openai") { ... }
  # if (provider_name == "anthropic") { ... }

  warning(sprintf("Provider '%s' not found. Available: gemini", provider_name),
    call. = FALSE
  )
  return(NULL)
}

#' List Available Providers
#'
#' Returns names of all registered LLM providers.
#'
#' @return Character vector of provider names
#'
#' @examples
#' \dontrun{
#' providers <- list_providers()
#' print(providers) # "gemini"
#' }
#'
#' @export
list_providers <- function() {
  # Currently only Gemini
  return("gemini")

  # Future: query provider registry
  # names(.bfhllm_env$providers)
}

# PROVIDER INTERFACE VALIDATION =================================================

#' Validate Provider Setup
#'
#' Calls provider-specific validation function to check prerequisites.
#'
#' @param provider_name Character string, provider identifier
#'
#' @return Logical, TRUE if setup is valid
#'
#' @keywords internal
validate_provider_setup <- function(provider_name) {
  provider <- get_provider(provider_name)

  if (is.null(provider)) {
    return(FALSE)
  }

  provider$validate()
}

#' Call Provider API
#'
#' Calls provider-specific API function with standardized interface.
#'
#' @param provider_name Character string, provider identifier
#' @param prompt Character string, prompt to send
#' @param model Character string, model identifier
#' @param timeout Numeric, timeout in seconds
#'
#' @return Provider-specific response object, or NULL on error
#'
#' @keywords internal
call_provider_api <- function(provider_name, prompt, model, timeout) {
  provider <- get_provider(provider_name)

  if (is.null(provider)) {
    stop(sprintf("Provider '%s' not available", provider_name))
  }

  provider$call(
    prompt = prompt,
    model = model,
    timeout = timeout
  )
}

#' Extract Text from Provider Response
#'
#' Calls provider-specific text extraction function.
#'
#' @param provider_name Character string, provider identifier
#' @param response Provider-specific response object
#'
#' @return Character string with extracted text
#'
#' @keywords internal
extract_provider_text <- function(provider_name, response) {
  provider <- get_provider(provider_name)

  if (is.null(provider)) {
    stop(sprintf("Provider '%s' not available", provider_name))
  }

  provider$extract(response)
}
