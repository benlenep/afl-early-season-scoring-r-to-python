# =============================================================================
# AFL Match Data Fetcher — using fitzRoy package
# Fetches game-by-game results for seasons 2016–2026 from AFL Tables
# Output: afl_match_data.csv (same format the Shiny app expects)
#
# SETUP (run once):
#   install.packages(c("fitzRoy", "dplyr", "tidyr"))
#
# USAGE:
#   source("fetch_afl_data.R")
# =============================================================================

library(fitzRoy)
library(dplyr)
library(tidyr)

cat("===========================================\n")
cat("AFL Match Data Fetcher (via fitzRoy)\n")
cat("Seasons: 2016 to 2026\n")
cat("===========================================\n\n")

# ---- 1. Fetch results from AFL Tables ----
# fetch_results_afltables returns:
#   Game, Date, Round, Home.Team, Home.Goals, Home.Behinds, Home.Points,
#   Away.Team, Away.Goals, Away.Behinds, Away.Points, Venue, Margin,
#   Season, Round.Type, Round.Number

cat("Fetching results from AFL Tables (2016-2026)...\n")
cat("This may take a moment on first run as fitzRoy caches the data.\n\n")

raw_results <- fetch_results_afltables(season = 2016:2026)

cat("Fetched", nrow(raw_results), "total matches.\n\n")

# ---- 2. Filter to home-and-away season only (exclude finals) ----
ha_results <- raw_results %>%
  filter(Round.Type == "Regular")

cat("Home-and-away matches:", nrow(ha_results), "\n")

# ---- 3. Nickname lookup ----
nickname_lookup <- c(
  "Adelaide"          = "Crows",
  "Brisbane Lions"    = "Lions",
  "Carlton"           = "Blues",
  "Collingwood"       = "Magpies",
  "Essendon"          = "Bombers",
  "Fremantle"         = "Dockers",
  "Geelong"           = "Cats",
  "Gold Coast"        = "Suns",
  "GWS"               = "Giants",
  "Greater Western Sydney" = "Giants",
  "Hawthorn"          = "Hawks",
  "Melbourne"         = "Demons",
  "North Melbourne"   = "Kangaroos",
  "Port Adelaide"     = "Power",
  "Richmond"          = "Tigers",
  "St Kilda"          = "Saints",
  "Sydney"            = "Swans",
  "West Coast"        = "Eagles",
  "Western Bulldogs"  = "Bulldogs"
)

get_nickname <- function(team) {
  nick <- nickname_lookup[team]
  ifelse(is.na(nick), "", nick)
}

# ---- 4. Transform to match the Shiny app's expected format ----
# 
# OPENING ROUND HANDLING:
# From 2024 onwards, the AFL introduced an "Opening Round" — a partial round 
# (4-5 games) played the week before Round 1 proper. AFL Tables numbers this 
# as Round 1 (labelled "R1"), but we recode it to Round 0 so that:
#   - Seasons 2016-2023: Early season = Rounds 1-6 (no Opening Round)
#   - Seasons 2024+:     Early season = Rounds 0-6 (Opening Round + Rounds 1-6)
#
# Detection: fitzRoy returns no "Opening" text — it's just "R1". So we detect 
# it by counting games: if Round 1 has fewer than 7 games, it's a partial 
# Opening Round. We then recode those games to Round 0 and shift all 
# subsequent round numbers down by 1 for that season.

# Count games per round per season to find partial Round 1s
r1_game_counts <- ha_results %>%
  filter(Round.Number == 1) %>%
  group_by(Season) %>%
  summarise(r1_games = n(), .groups = "drop")

# Seasons where Round 1 has fewer than 7 games = Opening Round
opening_round_seasons <- r1_game_counts %>%
  filter(r1_games < 7) %>%
  pull(Season)

cat("Seasons with Opening Round (R1 < 7 games):", 
    ifelse(length(opening_round_seasons) == 0, "none",
           paste(opening_round_seasons, collapse = ", ")), "\n")

# Show R1 game counts for verification
cat("\nRound 1 game counts by season:\n")
print(r1_game_counts, n = 20)
cat("\n")

match_data <- ha_results %>%
  mutate(
    season         = as.integer(Season),
    home_team      = Home.Team,
    home_nickname  = get_nickname(Home.Team),
    away_team      = Away.Team,
    away_nickname  = get_nickname(Away.Team),
    home_score     = as.integer(Home.Points),
    away_score     = as.integer(Away.Points),
    venue          = Venue,
    
    # Recode round numbers: Opening Round (partial R1) → 0, shift rest down by 1
    is_opening     = (Season %in% opening_round_seasons & Round.Number == 1),
    round          = case_when(
      is_opening ~ 0L,
      Season %in% opening_round_seasons ~ as.integer(Round.Number) - 1L,
      TRUE ~ as.integer(Round.Number)
    ),
    round_name     = case_when(
      is_opening ~ "Opening Round",
      Season %in% opening_round_seasons ~ paste0("R", as.integer(Round.Number) - 1L),
      TRUE ~ Round
    ),
    
    combined_score = home_score + away_score,
    avg_team_score = combined_score / 2,
    margin         = abs(home_score - away_score),
    winning_team   = case_when(
      home_score > away_score ~ home_team,
      away_score > home_score ~ away_team,
      TRUE ~ "Draw"
    ),
    home_100_plus  = home_score >= 100,
    away_100_plus  = away_score >= 100,
    
    # Early season: Rds 0-6 (round <= 6 captures both cases)
    season_phase   = ifelse(round <= 6, "Early (Rds 0-6)", "Mid/Late Season")
  ) %>%
  select(
    season, round, round_name,
    home_team, home_nickname, away_team, away_nickname,
    home_score, away_score, venue,
    combined_score, avg_team_score, margin,
    winning_team, home_100_plus, away_100_plus, season_phase
  ) %>%
  arrange(season, round)

# ---- 5. Write CSV ----
outfile <- "data/afl_match_data.csv"
write.csv(match_data, outfile, row.names = FALSE)

cat("\n===========================================\n")
cat("Done!", nrow(match_data), "H&A games written to", outfile, "\n\n")

# ---- 6. Summary output ----
cat("Games per season:\n")
print(table(match_data$season))

cat("\nRound range per season:\n")
match_data %>%
  group_by(season) %>%
  summarise(
    min_round = min(round),
    max_round = max(round),
    games = n(),
    .groups = "drop"
  ) %>%
  mutate(range = paste0("Rd ", min_round, " - Rd ", max_round, " (", games, " games)")) %>%
  select(season, range) %>%
  print(n = 20)

cat("\nEarly (Rds 0/1-6) vs Rest of Season:\n")
match_data %>%
  group_by(season, season_phase) %>%
  summarise(
    games = n(),
    avg_team_score = round(mean(avg_team_score), 1),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from  = season_phase,
    values_from = c(games, avg_team_score)
  ) %>%
  print(n = 20)

cat("\nCSV is ready. Place it alongside app.R and afl_yearly_averages.csv,\n")
cat("then run: shiny::runApp('app.R')\n")
