library(xgboost)
library(dplyr)

serves <- readRDS("data/serves_clean.rds")

serves <- serves %>%
  mutate(
    serve_team_id = as.integer(factor(serve_team)),
    player_id     = as.integer(factor(player))
  )

# --- Train/test split by match (not row) ---
# Use last 6 Cal Poly matches as test set, rest as train
all_contests <- unique(serves$contestid)
set.seed(42)
test_contests  <- tail(all_contests, 6)
train_contests <- setdiff(all_contests, test_contests)

train <- serves %>% filter(contestid %in% train_contests)
test  <- serves %>% filter(contestid %in% test_contests)

cat("Train serves:", nrow(train), "\n")
cat("Test serves:", nrow(test), "\n")

features <- c("serve_team_id", "player_id", "set_num", "score_diff")

# --- Validate Model 3: P(FBK Against | In Play) ---
train_ip <- train %>% filter(in_play == 1)
test_ip  <- test  %>% filter(in_play == 1)

X_train <- as.matrix(train_ip[, features])
X_test  <- as.matrix(test_ip[, features])
y_train <- train_ip$fbk_against
y_test  <- test_ip$fbk_against

m3_val <- xgboost(
  x = X_train,
  y = factor(y_train),
  nrounds = 100,
  eval_metric = "logloss"
)

preds <- predict(m3_val, X_test)

# Log-loss
logloss <- function(actual, predicted, eps = 1e-15) {
  predicted <- pmax(pmin(predicted, 1 - eps), eps)
  -mean(actual * log(predicted) + (1 - actual) * log(1 - predicted))
}

# Baseline: always predict the mean
baseline_pred <- rep(mean(y_train), length(y_test))

model_ll   <- logloss(y_test, preds)
baseline_ll <- logloss(y_test, baseline_pred)

cat("\n--- Model 3 Validation (P(FBK Against)) ---\n")
cat("Baseline logloss:", round(baseline_ll, 4), "\n")
cat("Model logloss:   ", round(model_ll, 4), "\n")
cat("Improvement:     ", round(baseline_ll - model_ll, 4), "\n")

# AUC
library(pROC)
roc_obj <- roc(y_test, preds, quiet = TRUE)
cat("AUC:             ", round(auc(roc_obj), 4), "\n")

