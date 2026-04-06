library(xgboost)
library(dplyr)

serves <- readRDS("data/serves_clean.rds")

serves <- serves %>%
  mutate(
    serve_team_id = as.integer(factor(serve_team)),
    player_id     = as.integer(factor(player))
  )

features <- c("serve_team_id", "player_id", "set_num", "score_diff")
X_all <- as.matrix(serves[, features])

# MODEL 1: P(Ace)
m1 <- xgboost(x = X_all, y = factor(serves$ace), nrounds = 100, eval_metric = "logloss")
serves$p_ace <- predict(m1, X_all)

# MODEL 2: P(Service Error)
m2 <- xgboost(x = X_all, y = factor(serves$service_error), nrounds = 100, eval_metric = "logloss")
serves$p_error <- predict(m2, X_all)

# MODEL 3: P(FBK Against | In Play)
in_play <- serves %>% filter(in_play == 1)
X_fbk   <- as.matrix(in_play[, features])
m3 <- xgboost(x = X_fbk, y = factor(in_play$fbk_against), nrounds = 100, eval_metric = "logloss")
in_play$p_fbk <- predict(m3, X_fbk)

# SERVE QUALITY INDEX
in_play <- in_play %>%
  mutate(serve_quality = p_ace - p_error - p_fbk)

# Leaderboard
leaderboard <- in_play %>%
  group_by(player, serve_team) %>%
  summarise(
    n_serves    = n(),
    avg_quality = round(mean(serve_quality), 3),
    avg_p_ace   = round(mean(p_ace), 3),
    avg_p_error = round(mean(p_error), 3),
    avg_p_fbk   = round(mean(p_fbk), 3),
    .groups = "drop"
  ) %>%
  filter(n_serves >= 10) %>%
  arrange(desc(avg_quality))

print(leaderboard)

saveRDS(list(m1 = m1, m2 = m2, m3 = m3), "data/models.rds")
saveRDS(in_play, "data/serve_quality.rds")
cat("\nDone. Models saved.\n")
