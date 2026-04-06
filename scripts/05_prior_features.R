library(dplyr)

serves            <- readRDS("data/serves_clean.rds")
big_west_contests <- readRDS("data/big_west_contests.rds")

# Chronological contest order
contest_order <- big_west_contests %>%
  mutate(date_parsed = as.Date(date, "%m/%d/%Y")) %>%
  arrange(date_parsed) %>%
  pull(contest)

serves <- serves %>%
  mutate(contest_idx = match(as.character(contestid), as.character(contest_order)))

stopifnot("contest_idx all NA — type mismatch between contestid and contest_order" =
            !all(is.na(serves$contest_idx)))

# ── Server prior ace / error rates (all serves) ───────────────────────────────
player_contest_stats <- serves %>%
  group_by(player, contestid, contest_idx) %>%
  summarise(n = n(), n_ace = sum(ace), n_error = sum(service_error), .groups = "drop")

server_prior <- player_contest_stats %>%
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

# ── Server prior FBK rate (in-play serves only) ───────────────────────────────
server_fbk <- serves %>%
  filter(in_play == 1) %>%
  group_by(player, contestid, contest_idx) %>%
  summarise(n_ip = n(), n_fbk = sum(fbk_against), .groups = "drop") %>%
  arrange(player, contest_idx) %>%
  group_by(player) %>%
  mutate(
    cum_n_ip = cumsum(n_ip) - n_ip,
    cum_fbk  = cumsum(n_fbk) - n_fbk,
    prior_fbk_rate = ifelse(cum_n_ip > 0, cum_fbk / cum_n_ip, NA_real_)
  ) %>%
  ungroup() %>%
  select(player, contestid, prior_fbk_rate)

# ── Receiver prior FBK rate (in-play serves, keyed on receiver) ───────────────
receiver_fbk <- serves %>%
  filter(in_play == 1, !is.na(receiver)) %>%
  group_by(receiver, contestid, contest_idx) %>%
  summarise(n_ip = n(), n_fbk = sum(fbk_against), .groups = "drop") %>%
  arrange(receiver, contest_idx) %>%
  group_by(receiver) %>%
  mutate(
    cum_n_ip = cumsum(n_ip) - n_ip,
    cum_fbk  = cumsum(n_fbk) - n_fbk,
    receiver_prior_fbk_rate = ifelse(cum_n_ip > 0, cum_fbk / cum_n_ip, NA_real_)
  ) %>%
  ungroup() %>%
  select(receiver, contestid, receiver_prior_fbk_rate)

# ── Opponent team prior FBK rate ──────────────────────────────────────────────
opp_team_fbk <- serves %>%
  filter(in_play == 1) %>%
  group_by(opp_team, contestid, contest_idx) %>%
  summarise(n_ip = n(), n_fbk = sum(fbk_against), .groups = "drop") %>%
  arrange(opp_team, contest_idx) %>%
  group_by(opp_team) %>%
  mutate(
    cum_n_ip = cumsum(n_ip) - n_ip,
    cum_fbk  = cumsum(n_fbk) - n_fbk,
    opp_prior_fbk_rate = ifelse(cum_n_ip > 0, cum_fbk / cum_n_ip, NA_real_)
  ) %>%
  ungroup() %>%
  select(opp_team, contestid, opp_prior_fbk_rate)

# ── Imputation means ──────────────────────────────────────────────────────────
mean_ace   <- mean(serves$ace)
mean_error <- mean(serves$service_error)
mean_fbk   <- mean(serves$fbk_against[serves$in_play == 1], na.rm = TRUE)

# ── Combine all features ──────────────────────────────────────────────────────
serves_featured <- serves %>%
  left_join(server_prior,  by = c("player", "contestid")) %>%
  left_join(server_fbk,    by = c("player", "contestid")) %>%
  left_join(receiver_fbk,  by = c("receiver", "contestid")) %>%
  left_join(opp_team_fbk,  by = c("opp_team", "contestid")) %>%
  mutate(
    prior_ace_rate          = ifelse(is.na(prior_ace_rate),          mean_ace,   prior_ace_rate),
    prior_error_rate        = ifelse(is.na(prior_error_rate),        mean_error, prior_error_rate),
    prior_fbk_rate          = ifelse(is.na(prior_fbk_rate),          mean_fbk,   prior_fbk_rate),
    receiver_prior_fbk_rate = ifelse(is.na(receiver_prior_fbk_rate), mean_fbk,   receiver_prior_fbk_rate),
    opp_prior_fbk_rate      = ifelse(is.na(opp_prior_fbk_rate),      mean_fbk,   opp_prior_fbk_rate),
    # Within-match rates — impute first serve of match with career prior
    match_ace_rate   = ifelse(
      match_serves_prior > 0,
      match_aces_prior / match_serves_prior,
      prior_ace_rate
    ),
    match_error_rate = ifelse(
      match_serves_prior > 0,
      match_errors_prior / match_serves_prior,
      prior_error_rate
    )
  ) %>%
  select(-contest_idx, -match_serves_prior, -match_aces_prior, -match_errors_prior)

saveRDS(serves_featured, "data/serves_featured.rds")
cat("Saved serves_featured.rds:", nrow(serves_featured), "rows\n")
