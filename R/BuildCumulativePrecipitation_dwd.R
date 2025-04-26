# Load necessary libraries
library(ggplot2)
library(tidyr)
library(dplyr)
library(lubridate)
library(stringr)
library(ggrepel) # For geom_label_repel
library(scales) # Explicitly load for date formatting if needed

# --- 1. Data Loading and Preparation ---

# Read the file
clim_data_raw <- read.csv2("data/clim_clean.csv")

# Prepare the data structure
clim_data <- clim_data_raw %>%
  mutate(datum = ymd(datum)) %>%
  # Rename columns
  rename(
    date = datum,
    PRCP = nieder
  ) %>%
  # Ensure data is ordered by date for cumulative sum
  arrange(date) %>%
  # Create necessary date components
  mutate(
    year = year(date),
    month = format(date, "%m"), # Character month with leading zero
    day = format(date, "%d"), # Character day with leading zero
    # Replace NA precipitation with 0 for cumulative sum calculation
    # If NA means truly missing data (not zero precip), this assumption might need review
    PRCP = replace_na(PRCP, 0)
  ) %>%
  # Calculate cumulative precipitation *within each year*
  group_by(year) %>%
  mutate(cum_precip = cumsum(PRCP)) %>%
  ungroup() # Ungroup after calculation
# Add day_of_year AFTER cumsum, just for reference if needed later
# mutate(day_of_year = yday(date)) # Not strictly needed for this plot logic


# --- 2. Determine Current Year and Date Range ---

year.to.plot <- max(clim_data$year)
last.date <- max(clim_data$date[clim_data$year == year.to.plot]) # Ensure last.date is from the year being plotted
first.date <- min(clim_data$date) # Get the earliest date for the caption

# --- 3. Filter Data for Plotting ---

# Data for the year to be plotted as a line
this.year <- clim_data %>%
  filter(year == year.to.plot)

# Identify complete years in the past for historical range calculation
# (Excluding the year currently being plotted)
past.years <- clim_data %>%
  filter(year != year.to.plot) %>%
  add_count(year, name = "days_in_year") %>%
  # Filter for years with at least 365 days to ensure they are complete
  filter(days_in_year >= 365) %>%
  ungroup()

# Check if there are any past years left after filtering
if (nrow(past.years) == 0) {
  stop("No complete past years found in the data to calculate historical ranges.")
}

# --- 4. Calculate Historical Summary Statistics (Grouped by Month/Day) ---

# Calculate stats based on month and day across past years
daily.summary.stats <- past.years %>%
  select(month, day, cum_precip) %>% # Select month/day for grouping
  group_by(month, day) %>%
  # Calculate summary stats for cumulative precipitation for each calendar day
  summarise(
    max = max(cum_precip, na.rm = TRUE),
    min = min(cum_precip, na.rm = TRUE),
    x5 = quantile(cum_precip, 0.05, na.rm = TRUE),
    x20 = quantile(cum_precip, 0.2, na.rm = TRUE),
    x40 = quantile(cum_precip, 0.4, na.rm = TRUE),
    x60 = quantile(cum_precip, 0.6, na.rm = TRUE),
    x80 = quantile(cum_precip, 0.8, na.rm = TRUE),
    x95 = quantile(cum_precip, 0.95, na.rm = TRUE),
    .groups = "drop" # Explicitly drop grouping
  ) %>%
  # Ensure stats are valid numbers
  mutate(across(c(max, min, starts_with("x")), ~ ifelse(is.infinite(.x) | is.nan(.x), NA, .x))) %>% # Handle NaN as well
  # Create a date column *within the plot year* for alignment
  mutate(
    month_num = as.numeric(month),
    day_num = as.numeric(day)
  ) %>%
  # Filter out Feb 29 if the plot year is not a leap year BEFORE creating date
  filter(!(month_num == 2 & day_num == 29 & !leap_year(year.to.plot))) %>%
  mutate(
    # Create date using the plot year for the x-axis mapping
    date = make_date(year = year.to.plot, month = month_num, day = day_num)
  ) %>%
  # !!! REMOVE THE INCORRECT FILTERING BASED ON last.date !!!
  # filter(date <= last.date) %>%  # <<<--- REMOVED THIS LINE
  select(date, month, day, everything(), -month_num, -day_num) %>% # Keep original month/day if needed, ensure date is first
  arrange(date) # Ensure stats are sorted by date for plotting ribbons


# --- 5. Prepare Breaks and Labels for Plot ---

# Percentile labels for the end of the year (last date available in stats)
# This should now correctly be Dec 31 (or Dec 30 if non-leap year plot)
last_stat_date <- max(daily.summary.stats$date, na.rm = TRUE)

pctile.labels <- daily.summary.stats %>%
  filter(date == last_stat_date) %>%
  pivot_longer(cols = c(max, min, starts_with("x")), names_to = "pctile", values_to = "precip") %>%
  mutate(
    pctile = case_when(
      str_sub(pctile, 1, 1) == "x" ~ paste0(str_sub(pctile, 2, -1), "%"),
      pctile == "max" ~ "Max.",
      pctile == "min" ~ "Min.",
      TRUE ~ pctile # Fallback
    ),
    # Store the date for positioning
    label_date = date
  )

