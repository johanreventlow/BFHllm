# test-prompts.R
# Tests for Prompt Utilities

test_that("bfhllm_interpolate replaces placeholders", {
  template <- "Hello {{name}}, you are {{age}} years old"
  data <- list(name = "Alice", age = 30)

  result <- bfhllm_interpolate(template, data)
  expect_equal(result, "Hello Alice, you are 30 years old")
})

test_that("bfhllm_interpolate handles spaces in placeholders", {
  template <- "Hello {{ name }}, you are {{ age }} years old"
  data <- list(name = "Bob", age = 25)

  result <- bfhllm_interpolate(template, data)
  expect_equal(result, "Hello Bob, you are 25 years old")
})

test_that("bfhllm_interpolate leaves unknown placeholders unchanged", {
  template <- "Hello {{name}}, you are {{age}} years old"
  data <- list(name = "Charlie")

  result <- bfhllm_interpolate(template, data)
  expect_equal(result, "Hello Charlie, you are {{age}} years old")
})

test_that("bfhllm_interpolate handles NULL values", {
  template <- "Value: {{val}}"
  data <- list(val = NULL)

  result <- bfhllm_interpolate(template, data)
  expect_equal(result, "Value: ")
})

test_that("bfhllm_interpolate validates inputs", {
  expect_error(bfhllm_interpolate(NULL, list()), "template must be")
  expect_error(bfhllm_interpolate("template", "not a list"), "data must be")
})

test_that("bfhllm_build_prompt concatenates components", {
  result <- bfhllm_build_prompt("Part 1", "Part 2", "Part 3", sep = " | ")
  expect_equal(result, "Part 1 | Part 2 | Part 3")
})

test_that("bfhllm_build_prompt filters NULL components", {
  result <- bfhllm_build_prompt("Part 1", NULL, "Part 3")
  expect_equal(result, "Part 1\n\nPart 3")
})

test_that("bfhllm_build_prompt trims whitespace", {
  result <- bfhllm_build_prompt("  Part 1  ", "  Part 2  ", sep = "|")
  expect_equal(result, "Part 1|Part 2")
})

test_that("bfhllm_build_prompt handles empty strings", {
  result <- bfhllm_build_prompt("Part 1", "", "Part 3")
  expect_equal(result, "Part 1\n\nPart 3")
})

test_that("bfhllm_create_structured_prompt builds prompt", {
  result <- bfhllm_create_structured_prompt(
    question = "What is SPC?",
    context = "Statistical Process Control",
    system = "You are an expert",
    format = "Keep it short"
  )

  expect_true(grepl("System:", result))
  expect_true(grepl("Context:", result))
  expect_true(grepl("Question:", result))
  expect_true(grepl("Format:", result))
})

test_that("bfhllm_create_structured_prompt handles optional params", {
  result <- bfhllm_create_structured_prompt(
    question = "What is SPC?"
  )

  expect_true(grepl("Question:", result))
  expect_false(grepl("System:", result))
  expect_false(grepl("Context:", result))
})
