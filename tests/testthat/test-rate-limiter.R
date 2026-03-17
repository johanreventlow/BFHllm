# test-rate-limiter.R
# Tests for rate limiting functionality

# SETUP ========================================================================

# Hjælper: nulstil rate limiter state mellem tests
reset_rate_limiter_state <- function() {
  bfhllm_rate_limit_reset()
}

# RATE LIMITER STATE ===========================================================

test_that("rate limiter initializes with clean state", {
  reset_rate_limiter_state()

  status <- bfhllm_rate_limit_status()

  expect_type(status, "list")
  expect_equal(status$requests_this_minute, 0L)
  expect_equal(status$requests_today, 0L)
  expect_true(is.numeric(status$rpm_remaining))
  expect_true(is.numeric(status$rpd_remaining))
})

test_that("rate limiter status reflects configured limits", {
  reset_rate_limiter_state()

  # Default Free Tier limits
  status <- bfhllm_rate_limit_status()
  config <- bfhllm_get_config()

  expect_equal(status$rpm_limit, config$rate_limit$rpm)
  expect_equal(status$rpd_limit, config$rate_limit$rpd)
  expect_equal(status$rpm_remaining, config$rate_limit$rpm)
  expect_equal(status$rpd_remaining, config$rate_limit$rpd)
})

# RATE LIMITER RESET ===========================================================

test_that("bfhllm_rate_limit_reset clears all state", {
  # Registrer nogle requests
  rate_limiter_record_request()
  rate_limiter_record_request()
  rate_limiter_record_request()

  status_before <- bfhllm_rate_limit_status()
  expect_equal(status_before$requests_today, 3L)

  # Nulstil
  bfhllm_rate_limit_reset()

  status_after <- bfhllm_rate_limit_status()
  expect_equal(status_after$requests_this_minute, 0L)
  expect_equal(status_after$requests_today, 0L)
})

# REQUEST RECORDING ============================================================

test_that("rate_limiter_record_request increments counters", {
  reset_rate_limiter_state()

  rate_limiter_record_request()
  status <- bfhllm_rate_limit_status()
  expect_equal(status$requests_this_minute, 1L)
  expect_equal(status$requests_today, 1L)

  rate_limiter_record_request()
  status <- bfhllm_rate_limit_status()
  expect_equal(status$requests_this_minute, 2L)
  expect_equal(status$requests_today, 2L)
})

# RPM SLIDING WINDOW ===========================================================

test_that("RPM sliding window fjerner gamle timestamps", {
  reset_rate_limiter_state()

  # Indsæt et gammelt timestamp (> 60 sekunder siden)
  old_time <- Sys.time() - 120  # 2 minutter siden
  .bfhllm_rate_limiter$request_timestamps <- list(old_time)
  .bfhllm_rate_limiter$daily_count <- 1L

  # Cleanup bør fjerne det gamle timestamp
  rate_limiter_cleanup_rpm()

  status <- bfhllm_rate_limit_status()
  expect_equal(status$requests_this_minute, 0L)
  # Daglig tæller forbliver (nulstilles kun ved midnat)
  expect_equal(status$requests_today, 1L)
})

# DAILY RESET ==================================================================

test_that("daglig tæller nulstilles ved ny dato", {
  reset_rate_limiter_state()

  # Simuler requests fra i går
  .bfhllm_rate_limiter$daily_count <- 100L
  .bfhllm_rate_limiter$daily_reset_date <- Sys.Date() - 1  # I går

  # Check bør trigge reset
  rate_limiter_reset_daily_if_needed()

  expect_equal(.bfhllm_rate_limiter$daily_count, 0L)
  expect_equal(.bfhllm_rate_limiter$daily_reset_date, Sys.Date())
})

test_that("daglig tæller bevares inden for samme dag", {
  reset_rate_limiter_state()

  .bfhllm_rate_limiter$daily_count <- 50L
  .bfhllm_rate_limiter$daily_reset_date <- Sys.Date()  # I dag

  rate_limiter_reset_daily_if_needed()

  expect_equal(.bfhllm_rate_limiter$daily_count, 50L)
})

# RPM CHECK ====================================================================

test_that("rate_limiter_check returnerer ok når under grænse", {
  reset_rate_limiter_state()

  result <- rate_limiter_check()
  expect_equal(result$allowed, TRUE)
  expect_null(result$wait_seconds)
  expect_null(result$reason)
})

test_that("rate_limiter_check blokerer ved RPM grænse", {
  reset_rate_limiter_state()

  config <- bfhllm_get_config()
  rpm_limit <- config$rate_limit$rpm

  # Fyld op til grænsen
  for (i in seq_len(rpm_limit)) {
    rate_limiter_record_request()
  }

  result <- rate_limiter_check()
  expect_equal(result$allowed, FALSE)
  expect_equal(result$reason, "rpm")
  expect_true(is.numeric(result$wait_seconds))
  expect_true(result$wait_seconds > 0)
  expect_true(result$wait_seconds <= 60)
})

# RPD CHECK ====================================================================

test_that("rate_limiter_check blokerer ved RPD grænse", {
  reset_rate_limiter_state()

  config <- bfhllm_get_config()
  rpd_limit <- config$rate_limit$rpd

  # Simuler at daglig grænse er nået
  .bfhllm_rate_limiter$daily_count <- rpd_limit

  result <- rate_limiter_check()
  expect_equal(result$allowed, FALSE)
  expect_equal(result$reason, "rpd")
})

# BEHAVIOR: WAIT ===============================================================