# Determine dynamic Y-axis limits based on the FULL historical range
y_max_limit <- ceiling(max(c(daily.summary.stats$max, this.year$cum_precip), na.rm = TRUE) / 100) * 100 # Adjusted divisor for potentially large values
# Keep user's y_break logic, ensure it covers the new max
y_breaks <- seq(0, y_max_limit, by = ifelse(y_max_limit > 1000, 200, 100))

# --- 6. Create the Plot (Using Date on X-axis) ---

cum.precip.graph <- daily.summary.stats %>%
  # Main plot call using date for x-axis from the full year stats
  ggplot(aes(x = date)) +
  # Historical range ribbons mapped to date (will cover the full year)
  geom_ribbon(aes(ymin = min, ymax = max), fill = "#bdc9e1", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(aes(ymin = x5, ymax = x95), fill = "#74a9cf", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(aes(ymin = x20, ymax = x80), fill = "#2b8cbe", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(aes(ymin = x40, ymax = x60), fill = "#045a8d", alpha = 0.8, na.rm = TRUE) +
  # Horizontal lines for reference
  geom_hline(yintercept = y_breaks, linetype = "dotted", linewidth = 0.3, colour = "gray") +
  # This year's cumulative precipitation line (data from 'this.year' stops at last.date)
  geom_line(data = this.year, aes(x = date, y = cum_precip), linewidth = 1, color = "black") +
  # Label for the last point of the current year
  ggrepel::geom_label_repel(
    # Ensure data has rows before trying to filter
    data = if (nrow(this.year) > 0) filter(this.year, date == max(date)) else this.year,
    aes(x = date, y = cum_precip, label = paste(round(cum_precip, 1), "mm")), # Map x=date
    point.padding = unit(1.5, "lines"),
    segment.color = "grey50",
    segment.size = 0.5,
    arrow = arrow(length = unit(0.01, "npc")),
    # Nudging might need slight adjustment based on date scale
    nudge_x = 5, # This value is in days when scale_x_date is used
    nudge_y = 5,
    direction = "y",
    min.segment.length = 0,
    max.overlaps = Inf # Prevent label removal due to overlap with end-of-year labels
  ) +
  # Segments and text for end-of-year percentile labels, positioned by date
  geom_segment(
    data = pctile.labels,
    aes(
      x = label_date + days(1), xend = label_date + days(5), # Extend segment using date calculation
      y = precip, yend = precip
    ),
    color = "grey40"
  ) +
  geom_text(
    data = pctile.labels,
    aes(x = label_date + days(6), y = precip, label = pctile), # Position text using date calculation
    hjust = 0, size = 2.5, color = "grey20"
  ) +
  # Scales
  scale_y_continuous(
    breaks = y_breaks,
    labels = scales::unit_format(suffix = " mm"),
    expand = expansion(mult = c(0.01, 0.05)), # Keep user expansion
    name = NULL
  ) +
  # Use scale_x_date
  scale_x_date(
    breaks = daily.summary.stats$date[daily.summary.stats$day == "15"], # Use the calculated dates for breaks (15th)
    labels = scales::label_date(format = "%b", locale = "de_DE"),
    minor_breaks = daily.summary.stats$date[daily.summary.stats$day == "01"], # Minor breaks at month start
    expand = expansion(mult = c(0.01, 0.03)), # Allow space for end labels; adjust if needed
    name = NULL
  ) +
  # Labels and Caption (Keep user's text)
  labs(
    title = paste("Kumulierter Niederschlag in", "Frankfurt am Main"),
    subtitle = paste0(
      "Linie zeigt kumulierten Niederschlag für ", year.to.plot, ". ",
      "Bänder decken den historischen Bereich ab (", min(past.years$year), "-", max(past.years$year), "). ",
      "Stand ", format(last.date, "%d.%m.%Y.") # Use the actual last date of data for the current year
    ),
    # caption = paste( # Keep caption commented as per user code
    #   "Quelle: Deutscher Wetterdienst.",
    #   "Records from", format(first.date, "%B %d, %Y"), "to", format(last.date, "%B %d, %Y"), ".",
    #   "\nGraph updated:", format(Sys.Date(), "%B %d, %Y."),
    #   "Cumulative totals include Feb 29th in leap years."
    # )
  ) +
  # Theme (Keep user's theme)
  theme(
    panel.background = element_rect(fill = "linen", colour = NA),
    panel.border = element_blank(),
    panel.grid.major.y = element_blank(), # User theme removes grid lines
    panel.grid.minor.y = element_blank(),
    panel.grid.major.x = element_blank(), # User theme removes grid lines
    panel.grid.minor.x = element_line(linetype = "dotted", linewidth = 0.3, colour = "gray"), # Keep minor x grid
    plot.background = element_rect(fill = "linen", colour = "linen"),
    plot.title.position = "plot",
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 10),
    plot.caption = element_text(size = 8, hjust = 0),
    axis.ticks = element_blank() # User theme removes ticks
  )


# --- 7. Save the Plot ---

# Create the directory if it doesn't exist
dir.create("graphs", showWarnings = FALSE)

# Save the plot (Keep user's filename and dimensions)
ggsave("graphs/AnnualCumulativePrecipitation_dwd.png",
  plot = cum.precip.graph,
  width = 8, height = 4
)

# cum.precip.graph
