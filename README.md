---
editor_options: 
  markdown: 
    wrap: 72
---

# Big West Volleyball Serve Quality Index

An end-to-end sports analytics pipeline quantifying serve effectiveness
across the Big West Conference using NCAA play-by-play data, XGBoost
modeling, and an interactive R Shiny dashboard.

## Motivation

Pitch quality modeling in baseball — epitomized by Statcast-powered
XGBoost pipelines — chains conditional probabilities to produce a single
interpretable score per pitch. This project applies that framework to
volleyball serving, a skill that lacks standardized analytical metrics
at the collegiate level.

The core question: **what actually drives first-ball-kill outcomes — the
server, or the receiver?**

## Data

-   **Source:** NCAA stats website via the `ncaavolleyballr` R package
-   **Scope:** All matches involving Big West Conference women's
    volleyball teams, 2024 season
-   **Volume:** 225 matches, 44,034 serves, 257,265 play-by-play events
-   **Storage:** DuckDB local analytical database

## Metrics

### Raw Outcomes (from PBP)
- **Ace** — serve lands untouched
- **Service Error** — serve out or into net
- **In Play** — serve returned (not ace or error)
- **FBK Against** — receiving team scored immediately after reception; observed directly from `"First ball kill"` events in the PBP event log

### Server Features (rolling, prior matches only — no data leakage)
- **prior_ace_rate** — server's ace rate in all preceding matches
- **prior_error_rate** — server's error rate in all preceding matches
- **prior_fbk_rate** — server's FBK-against rate in all preceding matches
- **match_ace_rate** — server's ace rate so far in current match
- **match_error_rate** — server's error rate so far in current match

### Receiver / Team Features
- **receiver_prior_fbk_rate** — receiver's historical FBK concession rate
- **opp_prior_fbk_rate** — receiving team's overall historical FBK rate

### Game State Features
- **score_diff** — server score minus receiver score at time of serve
- **set_num** — current set number
- **is_home** — whether the serving team is at home
- **is_late_set** — whether either team's score is ≥ 20

### Model Outputs (XGBoost)
- **P(Ace)** — predicted probability the serve is an ace
- **P(Error)** — predicted probability the serve is an error
- **P(FBK)** — predicted probability of FBK against (in-play serves only)
- **Serve Quality = P(Ace) - P(Error) - P(FBK Against)**

### Scouting Report Metrics
- **FBK Rate (receivers)** — fraction of receptions resulting in FBK against the server; lower = weaker passer = serve target
- **Serve Quality Index (servers)** — average predicted serve quality across all serves
- **Matchup Quality** — serve quality predicted for a specific server × receiver pairing at neutral game state (Set 2, tied score, away)

## Methodology

### Serve Outcome Chain

Each serve results in one of three mutually exclusive outcomes:

```         
P(Ace)                    — serve lands untouched
P(Error)                  — serve out or into net
P(FBK Against | In Play)  — opponent kills on first ball after reception
```

### Serve Quality Index

```         
Serve Quality = P(Ace) - P(Error) - P(FBK Against)
```

Higher scores indicate more effective serving. All scores are negative
in practice because FBK against probability (\~0.29) dominates ace
probability (\~0.057) — scores are meaningful relatively, not
absolutely.

### Feature Engineering

All player-level features are computed from prior matches only to
prevent data leakage. Features split by model:

**Ace and error models (all serves):** - `prior_ace_rate` — server's
historical ace rate in all preceding matches - `prior_error_rate` —
server's historical error rate in all preceding matches -
`match_ace_rate` — server's ace rate so far in the current match -
`match_error_rate` — server's error rate so far in the current match -
`score_diff` — server's score minus receiver's score - `set_num` —
current set number - `is_home` — whether the serving team is at home -
`is_late_set` — whether either team's score is ≥ 20

**FBK model (in-play serves only):** - All features above, plus: -
`receiver_id` — identity of the player receiving the serve -
`receiver_prior_fbk_rate` — receiver's historical FBK concession rate -
`prior_fbk_rate` — server's historical FBK rate against -
`opp_prior_fbk_rate` — receiving team's historical FBK rate

### Modeling

Three XGBoost binary classifiers, one per outcome. Hyperparameters tuned
with 5-fold cross-validation and early stopping (up to 500 rounds,
`eta = 0.05`, `max_depth = 4`). Trained on 205 matches (\~34,000 in-play
serves) and validated on a chronological holdout of 20 matches (\~3,700
serves).

### Validation Results

| Metric           | Value  |
|------------------|--------|
| Baseline logloss | 0.6060 |
| Model logloss    | 0.5483 |
| Improvement      | 0.0577 |
| AUC              | 0.630  |

Out-of-sample AUC of 0.630 indicates meaningful predictive power from
play-by-play data alone, without any tracking inputs.

## Key Findings

**Receiver identity drives FBK outcomes far more than server skill.**

