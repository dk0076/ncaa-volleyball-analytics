# Big West Volleyball Serve Quality Index

An end-to-end sports analytics pipeline quantifying serve effectiveness across 
the Big West Conference using NCAA play-by-play data, XGBoost modeling, and 
an interactive R Shiny dashboard.

## Motivation

Pitch quality modeling in baseball — epitomized by Statcast-powered XGBoost 
pipelines — chains conditional probabilities to produce a single interpretable 
score per pitch. This project applies that framework to volleyball serving, a 
skill that lacks standardized analytical metrics at the collegiate level.

The core question: **can we predict serve outcomes from contextual features, 
and if not, what does that tell us about the nature of serving in volleyball?**

## Data

- **Source:** NCAA stats website via the `ncaavolleyballr` R package
- **Scope:** All Big West Conference women's volleyball matches, 2024 season
- **Volume:** 225 matches, 44,034 serves, 257,265 play-by-play events
- **Storage:** DuckDB local analytical database

## Methodology

### Serve Outcome Chain

Each serve results in one of three mutually exclusive outcomes:
P(Ace)                    — serve lands untouched
P(Error)                  — serve out or into net
P(FBK Against | In Play)  — opponent kills on first ball after reception

### Serve Quality Index
Serve Quality = P(Ace) - P(Error) - P(FBK Against)

Higher scores indicate more effective serving. All scores are negative in 
practice because FBK against probability (~0.29) dominates ace probability 
(~0.057) — scores are meaningful relatively, not absolutely.

### Feature Engineering

To prevent data leakage, player-level features are computed from prior matches 
only. For each serve, the model sees:

- `prior_ace_rate` — server's historical ace rate in all preceding matches
- `prior_error_rate` — server's historical error rate in all preceding matches  
- `prior_fbk_rate` — server's historical FBK concession rate in all preceding matches
- `set_num` — current set number
- `score_diff` — server's score minus receiver's score at time of serve

### Modeling

Three XGBoost binary classifiers, one per outcome, trained on 205 matches 
(~40,000 serves) and validated on a held-out set of 20 matches (~3,700 serves).

### Validation Results

| Metric | Value |
|---|---|
| Baseline logloss | 0.6075 |
| Model logloss | 0.6203 |
| AUC | 0.517 |

Out-of-sample AUC of 0.517 indicates the model has negligible predictive power 
beyond the historical average baseline. This is the central finding of the project.

## Key Finding

**Serve outcomes in volleyball are not meaningfully predictable from contextual 
features alone.** The model converges to player historical averages, suggesting 
that serve quality is a stable player-level trait but not situationally 
predictable without tracking data — serve location, type, speed, and spin.

This mirrors a known limitation in early baseball analytics before Statcast: 
outcome-based models plateau without spatial and physical tracking inputs. The 
volleyball equivalent of Statcast does not yet exist at the NCAA level.

The Serve Quality Index therefore functions as a **stabilized player rating** 
rather than a situational prediction engine — still analytically useful for 
roster evaluation and opponent scouting.

## Conference Results (Top 10, min. 15 serves)

| Rank | Player | Team | Serves | Quality | P(Ace) | P(FBK Against) |
|---|---|---|---|---|---|---|
| 1 | Maddie Cugino | Gonzaga | 30 | -0.093 | 0.100 | 0.167 |
| 2 | Natalie Glenn | Long Beach St. | 274 | -0.132 | 0.076 | 0.203 |
| 3 | Michelle Zhao | UC Santa Barbara | 90 | -0.138 | 0.075 | 0.210 |
| 4 | Ameena Campbell | Cal St. Fullerton | 61 | -0.158 | 0.074 | 0.205 |
| 5 | Emily McDaniel | UC San Diego | 118 | -0.193 | 0.076 | 0.253 |
| 6 | Grace Stone | CSUN | 85 | -0.201 | 0.084 | 0.271 |
| 7 | Makena Morrison | UC Davis | 341 | -0.209 | 0.062 | 0.267 |

*Natalie Glenn (Long Beach St., 274 serves) and Makena Morrison (UC Davis, 341 serves) 
are the most reliable high-volume servers in the conference.*

## Cal Poly Results

| Rank | Player | Serves | Quality | P(Ace) | P(Error) | P(FBK Against) |
|---|---|---|---|---|---|---|
| 1 | Elif Hurriyet | 429 | -0.228 | 0.063 | 0.011 | 0.280 |
| 2 | Emme Bullis | 373 | -0.233 | 0.066 | 0.011 | 0.288 |
| 3 | Tommi Stockham | 510 | -0.235 | 0.067 | 0.009 | 0.293 |
| 4 | Ella Scott | 319 | -0.252 | 0.062 | 0.016 | 0.297 |
| 5 | Kendall Beshear | 185 | -0.264 | 0.048 | 0.008 | 0.304 |
| 6 | Lizzy Markovska | 266 | -0.264 | 0.047 | 0.009 | 0.303 |
| 7 | London Haberfield | 382 | -0.301 | 0.047 | 0.009 | 0.340 |
| 8 | Samantha Callahan | 46 | -0.309 | 0.063 | 0.077 | 0.296 |

*Tommi Stockham leads Cal Poly in serve volume (510) with the third-best quality 
score. Samantha Callahan has the highest service error rate on the roster (7.7%), 
the most actionable finding for coaching staff.*

## Stack

- **R** — data wrangling, feature engineering, modeling, visualization
- **DuckDB** — local analytical database queried with SQL
- **XGBoost** — gradient boosted tree models for outcome prediction
- **R Shiny** — interactive conference-wide serve quality dashboard

## Project Structure
scripts/
01_data_pull.R             # API data collection, DuckDB storage
02_sql_explore.R           # SQL analytical queries
03_feature_engineering.R   # Rally-level feature construction
04_model.R                 # XGBoost training and leaderboard
05_shiny_app.R             # Interactive Shiny dashboard
06_validation.R            # Out-of-sample validation
data/
volleyball.duckdb          # Raw PBP data (257k rows)
serves_clean.rds           # Engineered serve dataset
serves_featured.rds        # With historical player features
serve_quality.rds          # Model predictions and scores

## Limitations and Future Work

- Tracking data (serve location, type, speed) would substantially improve 
  predictive power — the primary bottleneck identified by validation
- Opponent reception quality as a covariate would contextualize FBK rates 
  against stronger vs weaker passing teams
- Extending to multiple seasons would stabilize player ratings and enable 
  year-over-year tracking
- A Bayesian shrinkage approach would handle low-sample players more 
  appropriately than the current mean imputation

## Author


## Author
Drew King — Statistics B.S., Cal Poly SLO  
Sports Analytics | github.com/dk0076