# SPC Fundamentals: Variation and Chart Structure

## Understanding Variation in Healthcare Data

### Common Cause Variation (Naturlig Variation)

**Definition:** Common cause variation is inherent to a stable process and is predictable. This variation is intrinsic to normal operations and arises from the system itself rather than external factors.

**Key Characteristics:**
- Reflects the normal behavior of the process
- Affects all who are part of the system
- Predictable within statistical limits
- Cannot be eliminated without changing the underlying system

**Danish Terms:** Naturlig variation, systemisk variation

**Example:** Seven identical letters written by the same hand will show minor differences despite identical conditions. This natural variability demonstrates common cause variation.

### Special Cause Variation (Særlig Årsag / Unaturlig Variation)

**Definition:** Special cause variation stems from assignable external factors that disrupt the process's normal state. It presents as an unpredictable signal requiring investigation.

**Key Characteristics:**
- Caused by external, identifiable factors
- Unpredictable in timing and magnitude
- May be favorable or unfavorable
- May be deliberate or incidental
- Requires investigation to understand root cause

**Danish Terms:** Særlig årsag, unaturlig variation, signal

**Example:** The eighth letter written with the non-dominant hand demonstrates special cause variation due to changed circumstances (different hand).

### Improvement Strategy Based on Variation Type

**For Common Cause Variation:**
- Requires modification of the underlying process system
- Cannot be improved by addressing individual data points
- Needs systemic changes to reduce inherent variability

**For Special Cause Variation:**
- Investigate root causes immediately
- Eliminate unfavorable special causes
- Integrate beneficial special causes into standard practice
- Document learnings for future reference

### Foundational SPC Philosophy

SPC is "a way of thinking with some tools attached" focused on:
- Continual improvement rather than specification compliance
- Understanding process behavior over time
- Distinguishing between noise (common cause) and signals (special cause)
- Making data-driven decisions about when to act

## SPC Chart Structure and Components

### Basic Chart Components

All SPC charts share a standardized structure:

**Centre Line (CL) / Centrallinje:**
- Represents the overall mean or median of the data
- Serves as the reference point for detecting shifts
- Danish: Centrallinje, midtlinje

**Control Limits / Kontrolgrænser:**
- Upper Control Limit (UCL) / Øvre kontrolgrænse
- Lower Control Limit (LCL) / Nedre kontrolgrænse
- Positioned three standard deviations (3-sigma) from centre line
- Define natural process variation boundaries
- Not specification limits or targets

**Data Points / Datapunkter:**
- Connected sequentially to show process behavior over time
- Order matters (time-series data)
- Visual pattern reveals process stability

### The 3-Sigma Limit Rationale

Walter Shewhart selected 3-sigma limits because they "work" practically:
- Balance sensitivity for detecting special causes
- Minimize false alarms
- Effective regardless of data distribution type
- Industry standard for decades

## SPC Chart Types: The Magnificent Seven

Chart selection depends on data type (counts vs. measurements) and subgroup structure.

### Count Data Charts (Tællinger)

**C Chart (Count Chart):**
- **Use for:** Event counts with constant opportunity
- **Example:** Patient falls per month, medication errors per week
- **Danish:** C-kort, tællingskort
- **When to use:** Fixed observation period, counting rare events

**U Chart (Rate Chart):**
- **Use for:** Event rates with varying opportunity
- **Example:** Falls per 1,000 patient-days, infections per 100 procedures
- **Danish:** U-kort, rate-kort
- **When to use:** Opportunity varies (different denominators)

**P Chart (Proportion Chart):**
- **Use for:** Case proportions (percentage with attribute)
- **Example:** Percentage of patients experiencing falls, readmission rate
- **Danish:** P-kort, andels-kort
- **When to use:** Binary outcome (yes/no), varying sample sizes acceptable

**Key Distinction:**
- **Events** = Individual occurrences (can happen multiple times to same unit)
- **Cases** = Units possessing an attribute (binary: has attribute or not)

### Measurement Data Charts (Målinger)

**I Chart (Individual Chart) + MR Chart (Moving Range):**
- **Use for:** Individual measurements with subgroup size = 1
- **Example:** Door-to-needle time for each stroke patient, daily bed occupancy
- **Danish:** I-kort, individkort; MR-kort, glidende spredning
- **When to use:** Each data point is a single measurement

**X-bar Chart (Mean Chart) + S Chart (Standard Deviation Chart):**
- **Use for:** Subgroup averages with subgroup size > 1
- **Example:** Average daily door-to-needle times per week, mean weekly blood pressure readings
- **Danish:** X-bar kort, gennemsnitskort; S-kort, spredningskort
- **When to use:** Natural subgroups exist (e.g., shifts, days, weeks)

**X-bar Chart + R Chart (Range Chart):**
- **Alternative to S chart:** Uses range instead of standard deviation
- **When to use:** Small subgroups (typically 2-10 observations)

### Run Charts vs. Control Charts

**Run Chart (Serieplot):**
- Simple point-and-line plot with median line
- Uses runs analysis (Anhøj rules) to detect signals
- No control limits
- Danish: Serieplot, løbediagram

**Control Chart (Kontrolkort):**
- Includes 3-sigma control limits
- Uses both sigma-based rules and runs analysis
- More formal statistical foundation
- Danish: Kontrolkort, SPC-diagram

**Commonality:** Interpretation methods remain consistent across both chart types using statistical rules to identify unusual patterns.

## Chart Selection Guide

| Data Type | Subgroup Size | Chart Type | Danish Term |
|-----------|---------------|------------|-------------|
| Event counts (constant) | N/A | C Chart | C-kort |
| Event rates (varying) | N/A | U Chart | U-kort |
| Proportions | N/A | P Chart | P-kort/Andels-kort |
| Measurements | 1 | I + MR Chart | I-kort + MR-kort |
| Measurements | >1 | X-bar + S Chart | X-bar + S-kort |

## Key Terminology Reference

| English Term | Danish Term | Definition |
|-------------|-------------|------------|
| Common cause variation | Naturlig variation | Inherent process variability |
| Special cause variation | Særlig årsag / Unaturlig variation | Assignable external factors |
| Centre line | Centrallinje | Process mean/median |
| Control limits | Kontrolgrænser | 3-sigma boundaries |
| Run chart | Serieplot | Simple time-series plot |
| Control chart | Kontrolkort | Chart with control limits |
| Signal | Signal | Indicator of special cause |
| Shift | Skift | Sustained process change |
| Trend | Trend | Gradual directional change |
| Freak | Freak / Ekstremværdi | Isolated outlier |

---

**Source:** Jacob Anhøj - "SPC for Healthcare" (https://anhoej.github.io/spc4hc/)
