library(xgboost)
library(dplyr)
library(pROC)

serves_featured <- readRDS("data/serves_featured.rds")
all_contests_df <- readRDS("data/big_west_contests.rds")

# Sort contests chronologically
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

features <- c("prior_ace_rate", "prior_error_rate", "prior_fbk_rate", "set_num", "score_diff")

train_ip <- train %>% filter(in_play == 1)
test_ip  <- test  %>% filter(in_play == 1)

X_train <- as.matrix(train_ip[, features])
X_test  <- as.matrix(test_ip[, features])
y_train <- train_ip$fbk_against
y_test  <- test_ip$fbk_against

m3_val <- xgboost(x = X_train, y = factor(y_train), nrounds = 100, eval_metric = "logloss")
preds  <- predict(m3_val, X_test)

logloss <- function(actual, predicted, eps = 1e-15) {
  predicted <- pmax(pmin(predicted, 1 - eps), eps)
  -mean(actual * log(predicted) + (1 - actual) * log(1 - predicted))
}

baseline_ll <- logloss(y_test, rep(mean(y_train), length(y_test)))
model_ll    <- logloss(y_test, preds)
roc_obj     <- pROC::roc(y_test, preds, quiet = TRUE)

cat("\n--- Validation: P(FBK Against) ---\n")
cat("Baseline logloss:", round(baseline_ll, 4), "\n")
cat("Model logloss:   ", round(model_ll, 4), "\n")
cat("Improvement:     ", round(baseline_ll - model_ll, 4), "\n")
cat("AUC:             ", round(pROC::auc(roc_obj), 4), "\n")
