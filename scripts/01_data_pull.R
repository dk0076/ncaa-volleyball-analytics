library(ncaavolleyballr)
library(dplyr)
library(duckdb)

# --- Get contest IDs for all Big West teams ---
# Team names must match ncaavolleyballr exactly. Verify with find_team_id().
big_west_teams <- c(
  "Cal Poly", "UC Santa Barbara", "UC San Diego", "UC Davis",
  "Long Beach St.", "Cal St. Fullerton", "Cal St. Northridge",
  "UC Irvine", "Hawaii", "UC Riverside"
)

schedules <- lapply(big_west_teams, function(team) {
  cat("Getting schedule for", team, "\n")
  tryCatch(
    find_team_id(team, 2024) |> find_team_contests(),
    error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL }
  )
})

all_contests_df <- bind_rows(Filter(Negate(is.null), schedules)) %>%
  select(contest, date) %>%
  distinct()

saveRDS(all_contests_df, "data/big_west_contests.rds")
cat("Total unique contests:", nrow(all_contests_df), "\n")

# --- Pull PBP for each contest ---
pbp_list <- list()
for (i in seq_len(nrow(all_contests_df))) {
  contest_id <- all_contests_df$contest[i]
  cat("Pulling", i, "of", nrow(all_contests_df), "-", contest_id, "\n")
  result <- tryCatch({
    df <- match_pbp(contest = contest_id)
    Sys.sleep(5)
    df
  }, error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    NULL
  })
  pbp_list[[i]] <- result
}

pbp_list <- Filter(Negate(is.null), pbp_list)
pbp_all  <- bind_rows(pbp_list)
cat("Total rows:", nrow(pbp_all), "\n")
cat("Total matches:", length(unique(pbp_all$contestid)), "\n")

# --- Write to DuckDB ---
con <- dbConnect(duckdb(), dbdir = "data/volleyball.duckdb")
dbWriteTable(con, "pbp", pbp_all, overwrite = TRUE)
dbDisconnect(con)
cat("Done.\n")
