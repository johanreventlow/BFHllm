# Anhøj Rules and Tests for Special Cause Variation

## Overview

Anhøj's approach to detecting special cause variation emphasizes **runs analysis** as a complement to traditional sigma-based rules. This methodology:

- Adapts dynamically to varying dataset sizes (10+ data points)
- Requires fewer assumptions than classical control chart methods
- Maintains sensitivity and specificity regardless of sample size
- Complements 3-sigma rules for comprehensive signal detection

**Danish Terms:** Anhøj regler, Anhøjs tests, signaltest

## The Three Types of Special Cause Patterns

### 1. Freaks (Freaks / Ekstremværdier)

**Definition:** Isolated transient deviations from normal process behavior.

**Characteristics:**
- Single data points outside control limits
- No sustained pattern
- Typically caused by sampling errors, measurement issues, or one-time events
- May not require process investigation if isolated

**Visual Convention:** Red data points outside UCL or LCL

**Danish Terms:** Freak, ekstremværdi, outlier

**Interpretation:** Investigate if clinically significant, but recognize these may be random occurrences within 3-sigma limits probability (0.27% false alarm rate).

### 2. Shifts (Skift)

**Definition:** Sudden, sustained changes in process behavior indicating a new process level.

**Characteristics:**
- Process moves to new stable state
- Multiple consecutive points on same side of centre line
- Indicates fundamental process change occurred
- Requires investigation to identify root cause

**Visual Convention:** Centre line turns red and dashed when shift detected

**Danish Terms:** Skift, niveauændring, procesændring

**Interpretation:** Critical signal requiring investigation. May indicate:
- Improvement (if shift is favorable)
- Deterioration (if shift is unfavorable)
- Process change that needs documentation and understanding

### 3. Trends (Trends)

**Definition:** Gradual directional changes in process center over time.

**Characteristics:**
- Progressive movement in one direction
- Slower than shifts, but persistent
- May indicate gradual process degradation or improvement

**Visual Convention:** Centre line turns red and dashed when trend detected

**Danish Terms:** Trend, gradvis ændring, retning

**Interpretation:** Investigate before trend becomes problematic. Early detection allows proactive intervention.

## Anhøj Detection Rules

### Rule 1: Unusually Long Runs (Serielængde)

**Definition:** A run is "one or more consecutive data points on the same side of the centre line."

**Detection Formula:**
```
Critical threshold = log₂(n) + 3 (rounded to nearest integer)
where n = useful data points (excluding points exactly on centre line)
```

**Examples:**
- 24 data points → runs exceeding 8 points suggest shift
- 10 data points → runs exceeding 6 points suggest shift
- 100 data points → runs exceeding 10 points suggest shift

**Interpretation:**
- Run length at or above threshold = special cause signal
- Indicates sustained shift in process level
- Direction matters: run above median = improvement (for positive metrics)

**Danish Terms:** Serielængde, run, række

**Why It Works:**
- Dynamically adjusts sensitivity based on dataset size
- More data = higher threshold (avoiding false alarms)
- Fewer data = lower threshold (maintaining sensitivity)

### Rule 2: Unusually Few Crossings (Krydsninger)

**Definition:** Crossings represent transitions where consecutive data points fall on opposite sides of the centre line.

**Detection Formula:**
```
Lower prediction limit = qbinom(p = 0.05, size = n-1, prob = 0.5)
```

**Interpretation:**
- Fewer crossings than lower limit = special cause signal
- Indicates sustained shift rather than random variation
- Complements runs test by detecting lack of oscillation

**Danish Terms:** Krydsninger, antal krydsninger, crossings

**Why It Works:**
- Under random variation, ~50% of consecutive points cross centre line
- Shifts reduce crossings dramatically
- Binomial distribution provides objective threshold

### Rule 3: Astronomical Points (3-Sigma Rule)

**Definition:** Data points falling outside 3-sigma control limits.

