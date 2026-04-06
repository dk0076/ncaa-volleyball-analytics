library(ncaavolleyballr)
library(dplyr)
library(duckdb)

cal_poly_contests <- readRDS("data/cal_poly_contests.rds")
contest_ids <- cal_poly_contests$contest

# Pull in batches of 5 with longer delay
pbp_list <- list()
for (i in seq_along(contest_ids)) {
  cat("Pulling", i, "of", length(contest_ids), "-", contest_ids[i], "\n")
  result <- tryCatch({
    df <- match_pbp(contest = contest_ids[i])
    Sys.sleep(5)
    df
  }, error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    NULL
  })
  pbp_list[[i]] <- result
}

# Remove failed pulls
pbp_list <- Filter(Negate(is.null), pbp_list)
pbp_all <- bind_rows(pbp_list)
cat("Total rows:", nrow(pbp_all), "\n")
cat("Total matches:", length(unique(pbp_all$contestid)), "\n")

# Overwrite DuckDB
con <- dbConnect(duckdb(), dbdir = "data/volleyball.duckdb")
dbWriteTable(con, "pbp", pbp_all, overwrite = TRUE)
dbDisconnect(con)
cat("Done.\n")

