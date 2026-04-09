library(xgboost)
library(dplyr)

set.seed(42)  # matches 06_validation.R so CV round counts are comparable

stopifnot("Run 05_prior_features.R before this script" =
            file.exists("data/serves_featured.rds"))

serves       <- readRDS("data/serves_featured.rds")
bwc_contests <- readRDS("data/big_west_contests.rds")

# Factor encoding — build levels from full dataset so 06_validation.R stays consistent
player_levels   <- levels(factor(serves$player))
receiver_levels <- levels(factor(serves$receiver))
opp_levels      <- levels(factor(serves$opp_team))

serves <- serves %>%
  mutate(
    player_id   = as.integer(factor(player,   levels = player_levels)),
    receiver_id = as.integer(factor(receiver, levels = receiver_levels)),
    opp_team_id = as.integer(factor(opp_team, levels = opp_levels))
  )

# Features for ace/error models (all serves — receiver may be NA for aces/errors)
features_base <- c(
  "player_id", "opp_team_id", "set_num", "score_diff",
  "is_home", "is_late_set",
  "prior_ace_rate", "prior_error_rate",
  "match_ace_rate", "match_error_rate"
)

# Features for FBK model (in-play serves only — receiver always present)
features_fbk <- c(
  features_base,
  "receiver_id", "prior_fbk_rate",
  "receiver_prior_fbk_rate", "opp_prior_fbk_rate"
)

# ── Chronological fold assignment (5 folds by contest date) ──────────────────
# Used for OOF predictions so leaderboard quality scores aren't in-sample.
contest_order <- bwc_contests %>%
  mutate(date_parsed = as.Date(date, "%m/%d/%Y")) %>%
  arrange(date_parsed) %>%
  pull(contest)
contest_order <- contest_order[contest_order %in% unique(serves$contestid)]

serves <- serves %>%
  mutate(
    contest_rank = match(as.character(contestid), as.character(contest_order)),
    fold         = ceiling(contest_rank / ceiling(length(contest_order) / 5))
  )

stopifnot("fold NAs — some contestids not in bwc_contests" = !any(is.na(serves$fold)))

serves$row_id <- seq_len(nrow(serves))
in_play <- serves %>% filter(in_play == 1)

X_all <- as.matrix(serves[,  features_base])
X_fbk <- as.matrix(in_play[, features_fbk])

# ── XGBoost hyperparameters ───────────────────────────────────────────────────
params <- list(
  objective        = "binary:logistic",
  eval_metric      = "logloss",
  eta              = 0.05,
  max_depth        = 4,
  subsample        = 0.8,
  colsample_bytree = 0.8
)

# 5-fold CV with early stopping — tune rounds on full data, reuse across OOF folds
tune_rounds <- function(X, y) {
  cv <- xgb.cv(
    params                = params,
    data                  = xgb.DMatrix(X, label = y),
    nrounds               = 500,
    nfold                 = 5,
    early_stopping_rounds = 20,
    verbose               = 0
  )
  if (length(cv$best_iteration) > 0) cv$best_iteration
  else which.min(cv$evaluation_log$test_logloss_mean)
}

cat("Tuning M1 (Ace)...\n")
nr1 <- tune_rounds(X_all, serves$ace)
cat("Tuning M2 (Error)...\n")
nr2 <- tune_rounds(X_all, serves$service_error)
cat("Tuning M3 (FBK)...\n")
nr3 <- tune_rounds(X_fbk, in_play$fbk_against)
cat("Best rounds — M1:", nr1, "| M2:", nr2, "| M3:", nr3, "\n")

# ── OOF predictions (5 chronological folds) ──────────────────────────────────
# Each serve is predicted by a model that never trained on it.
# serve_quality in the leaderboard is based on these — not in-sample.
serves$p_ace_oof   <- NA_real_
serves$p_error_oof <- NA_real_
in_play$p_fbk_oof  <- NA_real_

cat("Computing OOF predictions...\n")
for (k in seq_len(5)) {
  cat("  Fold", k, "of 5\n")
  tr <- serves$fold != k
  te <- serves$fold == k

  m1_k <- xgb.train(params = params, nrounds = nr1, verbose = 0,
                    data = xgb.DMatrix(as.matrix(serves[tr, features_base]),
                                       label = serves$ace[tr]))
  serves$p_ace_oof[te] <- predict(m1_k, xgb.DMatrix(as.matrix(serves[te, features_base])))

  m2_k <- xgb.train(params = params, nrounds = nr2, verbose = 0,
                    data = xgb.DMatrix(as.matrix(serves[tr, features_base]),
                                       label = serves$service_error[tr]))
  serves$p_error_oof[te] <- predict(m2_k, xgb.DMatrix(as.matrix(serves[te, features_base])))

  ip_tr <- in_play$fold != k
  ip_te <- in_play$fold == k
  m3_k <- xgb.train(params = params, nrounds = nr3, verbose = 0,
                    data = xgb.DMatrix(as.matrix(in_play[ip_tr, features_fbk]),
                                       label = in_play$fbk_against[ip_tr]))
  in_play$p_fbk_oof[ip_te] <- predict(m3_k, xgb.DMatrix(as.matrix(in_play[ip_te, features_fbk])))
}

