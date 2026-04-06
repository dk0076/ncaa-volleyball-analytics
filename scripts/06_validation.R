library(xgboost)
library(dplyr)
library(pROC)

serves_featured  <- readRDS("data/serves_featured.rds")
all_contests_df  <- readRDS("data/big_west_contests.rds")
model_artifacts  <- readRDS("data/models.rds")

# Consistent factor encoding using levels saved by 04_model.R
serves_featured <- serves_featured %>%
  mutate(
    player_id   = as.integer(factor(player,   levels = model_artifacts$player_levels)),
    receiver_id = as.integer(factor(receiver, levels = model_artifacts$receiver_levels)),
    opp_team_id = as.integer(factor(opp_team, levels = model_artifacts$opp_levels))
  )

# Chronological contest order
contest_order <- all_contests_df %>%
  mutate(date = as.Date(date, "%m/%d/%Y")) %>%
  arrange(date) %>%
  pull(contest) %>%
  unique()
contest_order <- contest_order[contest_order %in% unique(serves_featured$contestid)]

# Last 20 matches as holdout test set
test_contests  <- tail(contest_order, 20)
train_contests <- setdiff(contest_order, test_contests)

train <- serves_featured %>% filter(contestid %in% train_contests)
test  <- serves_featured %>% filter(contestid %in% test_contests)
cat("Train:", nrow(train), "| Test:", nrow(test), "\n")

features_fbk <- model_artifacts$features_fbk

train_ip <- train %>% filter(in_play == 1)
test_ip  <- test  %>% filter(in_play == 1)

X_train <- as.matrix(train_ip[, features_fbk])
X_test  <- as.matrix(test_ip[,  features_fbk])
y_train <- train_ip$fbk_against
y_test  <- test_ip$fbk_against

# ── CV tuning on training set ─────────────────────────────────────────────────
params <- list(
  objective        = "binary:logistic",
  eval_metric      = "logloss",
  eta              = 0.05,
  max_depth        = 4,
  subsample        = 0.8,
  colsample_bytree = 0.8
)

cv <- xgb.cv(
  params                = params,
  data                  = xgb.DMatrix(X_train, label = y_train),
  nrounds               = 500,
  nfold                 = 5,
  early_stopping_rounds = 20,
  verbose               = 0
)

best_rounds <- if (length(cv$best_iteration) > 0) {
  cv$best_iteration
} else {
  which.min(cv$evaluation_log$test_logloss_mean)
}

m3_val <- xgb.train(
  params  = params,
  data    = xgb.DMatrix(X_train, label = y_train),
  nrounds = best_rounds,
  verbose = 0
)

preds <- predict(m3_val, xgb.DMatrix(X_test))

logloss <- function(actual, predicted, eps = 1e-15) {
  predicted <- pmax(pmin(predicted, 1 - eps), eps)
  -mean(actual * log(predicted) + (1 - actual) * log(1 - predicted))
}

baseline_ll <- logloss(y_test, rep(mean(y_train), length(y_test)))
model_ll    <- logloss(y_test, preds)
roc_obj     <- pROC::roc(y_test, preds, quiet = TRUE)

cat("\n--- Validation: P(FBK Against) ---\n")
cat("Baseline logloss:", round(baseline_ll, 4), "\n")
cat("Model logloss:   ", round(model_ll,    4), "\n")
cat("Improvement:     ", round(baseline_ll - model_ll, 4), "\n")
cat("AUC:             ", round(pROC::auc(roc_obj), 4), "\n")

cat("\nTop features:\n")
print(xgb.importance(model = m3_val))
