# BFHllm 0.1.2

## Bug fixes

* Tilføjet `Remotes:` for `BFHcharts` (Suggests). Downstream-installationer
  kunne tidligere fejle ved `--as-cran` tests der forsøger at installere
  Suggests. Fra v0.1.2 er transitiv dep-resolution konsistent med sibling-
  pakkerne (BFHcharts v0.8.1).

# BFHllm 0.1.1

## Bug fixes

* Fixed deprecation warning by updating to `credentials` parameter in `ellmer::chat_google_gemini()` and `ragnar::embed_google_gemini()` calls (was `api_key` prior to ellmer 0.4.0)
* Fixed roxygen2 deprecation warning by removing `@docType package` and documenting `"_PACKAGE"` instead
* Updated ellmer dependency to >= 0.4.0 to ensure compatibility

# BFHllm 0.1.0

## Initial release

* Core LLM chat interface with Google Gemini provider
* Provider abstraction layer for future model support
* Configuration management system with defaults
* Circuit breaker pattern for API resilience
* Response validation and sanitization
* Generic caching layer with Shiny session adapter
* RAG integration with ragnar knowledge stores
* SPC-specific improvement suggestions module
* Comprehensive test suite with 142 passing tests
* Examples for basic chat, SPC suggestions, and Shiny integration