# Join p_fbk_oof back to serves and compute OOF serve_quality
serves <- serves %>%
  left_join(in_play %>% select(row_id, p_fbk_oof), by = "row_id") %>%
  mutate(
    p_fbk_oof     = ifelse(is.na(p_fbk_oof), 0, p_fbk_oof),
    # M1 and M2 are trained independently (binary:logistic), so their probabilities
    # are not constrained to sum to <= 1. pmax(0, ...) clamps the residual.
    p_in_play_oof = pmax(0, 1 - p_ace_oof - p_error_oof),
    # Serve quality: expected-outcome composite with unit weights.
    # Implicit assumption: ace (+1), error (-1), and FBK against (-1 conditional on
    # in-play) are treated as equal in magnitude. In practice an ace ends the rally
    # entirely, while FBK raises the opponent's rally-win probability rather than
    # guaranteeing a point — so this slightly overvalues aces relative to FBK
    # avoidance. A calibrated version would weight by empirical points-won probability
    # per outcome; this formula is the unit-weight baseline.
    serve_quality = p_ace_oof - p_error_oof - p_in_play_oof * p_fbk_oof
  )

n_clamped <- sum((1 - serves$p_ace_oof - serves$p_error_oof) < 0)
if (n_clamped > 0) warning(n_clamped, " serves had p_ace_oof + p_error_oof > 1 before clamping.")

# Global 0-100 quality index for interpretable display.
# Saved to models.rds so scouting report applies identical scaling to new predictions.
quality_min   <- min(serves$serve_quality)
quality_max   <- max(serves$serve_quality)
serves <- serves %>%
  mutate(quality_index = as.integer(round(
    100 * (serve_quality - quality_min) / (quality_max - quality_min)
  )))

# ── Train final full-data models (for scouting report matchup predictions) ───
cat("Training final models on full data...\n")
m1 <- xgb.train(params = params, nrounds = nr1, verbose = 0,
                data = xgb.DMatrix(X_all, label = serves$ace))
m2 <- xgb.train(params = params, nrounds = nr2, verbose = 0,
                data = xgb.DMatrix(X_all, label = serves$service_error))
m3 <- xgb.train(params = params, nrounds = nr3, verbose = 0,
                data = xgb.DMatrix(X_fbk, label = in_play$fbk_against))

# Full-data predictions stored separately — used by scouting report for
# per-server probability display (p_ace, p_error, p_fbk columns)
serves$p_ace   <- predict(m1, xgb.DMatrix(X_all))
serves$p_error <- predict(m2, xgb.DMatrix(X_all))
serves$p_in_play <- pmax(0, 1 - serves$p_ace - serves$p_error)

in_play_final      <- serves %>% filter(in_play == 1)
in_play_final$p_fbk <- predict(m3, xgb.DMatrix(as.matrix(in_play_final[, features_fbk])))
serves <- serves %>%
  left_join(in_play_final %>% select(row_id, p_fbk), by = "row_id") %>%
  mutate(p_fbk = ifelse(is.na(p_fbk), 0, p_fbk))

# ── Leaderboard (OOF quality_index — not in-sample) ──────────────────────────
leaderboard <- serves %>%
  group_by(player, serve_team) %>%
  summarise(
    n_serves    = n(),
    avg_quality = round(mean(quality_index)),
    avg_p_ace   = round(mean(p_ace_oof), 3),
    avg_p_error = round(mean(p_error_oof), 3),
    avg_p_fbk   = round(mean(p_fbk_oof[in_play == 1]), 3),
    .groups = "drop"
  ) %>%
  filter(n_serves >= 10) %>%
  arrange(desc(avg_quality))

print(leaderboard)

saveRDS(
  list(
    m1 = m1, m2 = m2, m3 = m3,
    features_base   = features_base,
    features_fbk    = features_fbk,
    player_levels   = player_levels,
    receiver_levels = receiver_levels,
    opp_levels      = opp_levels,
    quality_min     = quality_min,
    quality_max     = quality_max
  ),
  "data/models.rds"
)
saveRDS(serves %>% select(-contest_rank, -fold), "data/serve_quality.rds")
cat("\nDone. Models saved.\n")
