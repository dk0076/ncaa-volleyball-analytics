# NCAA Volleyball Serve Quality Index

An end-to-end sports analytics pipeline built to quantify serve effectiveness 
across the Big West Conference using NCAA play-by-play data.

## Motivation

Inspired by pitch quality modeling in baseball (Statcast/XGBoost), this project 
applies a similar chained probability framework to volleyball serving — a skill 
that lacks standardized analytical metrics at the collegiate level.

## Data

- Source: NCAA stats website via the `ncaavolleyballr` R package
- Scope: All Big West Conference women's volleyball matches, 2024 season
- Volume: ~225 matches, ~200,000+ play-by-play events

## Methodology

### Serve Outcome Chain
Each serve results in one of three outcomes:P(Ace) — serve lands untouched
P(Error) — serve out or in net
P(FBK Against | In Play) — opponent kills on first ball after reception

### Serve Quality Index
Serve Quality = P(Ace) - P(Error) - P(FBK Against)

### Modeling
- Three XGBoost binary classifiers, one per outcome
- Features: server historical ace rate, error rate, FBK concession rate 
  (computed from prior matches only to prevent leakage), set number, score differential
- Validated out-of-sample on final 6 matches of the season

### Validation Result
Out-of-sample AUC ≈ 0.51, indicating that contextual features alone have 
limited predictive power. This suggests that tracking data (serve location, 
type, speed) would be necessary for a fully predictive model — analogous to 
the role Statcast plays in baseball pitch quality modeling.

## Stack
- **R** — data wrangling, modeling, visualization
- **DuckDB** — local analytical database, queried with SQL
- **XGBoost** — gradient boosted tree models
- **R Shiny** — interactive dashboard

## Results

Interactive leaderboard ranking every Big West server by Serve Quality Index,
filterable by team and minimum serve threshold.

Key finding: [TO FILL IN after full data pull]

## Structure
scripts/
01_data_pull.R          # API data collection
02_sql_explore.R        # SQL analytical queries
03_feature_engineering.R # Rally-level feature construction
04_model.R              # XGBoost training
05_shiny_app.R          # Interactive dashboard
06_validation.R         # Out-of-sample validation
data/
volleyball.duckdb       # Raw PBP data
serves_clean.rds        # Engineered serve dataset
serves_featured.rds     # With historical player features
serve_quality.rds       # Model predictions

## Author
Drew King — Statistics B.S., Cal Poly SLO  
Sports Analytics | github.com/dk0076