XGBoost feature importance on the held-out test set:

| Feature                   | Gain  |
|---------------------------|-------|
| `receiver_id`             | 81.6% |
| `receiver_prior_fbk_rate` | 4.9%  |
| `opp_prior_fbk_rate`      | 3.3%  |
| `player_id` (server)      | 2.1%  |
| `prior_fbk_rate` (server) | 1.5%  |
| All other features        | 6.6%  |

The receiver alone accounts for 81.6% of model gain. Server identity and
historical rates contribute less than 4% combined. Game state features
(`set_num`, `is_late_set`, `is_home`) are near zero.

**What this means:** a first-ball kill is primarily determined by who
receives the serve, not who serves it. This has direct implications for
how serve quality should be interpreted — a server whose opponents
concede high FBK rates may be benefiting from targeting weak passers
rather than generating serves that are inherently difficult to handle.

**The Serve Quality Index functions as a receiver-adjusted server
rating.** Players who consistently face weak passers are penalized
relative to raw FBK rates; those who face strong passers are credited.
This makes it more useful for cross-opponent comparison than raw
statistics.

This also mirrors a known ceiling in outcome-based sports modeling:
without spatial tracking data (serve location, trajectory, speed), the
model cannot separate server intent from receiver weakness. The
volleyball equivalent of Statcast does not yet exist at the NCAA level.

## Stack

-   **R** — data wrangling, feature engineering, modeling, visualization
-   **DuckDB** — local analytical database queried with SQL
-   **XGBoost** — gradient boosted tree models with CV tuning
-   **R Shiny** — interactive conference-wide serve quality dashboard

## Project Structure

```         
scripts/
  01_data_pull.R           # Pull all Big West schedules and PBP via ncaavolleyballr
  02_sql_explore.R         # SQL analytical queries against DuckDB
  03_feature_engineering.R # Rally-level feature construction (receiver, home/away, etc.)
  04_model.R               # XGBoost training, CV tuning, leaderboard, model artifacts
  05_prior_features.R      # Rolling per-player prior rates (no data leakage)
  06_validation.R          # Chronological holdout validation + feature importance
shiny_app/
  app.R                    # Interactive serve quality dashboard
data/                      # Not tracked in git — generated by scripts
  volleyball.duckdb        # Raw PBP data (257k rows)
  big_west_contests.rds    # Contest metadata with dates (output of 01)
  serves_clean.rds         # Serve-level dataset with receiver and game state (output of 03)
  serves_featured.rds      # With rolling prior rates for all players (output of 05)
  serve_quality.rds        # Model predictions and quality scores (output of 04)
  models.rds               # Trained models and factor encodings (output of 04)
```

## Reproducing the Data

`data/` is not tracked in git. Open the project via
`ncaa-volleyball-analytics.Rproj` (sets the working directory
automatically), then:

**1. Create the data folder**

``` r
dir.create("data", showWarnings = FALSE)
```

**2. Run scripts in order**

``` r
source("scripts/01_data_pull.R")   # live API pull — ~5 sec per match, expect 15–20 min
source("scripts/02_sql_explore.R")
source("scripts/03_feature_engineering.R")
source("scripts/05_prior_features.R")  # must run before 04
source("scripts/04_model.R")
source("scripts/06_validation.R")
```

Script 01 builds the contest list automatically from all Big West team
schedules via `ncaavolleyballr`. Skip it if `data/volleyball.duckdb`
already exists.

**3. Generate a scouting report**

``` r
rmarkdown::render(
  "reports/scouting_report.Rmd",
  params = list(opponent = "UC Santa Barbara"),  # replace with any Big West team
  output_file = "scouting_UCSB.pdf"             # output lands in reports/
)
```

To see valid opponent names:

``` r
serves <- readRDS("data/serves_featured.rds")
sort(unique(c(serves$serve_team, serves$opp_team)))
```

Requires LaTeX for PDF output. If not installed:
`tinytex::install_tinytex()`

**4. Launch the app**

``` r
shiny::runApp("shiny_app")
```

The app defaults to Cal Poly. Use the team dropdown to view any
conference team or select "All Teams" for the full leaderboard.

## Limitations and Future Work

-   **Tracking data** (serve location, type, speed) is the primary
    bottleneck — the model cannot separate server mechanics from
    receiver weakness without it
-   **Receiver targeting** — identifying which player a server is
    targeting, rather than just who received, would add a strategic
    layer currently invisible in PBP data
-   **Multiple seasons** would stabilize ratings for low-volume players
    and enable year-over-year tracking
-   **Bayesian shrinkage** would handle first-match imputation more
    principally than the current global mean fallback
-   **Reception quality grades** (if available via
    DataVolley/VolleyMetrics) would replace the binary FBK outcome with
    a continuous reception quality score

## Author

Drew King — Statistics B.S., Cal Poly SLO Sports Analytics \|
github.com/dk0076
