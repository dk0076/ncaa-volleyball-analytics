library(duckdb)
library(dplyr)

serves <- readRDS("data/serves_clean.rds")

# --- Get contest dates from DuckDB ---
con <- dbConnect(duckdb(), dbdir = "data/volleyball.duckdb", read_only = TRUE)
cols <- dbListFields(con, "pbp")
if ("date" %in% cols) {
  contests_df <- dbGetQuery(con, "SELECT DISTINCT contestid, date FROM pbp")
} else {
  stop("pbp table has no 'date' column — cannot order contests chronologically.")
}
dbDisconnect(con)

# Save contest metadata for 06_validation.R
big_west_contests <- contests_df %>% rename(contest = contestid)
saveRDS(big_west_contests, "data/big_west_contests.rds")

# Chronological contest order
contest_order <- big_west_contests %>%
  mutate(date_parsed = as.Date(date, "%m/%d/%Y")) %>%
  arrange(date_parsed) %>%
  pull(contest)

serves <- serves %>%
  mutate(contest_idx = match(contestid, contest_order))

# --- Per-player, per-contest aggregates (ace & error over all serves) ---
player_contest_stats <- serves %>%
  group_by(player, contestid, contest_idx) %>%
  summarise(
    n       = n(),
    n_ace   = sum(ace),
    n_error = sum(service_error),
    .groups = "drop"
  )

player_prior_rates <- player_contest_stats %>%
  arrange(player, contest_idx) %>%
  group_by(player) %>%
  mutate(
    cum_n     = cumsum(n) - n,
    cum_ace   = cumsum(n_ace) - n_ace,
    cum_error = cumsum(n_error) - n_error,
    prior_ace_rate   = ifelse(cum_n > 0, cum_ace   / cum_n, NA_real_),
    prior_error_rate = ifelse(cum_n > 0, cum_error / cum_n, NA_real_)
  ) %>%
  ungroup() %>%
  select(player, contestid, prior_ace_rate, prior_error_rate)

# --- FBK prior rate (in-play serves only) ---
player_contest_fbk <- serves %>%
  filter(in_play == 1) %>%
  group_by(player, contestid, contest_idx) %>%
  summarise(
    n_ip  = n(),
    n_fbk = sum(fbk_against),
    .groups = "drop"
  ) %>%
  arrange(player, contest_idx) %>%
  group_by(player) %>%
  mutate(
    cum_n_ip = cumsum(n_ip) - n_ip,
    cum_fbk  = cumsum(n_fbk) - n_fbk,
    prior_fbk_rate = ifelse(cum_n_ip > 0, cum_fbk / cum_n_ip, NA_real_)
  ) %>%
  ungroup() %>%
  select(player, contestid, prior_fbk_rate)

# --- Impute first-match NAs with overall means ---
mean_ace   <- mean(serves$ace)
mean_error <- mean(serves$service_error)
mean_fbk   <- mean(serves$fbk_against[serves$in_play == 1], na.rm = TRUE)

serves_featured <- serves %>%
  left_join(player_prior_rates, by = c("player", "contestid")) %>%
  left_join(player_contest_fbk, by = c("player", "contestid")) %>%
  mutate(
    prior_ace_rate   = ifelse(is.na(prior_ace_rate),   mean_ace,   prior_ace_rate),
    prior_error_rate = ifelse(is.na(prior_error_rate), mean_error, prior_error_rate),
    prior_fbk_rate   = ifelse(is.na(prior_fbk_rate),   mean_fbk,   prior_fbk_rate)
  ) %>%
  select(-contest_idx)

saveRDS(serves_featured, "data/serves_featured.rds")
cat("Saved serves_featured.rds:", nrow(serves_featured), "rows\n")
cat("Saved big_west_contests.rds:", nrow(big_west_contests), "contests\n")
