library(duckdb)
library(dplyr)

con <- dbConnect(duckdb(), dbdir = "data/volleyball.duckdb", read_only = TRUE)
pbp <- dbGetQuery(con, "SELECT * FROM pbp")
dbDisconnect(con)

# FBK rallies
fbk_rallies <- pbp %>%
  filter(event == "First ball kill") %>%
  select(contestid, set, rally, fbk_team = team)

# Receiver for each in-play rally (first Reception event)
receivers <- pbp %>%
  filter(event == "Reception") %>%
  arrange(contestid, set, rally, rally_event) %>%
  group_by(contestid, set, rally) %>%
  slice(1) %>%
  ungroup() %>%
  select(contestid, set, rally, receiver = player)

# Build serve-level dataset
# home_team and away_team are native pbp columns — no extra join needed
serves <- pbp %>%
  filter(event %in% c("Serve", "Ace", "Service error")) %>%
  left_join(fbk_rallies, by = c("contestid", "set", "rally")) %>%
  left_join(receivers,   by = c("contestid", "set", "rally")) %>%
  mutate(
    ace            = as.integer(event == "Ace"),
    service_error  = as.integer(event == "Service error"),
    in_play        = as.integer(event == "Serve"),
    fbk_against    = as.integer(!is.na(fbk_team) & fbk_team != team),
    set_num        = as.integer(set),
    score_server   = suppressWarnings(as.integer(trimws(sub("-.*", "", score)))),
    score_receiver = suppressWarnings(as.integer(trimws(sub(".*-", "", score)))),
    score_diff     = score_server - score_receiver,
    is_home        = as.integer(team == home_team),
    is_late_set    = as.integer(
      pmax(score_server, score_receiver, na.rm = TRUE) >=
        ifelse(as.integer(set) == 5, 12, 20)
    ),
    opp_team       = ifelse(team == home_team, away_team, home_team)
  ) %>%
  # Within-match rolling counts (excludes current serve)
  arrange(contestid, set_num, rally) %>%
  group_by(contestid, player) %>%
  mutate(
    match_serves_prior = row_number() - 1L,
    match_aces_prior   = cumsum(ace)           - ace,
    match_errors_prior = cumsum(service_error) - service_error
  ) %>%
  ungroup() %>%
  select(
    contestid, set_num, rally,
    serve_team = team, player, receiver, opp_team,
    ace, service_error, in_play, fbk_against,
    score_diff, is_home, is_late_set,
    match_serves_prior, match_aces_prior, match_errors_prior
  )

glimpse(serves)
cat("\nTotal serves:", nrow(serves))
cat("\nAce rate:", round(mean(serves$ace), 3))
cat("\nService error rate:", round(mean(serves$service_error), 3))
cat("\nFBK against rate (in-play only):",
    round(mean(serves$fbk_against[serves$in_play == 1], na.rm = TRUE), 3))
cat("\n")

saveRDS(serves, "data/serves_clean.rds")
cat("Saved to data/serves_clean.rds\n")
