# Exports the Milestone 1 results from R so the Python version can be checked against them.
# Run from the repository root: Rscript r/export_results.R

library(dplyr)
library(tidyr)

match_data <- read.csv("data/afl_match_data.csv", stringsAsFactors = FALSE) %>%
  filter(season <= 2025)

# Result 1: early vs rest of season, by season
season_gap <- match_data %>%
  mutate(phase = ifelse(round <= 6, "early", "rest")) %>%
  group_by(season, phase) %>%
  summarise(avg_team_score = mean(avg_team_score), .groups = "drop") %>%
  pivot_wider(names_from = phase, values_from = avg_team_score, names_prefix = "avg_") %>%
  mutate(drop = avg_rest - avg_early, early_higher = avg_early > avg_rest)
write.csv(season_gap, "r_outputs/season_gap.csv", row.names = FALSE)

# Result 2: early vs rest summary for 2025
phase_2025 <- match_data %>%
  filter(season == 2025) %>%
  mutate(phase = ifelse(round <= 6, "Early (Rds 0-6)", "Rest of Season")) %>%
  group_by(phase) %>%
  summarise(
    games            = n(),
    avg_team_score   = mean(avg_team_score),
    avg_combined     = mean(combined_score),
    avg_margin       = mean(margin),
    pct_100_plus     = mean(home_score >= 100 | away_score >= 100) * 100,
    highest_combined = max(combined_score),
    .groups = "drop"
  )
write.csv(phase_2025, "r_outputs/phase_summary_2025.csv", row.names = FALSE)

cat("Wrote r_outputs/season_gap.csv and r_outputs/phase_summary_2025.csv\n")