# Design: Batch SPC Analysis Generation

**Dato:** 2026-03-17
**Status:** Approved
**Pakker:** BFHllm (batch API + fil-cache), BFHddl (pipeline orkestrering)

---

## Problem

Nuværende flow genererer SPC-analyser via individuelle Gemini API-kald — ét per diagram. Med Gemini Free Tier (RPM=15, RPD=1500) og potentielt hundredvis af diagrammer per kørsel er dette:

- **Langsomt:** 100 diagrammer = ~7 min ventetid (rate limiting)
- **Dyrt på kvote:** 500 diagrammer = 33% af daglig kvote
- **Unødvendigt:** Flash-Lite har stort context window og kan håndtere mange analyser i ét kald

## Løsning

Batch N analyser i ét API-kald via samlet prompt med JSON-output. Grupper á 25 diagrammer per kald.

| Scenario | Uden batching | Med batching (á 25) |
|----------|--------------|---------------------|
| 100 diagrammer | 100 kald, ~7 min, 7% kvote | 4 kald, ~16 sek, 0.3% kvote |
| 500 diagrammer | 500 kald, ~33 min, 33% kvote | 20 kald, ~80 sek, 1.3% kvote |

## Arkitektur

### Pakkeansvar

| Pakke | Ansvar | Ændring |
|-------|--------|---------|
| **BFHllm** | Batch API-kald, fil-cache, prompt-konstruktion, JSON-parsing | Ny funktion |
| **BFHddl** | Tre-pass pipeline, kontekst-samling, bruger-interaktion | Refaktorering |
| **BFHcharts** | Uændret | Ingen |
| **ddl** | Uændret | Ingen |

### Dataflow

```
BFHddl run_pipeline()
  ├─ Fase 5a: Generer charts, saml kontekster i liste
  ├─ Fase 5b: BFHllm::bfhllm_spc_suggestions_batch()
  │   ├─ Tjek fil-cache per diagram (hash-baseret)
  │   ├─ Opdel cache-misses i grupper á 25
  │   ├─ Per gruppe: tjek RPD → byg prompt → ét API-kald → parse JSON
  │   └─ Gem nye resultater i fil-cache
  └─ Fase 5c: Eksporter PDFs med pre-udfyldt metadata$analysis
```

---

## BFHllm: Ny funktion

### `bfhllm_spc_suggestions_batch()`

```r
bfhllm_spc_suggestions_batch <- function(
  contexts,              # Named list: diagram_key -> list(spc_result, llm_context)
  batch_size = 25,       # Antal per API-kald
  use_cache = TRUE,      # Brug fil-cache
  cache_dir = NULL,      # Cache-mappe (default: tempdir())
  force_refresh = FALSE, # Ignorer cache, generer nye
  min_chars = 300,
  max_chars = 375
)
```

**Returnerer:**
```r
list(
  analyses = named list (diagram_key -> tekst),
  from_cache = integer,
  from_api = integer,
  failed = character vector (diagram_keys der fejlede),
  rpd_exhausted = logical
)
```

### Prompt-strategi

Ét prompt per batch med JSON-output:

```
Du er en SPC-ekspert. Generér en kort analyse (300-375 tegn) for hvert
af følgende diagrammer. Svar KUN med valid JSON:
{"1": "analyse...", "2": "analyse...", ...}

Diagram 1 (key: "akdb;akdb_23_002;0_BFH"):
- Chart type: run
- Signals: longest_run=9, crossings=3
- Target: 95%
- Definition: Andel patienter med...

Diagram 2 (key: "dana;dana_04_006;0_BFH"):
...
```

### Fil-cache

```
cache_dir/.bfhllm_cache/
  └─ cache_index.rds    # data.frame: diagram_key, data_hash, analysis, timestamp
```

- **Cache-nøgle:** `digest::digest(list(spc_result, llm_context))` per diagram
- **Invalidering:** Via data-hash, ikke TTL. Ændret data → ny hash → cache miss
- **`force_refresh = TRUE`:** Ignorer cache, send alt til API

### RPD-håndtering

Før hvert batch-kald:
1. `bfhllm_rate_limit_status()` → tjek `rpd_remaining`
2. Hvis `rpd_remaining < batch_size` → sæt `rpd_exhausted = TRUE`, stop batching
3. Returner allerede genererede + cachede analyser
4. BFHddl håndterer bruger-interaktion

---

## BFHddl: Tre-pass pipeline

### Nye parametre til `run_pipeline()`

```r
run_pipeline(
  ...,                        # Eksisterende
  batch_analysis = TRUE,      # Aktiver batch-mode
  force_refresh = FALSE,      # Ignorer cache
  analysis_batch_size = 25    # Antal per API-kald
)
```

### Pass 1: Chart-generering

Eksisterende loop, men gem chart + kontekst i `prepared[[key]]` i stedet for at eksportere straks.

### Pass 2: Batch-analyse

```r
batch_result <- BFHllm::bfhllm_spc_suggestions_batch(
  contexts = lapply(prepared, `[[`, "context"),
  cache_dir = file.path(output_dir, ".bfhllm_cache"),
  force_refresh = force_refresh
)

if (batch_result$rpd_exhausted) {
  svar <- readline("Daglig API-graense naaet. Fortsaet med regelbaserede tekster? (j/n): ")
  if (tolower(svar) != "j") stop("Pipeline afbrudt af bruger")
}
```

### Pass 3: PDF-eksport

```r
for (key in names(prepared)) {
  item <- prepared[[key]]
  item$pdf_metadata$analysis <- batch_result$analyses[[key]]
  BFHcharts::bfh_export_pdf(
    x = item$chart,
    output = item$output_path,
    metadata = item$pdf_metadata,
    auto_analysis = is.null(item$pdf_metadata$analysis)
  )
}
```

### Backward compatibility

- `batch_analysis = FALSE` → single-pass (uændret adfærd)
- PNG-only → spring Pass 2 over
- BFHllm ikke installeret → spring Pass 2 over, Pass 3 bruger fallback
- Gemini API-nøgle mangler → samme som ovenfor

---

## Edge Cases

| Situation | Håndtering |
|-----------|------------|
| BFHllm ikke installeret | Spring Fase 5b over, fallback i 5c |
| JSON-parsing fejler for batch | Log fejl, de diagrammer får fallback |
| Kun PNG-format | Spring Fase 5b+5c over |
| 0 cache-misses | Ingen API-kald |
| `force_refresh = TRUE` | Ignorer cache, send alle til API |
| Diagram fejler i Fase 5a | Udelades fra 5b og 5c |
| RPM nået mid-batch | Eksisterende `rate_limiter_check_and_wait()` venter |
| RPD nået mid-batch | `rpd_exhausted = TRUE`, bruger spørges |
| Tomt svar fra Gemini | Parse-fejl → fallback |

---

## Beslutninger

1. **Batch-størrelse 25:** Balancerer prompt-størrelse vs. antal kald
2. **JSON-output format:** Struktureret, let at parse, Gemini er god til det
3. **Fil-cache uden TTL:** Hash-baseret invalidering er mere præcis
4. **Interaktiv RPD-advarsel:** Bruger beholder kontrol over fallback-beslutning
5. **Tre-pass i stedet for to:** Separerer chart-gen, analyse, eksport cleanly