**Detection:**
- Any point > UCL or < LCL
- Probability of false alarm: 0.27% (assuming normality)

**Interpretation:**
- Large, transient deviations from process mean
- May indicate measurement error, data coding issue, or genuine extreme event
- Investigate if clinically or operationally significant

**Danish Terms:** Ekstremværdi, punkt udenfor kontrolgrænser

## Runs Analysis vs. Western Electric Rules

**Advantages of Anhøj's Approach:**

1. **Adaptive Sensitivity:**
   - Western Electric rules lose sensitivity with <20 data points
   - Western Electric rules lose specificity with >30 data points
   - Anhøj's rules adapt dynamically across 10+ observations

2. **Fewer Assumptions:**
   - No normality assumption required for runs analysis
   - Works with median (robust to skewness)
   - Suitable for small datasets

3. **Lower False Alarm Rate:**
   - Runs analysis combined with 3-sigma: ~5% false alarm rate
   - Western Electric rules alone: higher false positive risk

## Recommended Detection Strategy

**Sequential Approach (Anhøj's Recommendation):**

1. **Start with Run Chart:**
   - Use median as centre line (assumption-free)
   - Apply runs analysis (long runs + few crossings tests)
   - Detect persistent shifts first

2. **Add Control Limits (if needed):**
   - Calculate 3-sigma limits for mean-based chart
   - Identify large transient deviations (freaks)
   - Complement runs analysis

3. **Combined Interpretation:**
   - Both runs tests AND astronomical points
   - Prioritize persistent signals (shifts/trends) over freaks
   - Context matters: clinical significance trumps statistical significance

## Practical Application in SPCify

SPCify uses **qicharts2** for Anhøj rules calculation:

```r
# Metadata extracted from qicharts2::qic()
- n.crossings: Number of crossings
- n.runs: Longest run length
- runs.signal: TRUE if unusually long run detected
- sigma.signal: TRUE if point outside 3-sigma limits
```

**Integration with BFHcharts:**
- BFHcharts handles visualization
- qicharts2 provides Anhøj rules detection
- SPCify combines both for comprehensive SPC analysis

## Signal Interpretation Framework

### When Shift Signal Detected (Run or Few Crossings):

**Questions to Ask:**
1. **What changed?** Identify events coinciding with shift timing
2. **Is it favorable or unfavorable?** Direction relative to target
3. **Is it sustained?** Check subsequent data points
4. **What's the root cause?** Use Pyramid Model for investigation

### When Freak Detected (3-Sigma):

**Questions to Ask:**
1. **Is it a data error?** Check coding, documentation, definitions
2. **Is it clinically significant?** Context matters more than statistics
3. **Is it isolated?** Single point or part of pattern?
4. **Should we investigate?** Balance effort with potential insight

## Summary Table: Anhøj Rules

| Rule | Danish Term | Formula | Detects | Action |
|------|-------------|---------|---------|--------|
| Long run | Serielængde | log₂(n) + 3 | Shifts | Investigate timing, identify cause |
| Few crossings | Få krydsninger | qbinom(0.05, n-1, 0.5) | Shifts | Same as long run |
| 3-sigma | Ekstremværdi | ±3σ from mean | Freaks | Check data quality, assess clinical significance |

## Key Terminology Reference

| English | Danish | Definition |
|---------|--------|------------|
| Run | Serielængde / Run / Række | Consecutive points on same side of centre line |
| Crossings | Krydsninger | Transitions across centre line |
| Shift | Skift | Sustained change in process level |
| Trend | Trend | Gradual directional change |
| Freak | Freak / Ekstremværdi | Point outside 3-sigma limits |
| Signal | Signal | Statistical indicator of special cause |
| False alarm | Falsk alarm | Signal due to random variation, not special cause |

---

**Source:** Jacob Anhøj - "SPC for Healthcare" (https://anhoej.github.io/spc4hc/)
**Implementation:** qicharts2 R package (https://cran.r-project.org/package=qicharts2)