test_that("rate_limiter_check_and_wait venter ved RPM grænse (behavior=wait)", {
  reset_rate_limiter_state()

  # Konfigurer med lav RPM for at teste hurtigt
  old_config <- bfhllm_get_config()
  bfhllm_configure(rate_limit = list(rpm = 2, rpd = 1500, behavior = "wait"))

  # Fyld RPM
  rate_limiter_record_request()
  rate_limiter_record_request()

  # Indsæt timestamps tæt på udløb (59 sekunder gamle)
  almost_expired <- Sys.time() - 59
  .bfhllm_rate_limiter$request_timestamps <- list(almost_expired, almost_expired)

  # Check bør returnere med kort ventetid
  result <- rate_limiter_check()
  expect_false(result$allowed)
  expect_equal(result$reason, "rpm")
  expect_true(result$wait_seconds <= 2)  # Max 1-2 sekunder

  # Gendan konfiguration
  bfhllm_configure(
    rate_limit = list(
      rpm = old_config$rate_limit$rpm,
      rpd = old_config$rate_limit$rpd,
      behavior = old_config$rate_limit$behavior
    )
  )
})

test_that("rate_limiter_check_and_wait fejler ved RPD grænse (behavior=wait)", {
  reset_rate_limiter_state()

  config <- bfhllm_get_config()
  bfhllm_configure(rate_limit = list(behavior = "wait"))

  # Simuler at daglig grænse er nået
  .bfhllm_rate_limiter$daily_count <- config$rate_limit$rpd

  # Selv i wait mode: RPD giver fejl (kan ikke vente til midnat)
  expect_error(
    rate_limiter_check_and_wait(),
    "Daglige"
  )

  bfhllm_configure(rate_limit = list(behavior = "wait"))
  reset_rate_limiter_state()
})

# BEHAVIOR: DEGRADE ============================================================

test_that("rate_limiter_check_and_wait returnerer fallback ved RPM (behavior=degrade)", {
  reset_rate_limiter_state()

  bfhllm_configure(rate_limit = list(rpm = 2, rpd = 1500, behavior = "degrade"))

  # Fyld RPM
  rate_limiter_record_request()
  rate_limiter_record_request()

  result <- rate_limiter_check_and_wait()
  expect_false(is.null(result))
  expect_true(is.character(result))
  expect_true(grepl("rate limit", result, ignore.case = TRUE))

  # Gendan
  bfhllm_configure(rate_limit = list(rpm = 15, rpd = 1500, behavior = "wait"))
  reset_rate_limiter_state()
})

test_that("rate_limiter_check_and_wait returnerer fallback ved RPD (behavior=degrade)", {
  reset_rate_limiter_state()

  bfhllm_configure(rate_limit = list(rpm = 15, rpd = 1500, behavior = "degrade"))

  # Simuler daglig grænse nået
  .bfhllm_rate_limiter$daily_count <- 1500L

  result <- rate_limiter_check_and_wait()
  expect_true(is.character(result))
  expect_true(grepl("rate limit", result, ignore.case = TRUE))

  # Gendan
  bfhllm_configure(rate_limit = list(rpm = 15, rpd = 1500, behavior = "wait"))
  reset_rate_limiter_state()
})

# CONFIGURATION ================================================================

test_that("rate_limit konfiguration har korrekte defaults", {
  bfhllm_reset_config()
  config <- bfhllm_get_config()

  expect_true(!is.null(config$rate_limit))
  expect_equal(config$rate_limit$enabled, TRUE)
  expect_equal(config$rate_limit$rpm, 15)
  expect_equal(config$rate_limit$rpd, 1500)
  expect_equal(config$rate_limit$behavior, "wait")
})

test_that("rate_limit konfiguration kan ændres via bfhllm_configure", {
  bfhllm_reset_config()

  bfhllm_configure(rate_limit = list(rpm = 100, rpd = 10000, behavior = "degrade"))

  config <- bfhllm_get_config()
  expect_equal(config$rate_limit$rpm, 100)
  expect_equal(config$rate_limit$rpd, 10000)
  expect_equal(config$rate_limit$behavior, "degrade")

  # Gendan
  bfhllm_reset_config()
})

test_that("rate_limit partial update bevarer eksisterende settings", {
  bfhllm_reset_config()

  # Opdater kun rpm
  bfhllm_configure(rate_limit = list(rpm = 30))

  config <- bfhllm_get_config()
  expect_equal(config$rate_limit$rpm, 30)
  expect_equal(config$rate_limit$rpd, 1500)       # Uændret
  expect_equal(config$rate_limit$behavior, "wait") # Uændret

  bfhllm_reset_config()
})

# DISABLED RATE LIMITING =======================================================

test_that("rate limiter kan deaktiveres", {
  reset_rate_limiter_state()

  bfhllm_configure(rate_limit = list(enabled = FALSE))

  # Selv med mange requests, bør check altid tillade
  for (i in 1:20) {
    rate_limiter_record_request()
  }

  result <- rate_limiter_check()
  expect_true(result$allowed)

  # Gendan
  bfhllm_configure(rate_limit = list(enabled = TRUE))
  reset_rate_limiter_state()
})

# STATUS OUTPUT ================================================================

test_that("bfhllm_rate_limit_status returnerer alle forventede felter", {
  reset_rate_limiter_state()

  status <- bfhllm_rate_limit_status()

  expected_fields <- c(
    "requests_this_minute", "requests_today",
    "rpm_limit", "rpd_limit",
    "rpm_remaining", "rpd_remaining",
    "daily_reset_date", "enabled", "behavior"
  )

  for (field in expected_fields) {
    expect_true(field %in% names(status),
      info = paste("Missing field:", field))
  }
})
