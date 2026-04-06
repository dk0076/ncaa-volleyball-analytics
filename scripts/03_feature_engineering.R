library(duckdb)
library(dplyr)

# --- Load data from DuckDB ---
con <- dbConnect(duckdb(), dbdir = "data/volleyball.duckdb", read_only = TRUE)
pbp <- dbGetQuery(con, "SELECT * FROM pbp")
dbDisconnect(con)

# --- Identify rallies that ended in a first ball kill ---
fbk_rallies <- pbp %>%
  filter(event == "First ball kill") %>%
  select(contestid, set, rally, fbk_team = team)

# --- Build serve-level modeling dataset ---
serves <- pbp %>%
  filter(event %in% c("Serve", "Ace", "Service error")) %>%
  left_join(fbk_rallies, by = c("contestid", "set", "rally")) %>%
  mutate(
    ace            = as.integer(event == "Ace"),
    service_error  = as.integer(event == "Service error"),
    in_play        = as.integer(event == "Serve"),
    fbk_against    = as.integer(!is.na(fbk_team) & fbk_team != team),
    set_num        = as.integer(set),
    score_server   = suppressWarnings(as.integer(sub("-.*", "", score))),
    score_receiver = suppressWarnings(as.integer(sub(".*-", "", score))),
    score_diff     = score_server - score_receiver
  ) %>%
  select(
    contestid, set_num, rally,
    serve_team = team, player,
    ace, service_error, in_play, fbk_against,
    score_diff
  )

# --- Sanity check ---
glimpse(serves)
cat("\nTotal serves:", nrow(serves))
cat("\nAce rate:", round(mean(serves$ace), 3))
cat("\nService error rate:", round(mean(serves$service_error), 3))
cat("\nFBK against rate (in-play only):",
    round(mean(serves$fbk_against[serves$in_play == 1], na.rm = TRUE), 3))
cat("\n")

# --- Save for modeling ---
saveRDS(serves, "data/serves_clean.rds")
cat("Saved to data/serves_clean.rds\n")

