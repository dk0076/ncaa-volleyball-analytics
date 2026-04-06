library(xgboost)
library(dplyr)

serves <- readRDS("data/serves_featured.rds")

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

# 5-fold CV with early stopping to find optimal rounds
tune_rounds <- function(X, y) {
  cv <- xgb.cv(
    params                = params,
    data                  = xgb.DMatrix(X, label = y),
    nrounds               = 500,
    nfold                 = 5,
    early_stopping_rounds = 20,
    verbose               = 0
  )
  if (length(cv$best_iteration) > 0) {
    cv$best_iteration
  } else {
    which.min(cv$evaluation_log$test_logloss_mean)
  }
}

cat("Tuning M1 (Ace)...\n")
nr1 <- tune_rounds(X_all, serves$ace)
cat("Tuning M2 (Error)...\n")
nr2 <- tune_rounds(X_all, serves$service_error)
cat("Tuning M3 (FBK)...\n")
nr3 <- tune_rounds(X_fbk, in_play$fbk_against)
cat("Best rounds — M1:", nr1, "| M2:", nr2, "| M3:", nr3, "\n")

# ── Train final models ────────────────────────────────────────────────────────
m1 <- xgb.train(params = params, data = xgb.DMatrix(X_all, label = serves$ace),           nrounds = nr1, verbose = 0)
m2 <- xgb.train(params = params, data = xgb.DMatrix(X_all, label = serves$service_error), nrounds = nr2, verbose = 0)
m3 <- xgb.train(params = params, data = xgb.DMatrix(X_fbk, label = in_play$fbk_against),  nrounds = nr3, verbose = 0)

serves$p_ace   <- predict(m1, xgb.DMatrix(X_all))
serves$p_error <- predict(m2, xgb.DMatrix(X_all))
serves$p_in_play <- pmax(0, 1 - serves$p_ace - serves$p_error)

# Predict P(FBK | In Play) on in-play subset, then join back to full serves
# row_id was added before filtering so we can rejoin correctly
in_play <- serves %>% filter(in_play == 1)
in_play$p_fbk <- predict(m3, xgb.DMatrix(as.matrix(in_play[, features_fbk])))

serves <- serves %>%
  left_join(in_play %>% select(row_id, p_fbk), by = "row_id") %>%
  mutate(
    p_fbk         = ifelse(is.na(p_fbk), 0, p_fbk),
    serve_quality = p_ace - p_error - p_in_play * p_fbk
  )

# ── Leaderboard ───────────────────────────────────────────────────────────────
leaderboard <- serves %>%
  group_by(player, serve_team) %>%
  summarise(
    n_serves    = n(),
    avg_quality = round(mean(serve_quality), 3),
    avg_p_ace   = round(mean(p_ace), 3),
    avg_p_error = round(mean(p_error), 3),
    avg_p_fbk   = round(mean(p_fbk[in_play == 1]), 3),
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
    opp_levels      = opp_levels
  ),
  "data/models.rds"
)
saveRDS(serves, "data/serve_quality.rds")
cat("\nDone. Models saved.\n")
