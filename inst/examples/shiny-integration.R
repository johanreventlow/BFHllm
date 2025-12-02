# shiny-integration.R
# Shiny Integration Example with BFHllm Session-Scoped Caching

# Load libraries
library(BFHllm)
library(shiny)

# Check if BFHllm is available
if (!bfhllm_chat_available()) {
  stop(
    "BFHllm not available. Set GOOGLE_API_KEY or GEMINI_API_KEY in .Renviron ",
    "and restart R."
  )
}

# Define UI
ui <- fluidPage(
  titlePanel("BFHllm Shiny Integration Example"),

  sidebarLayout(
    sidebarPanel(
      h4("Chat Interface"),

      textAreaInput(
        "prompt",
        "Enter your prompt:",
        value = "Explain the difference between a run chart and a control chart",
        height = "150px"
      ),

      sliderInput(
        "max_chars",
        "Max response length:",
        min = 100,
        max = 500,
        value = 300,
        step = 50
      ),

      checkboxInput(
        "use_rag",
        "Use RAG (SPC knowledge base)",
        value = TRUE
      ),

      actionButton("submit", "Generate Response", class = "btn-primary"),
      actionButton("clear_cache", "Clear Cache", class = "btn-warning"),

      hr(),

      h4("Cache Statistics"),
      verbatimTextOutput("cache_stats")
    ),

    mainPanel(
      h4("Response"),
      verbatimTextOutput("response"),

      hr(),

      h4("Session Info"),
      p("This example demonstrates:"),
      tags$ul(
        tags$li("Session-scoped caching (responses cached per user session)"),
        tags$li("RAG-enhanced responses (toggle on/off)"),
        tags$li("Cache statistics (hits, misses, size)"),
        tags$li("Cache clearing")
      ),

      p(
        "Try submitting the same prompt twice - the second response should be ",
        "instant (cache hit)."
      )
    )
  )
)

# Define server
server <- function(input, output, session) {

  # Create session-scoped cache
  # Cache is automatically cleaned up when session ends
  cache <- bfhllm_cache_shiny(session, ttl_seconds = 3600)

  # Reactive value to store response
  response_text <- reactiveVal("")

  # Generate response on button click
  observeEvent(input$submit, {
    # Show loading message
    response_text("Generating response...")

    # Generate response (with or without RAG)
    if (input$use_rag) {
      result <- bfhllm_chat_with_rag(
        question = input$prompt,
        max_chars = input$max_chars,
        cache = cache
      )
    } else {
      result <- bfhllm_chat(
        prompt = input$prompt,
        max_chars = input$max_chars,
        cache = cache
      )
    }

    # Update response
    if (is.null(result)) {
      response_text("Error: Failed to generate response. Check API key and connection.")
    } else {
      response_text(result)
    }
  })

  # Clear cache on button click
  observeEvent(input$clear_cache, {
    cache$clear()
    showNotification("Cache cleared successfully", type = "message")
  })

  # Display response
  output$response <- renderText({
    response_text()
  })

  # Display cache statistics
  output$cache_stats <- renderText({
    stats <- cache$stats()
    paste0(
      "Hits: ", stats$hits, "\n",
      "Misses: ", stats$misses, "\n",
      "Size: ", stats$size, " entries\n",
      "Hit rate: ", round(stats$hits / max(stats$hits + stats$misses, 1) * 100, 1), "%"
    )
  })
}

# Run app
shinyApp(ui = ui, server = server)
