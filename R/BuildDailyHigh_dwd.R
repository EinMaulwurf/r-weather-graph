# Load necessary libraries
library(ggplot2)
library(tidyr)
library(dplyr)
library(lubridate)
library(stringr)
library(ggrepel)

# --- 1. Data Loading and Preparation ---

# Read the file
clim_data_raw <- read.csv2("data/clim_clean.csv")

# Prepare the data structure similar to the original 'ghcn' dataframe
clim_data <- clim_data_raw %>%
  mutate(datum = ymd(datum)) %>%
  # Rename columns to match expectations or make them explicit
  rename(
    date = datum, # Original script used 'date' frequently
    TMAX = temp_max,
    TMIN = temp_min,
    PRCP = nieder
    # 'temp' column from the new data is not used in the original script's logic for this specific plot
  ) %>%
  # Create necessary date components
  mutate(
    year = year(date),
    month = format(date, "%m"), # Character month with leading zero (e.g., "04")
    day = format(date, "%d"), # Character day with leading zero (e.g., "01")
    day_of_year = yday(date),
    date = as.Date(date)
  ) %>%
  arrange(date)

# --- 2. Determine Current Year and Date Range ---

year.to.plot <- max(clim_data$year)
last.date <- max(clim_data$date)
first.date <- min(clim_data$date)

this.year <- clim_data %>%
  filter(year == year.to.plot)

# is this year a leap year?
is.leap.year <- leap_year(this.year$date[1])
leap.year.caption <- "Records for Leap Day (Feb 29) are shown if applicable."

# --- 3. Calculate Historical Summary Statistics ---

daily.summary.stats <- clim_data %>%
  filter(year != year.to.plot) %>%
  # Select relevant columns including the new derived month/day
  select(month, day, PRCP, TMAX, TMIN) %>%
  # Pivot longer using the weather variable names
  pivot_longer(cols = c(PRCP, TMAX, TMIN), names_to = "name", values_to = "value") %>%
  filter(!is.na(value)) %>% # Added filter for NA values before calculating stats
  group_by(month, day, name) %>%
  # Calculate summary stats (check if infinite values are produced if all values are NA)
  summarise(
    max = if (all(is.na(value))) NA else max(value, na.rm = TRUE),
    min = if (all(is.na(value))) NA else min(value, na.rm = TRUE),
    x5 = quantile(value, 0.05, na.rm = TRUE),
    x20 = quantile(value, 0.2, na.rm = TRUE),
    x40 = quantile(value, 0.4, na.rm = TRUE),
    x60 = quantile(value, 0.6, na.rm = TRUE),
    x80 = quantile(value, 0.8, na.rm = TRUE),
    x95 = quantile(value, 0.95, na.rm = TRUE),
    .groups = "drop" # Explicitly drop grouping
  ) %>%
  # Replace Inf/-Inf resulting from all NA with NA
  mutate(across(c(max, min), ~ ifelse(is.infinite(.x), NA, .x))) %>%
  # Create a date column *within the current year* for plotting alignment
  # Use make_date for robustness; ensure month/day are numeric for it
  mutate(
    month_num = as.numeric(month),
    day_num = as.numeric(day)
  ) %>%
  filter(!(month_num == 2 & day_num == 29 & !leap_year(year.to.plot))) %>% # Filter Feb 29 for non-leap target year *before* creating date
  mutate(
    date = make_date(year = year.to.plot, month = month_num, day = day_num),
    day_of_year = yday(date) # Calculate day_of_year based on the plot year's date
  ) %>%
  select(-month_num, -day_num) # Remove temporary numeric month/day

# if the year being plotted is NOT a leap year, remove Feb 29 summaries
# (This check is slightly redundant now but kept for clarity)
if (!is.leap.year) {
  daily.summary.stats <- daily.summary.stats %>%
    filter(!(month == "02" & day == "29"))
  leap.year.caption <- "Records for February 29th are not shown as the year plotted is not a leap year."
}


# --- 4. Determine Record Status for This Year ---

record.status.this.year <- this.year %>%
  select(date, month, day, PRCP, TMAX, TMIN) %>% # Include date for joining if needed later
  pivot_longer(cols = c(PRCP, TMAX, TMIN), names_to = "name", values_to = "this_year") %>%
  # Join with the summary stats based on month, day, and variable name
  inner_join(daily.summary.stats %>% select(month, day, name, min, max),
    by = c("month", "day", "name")
  ) %>%
  mutate(record_status = case_when(
    this_year > max ~ "max",
    this_year < min ~ "min",
    TRUE ~ "none"
  )) %>%
  filter(record_status != "none") %>%
  # Add the date back in for plotting points correctly
  left_join(this.year %>% select(date, month, day), by = c("date", "month", "day"))


# --- 5. Create the Main Plot (Max Temperature Focus) ---

# Define y-axis limits dynamically or use reasonable defaults
# Let's calculate based on observed range +/- buffer
y_min_limit <- ceiling(min(daily.summary.stats$min[daily.summary.stats$name == "TMIN"]) / 10) * 10
y_max_limit <- floor(max(daily.summary.stats$max[daily.summary.stats$name == "TMAX"]) / 10) * 10
y_breaks <- seq(y_min_limit, y_max_limit, 10)

max.graph <- daily.summary.stats %>%
  filter(name == "TMAX") %>%
  ggplot(aes(x = date)) +
  # Historical range ribbons
  geom_ribbon(aes(ymin = min, ymax = max), fill = "#bdc9e1", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(aes(ymin = x5, ymax = x95), fill = "#74a9cf", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(aes(ymin = x20, ymax = x80), fill = "#2b8cbe", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(aes(ymin = x40, ymax = x60), fill = "#045a8d", alpha = 0.8, na.rm = TRUE) +
  # y-axis breaks lines (adjust colour/linewidth if needed)
  # geom_hline(yintercept = y_breaks, color = "white", linewidth = 0.2) +
  geom_hline(yintercept = y_breaks, linetype = "dotted", linewidth = 0.3, colour = "gray") +
  # This year's line
  geom_line(
    data = this.year %>% filter(!is.na(TMAX)), # Ensure no NAs break the line
    aes(y = TMAX), linewidth = 0.8, color = "black"
  ) + # Slightly thinner, black line
  # Points for records set this year
  geom_point(
    data = filter(
      record.status.this.year,
      name == "TMAX",
      record_status == "max"
    ),
    aes(y = this_year), color = "red", size = 2
  ) +
  geom_point(
    data = filter(
      record.status.this.year,
      name == "TMAX",
      record_status == "min"
    ),
    aes(y = this_year), color = "blue", size = 2
  ) +
  # Scales
  scale_y_continuous(
    breaks = y_breaks,
    labels = scales::unit_format(suffix = "°"), # Assuming Celsius or Fahrenheit, adjust if needed
    expand = expansion(mult = 0.01), # Use mult for expansion
    name = NULL,
    sec.axis = dup_axis()
  ) +
  scale_x_date(
    expand = expansion(mult = 0.01), # Use mult for expansion
    # Breaks on the 15th of each month
    breaks = daily.summary.stats$date[daily.summary.stats$day == "15"],
    labels = scales::label_date(format = "%b", locale = "de_DE"),
    # Minor breaks on the 1st of each month
    minor_breaks = daily.summary.stats$date[daily.summary.stats$day == "01"],
    name = NULL
  ) +
  # Labels and Caption
  labs(
    title = paste("Tageshöchsttemperatur in", "Frankfurt am Main"),
    subtitle = paste0(
      "Linie zeigt Tageshöchsttemperatur für ", year.to.plot, ". ",
      "Bänder decken den historischen Bereich ab (", year(first.date), "-", year.to.plot - 1, "). ",
      "Stand ", format(last.date, "%d.%m.%Y.")
    ),
    # caption = paste(
    #   "Records from", format(first.date, "%B %d, %Y"), "to", format(last.date, "%B %d, %Y"), ".",
    #   "Graph updated:", format(Sys.Date(), "%B %d, %Y."),
    #   leap.year.caption
    # )
  ) +
  # Theme
  theme(
    panel.background = element_rect(fill = "linen", colour = NA),
    panel.border = element_blank(),
    panel.grid.major.y = element_blank(),
    panel.grid.minor.y = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_line(linetype = "dotted", linewidth = 0.3, colour = "gray"),
    plot.background = element_rect(fill = "linen", colour = "linen"),
    plot.title.position = "plot",
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 10),
    plot.caption = element_text(size = 8, hjust = 0),
    axis.ticks = element_blank()
  )

# --- 6. Create and Add Custom Legend ---
# !! NB: The positioning of this legend is empirical (days 165-201, vertical shift).
# !! You MAY need to adjust the day_of_year range and the vertical shift
# !! depending on your data's typical values during that period to avoid overlaps.

legend.y.shift <- -30 # <-- Keep your tuned value

# Define the day range for the legend
legend_doy_range <- 170:211 #<--- ADJUST DAY RANGE IF NEEDED

legend.df <- daily.summary.stats %>%
  filter(
    day_of_year %in% legend_doy_range,
    name == "TMAX"
  ) %>%
  # Apply vertical shift for legend placement
  mutate(across(c(max, min, starts_with("x")), ~ .x + legend.y.shift)) %>%
  # Ensure we have data for the days we'll need points for
  filter(!is.na(min) & !is.na(max) & !is.na(x40) & !is.na(x60))

# Define horizontal positions (days) for min/max points in the legend
min_pt_doy <- 177 # <--- Adjust day for min point if needed
max_pt_doy <- 189 # <--- Adjust day for max point if needed

# --- Define the points for the legend's black line ---
# Get the actual shifted min/max values on the chosen days for the line ends
# Add/subtract a tiny bit so the dot is clearly the extreme
min_pt_y_line <- legend.df$min[legend.df$day_of_year == min_pt_doy][1] + 0.5
max_pt_y_line <- legend.df$max[legend.df$day_of_year == max_pt_doy][1] - 0.5

# Get start/end points based on shifted percentiles
start_pt_y <- legend.df$x40[legend.df$day_of_year == min(legend_doy_range)][1]
end_pt_y <- legend.df$x60[legend.df$day_of_year == max(legend_doy_range)][1]

# Get some intermediate points for shape, using shifted percentiles
mid_pt1_doy <- 172
mid_pt1_y <- legend.df$x20[legend.df$day_of_year == mid_pt1_doy][1]
mid_pt2_doy <- 182
mid_pt2_y <- legend.df$x80[legend.df$day_of_year == mid_pt2_doy][1]

# Create a tibble with only the KEY points for the line
legend.line.key.points <- tibble(
  day_of_year = c(min(legend_doy_range), mid_pt1_doy, min_pt_doy, mid_pt2_doy, max_pt_doy, max(legend_doy_range)),
  temp = c(start_pt_y, mid_pt1_y, min_pt_y_line, mid_pt2_y, max_pt_y_line, end_pt_y)
) %>%
  # Remove rows where temp could not be calculated (if data was missing on that day)
  filter(!is.na(temp)) %>%
  # Ensure points are ordered by day_of_year for interpolation
  arrange(day_of_year)

# Interpolate between the key points to create a full line
legend.line.df <- tibble(day_of_year = legend_doy_range) %>%
  mutate(temp = approx(legend.line.key.points$day_of_year, legend.line.key.points$temp, xout = day_of_year)$y) %>%
  mutate(date = make_date(year = year.to.plot, month = 1, day = 1) + days(day_of_year - 1))


# --- Define positions for the annotation DOTS ---
# Place dots slightly outside the line's min/max for visibility
min_pt_y_dot <- legend.df$min[legend.df$day_of_year == min_pt_doy][1] - 0.5
max_pt_y_dot <- legend.df$max[legend.df$day_of_year == max_pt_doy][1] + 0.5
min_pt_date <- make_date(year = year.to.plot, month = 1, day = 1) + days(min_pt_doy - 1)
max_pt_date <- make_date(year = year.to.plot, month = 1, day = 1) + days(max_pt_doy - 1)


# Prepare labels for the ribbon elements (same as before)
legend.labels <- legend.df %>%
  pivot_longer(cols = c(max, min, starts_with("x")), names_to = "levels", values_to = "value") %>%
  mutate(label = case_when(
    levels == "max" ~ "Historisches Max.",
    levels == "min" ~ "Historisches Min.",
    levels == "x95" ~ "95% Perzentil",
    levels == "x80" ~ "80%",
    levels == "x60" ~ "60%",
    levels == "x40" ~ "40%",
    levels == "x20" ~ "20%",
    levels == "x5" ~ "5% Perzentil",
    TRUE ~ levels # Fallback
  )) %>%
  # Position labels at the start/end of the legend range
  mutate(filter_day = ifelse(
    levels %in% c("max", "x80", "x40", "x5"),
    min(day_of_year),
    max(day_of_year)
  )) %>%
  filter(day_of_year == filter_day) %>%
  # Ensure value is not NA before plotting label
  filter(!is.na(value))


## Add legend components to the plot
max.graph2 <- max.graph +
  # Ribbons for the legend area (shifted vertically)
  geom_ribbon(data = legend.df, aes(ymin = min, ymax = max), fill = "#bdc9e1", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(data = legend.df, aes(ymin = x5, ymax = x95), fill = "#74a9cf", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(data = legend.df, aes(ymin = x20, ymax = x80), fill = "#2b8cbe", alpha = 0.8, na.rm = TRUE) +
  geom_ribbon(data = legend.df, aes(ymin = x40, ymax = x60), fill = "#045a8d", alpha = 0.8, na.rm = TRUE) +
  # Line for the current year in the legend area (interpolated between key points)
  geom_line(data = legend.line.df %>% filter(!is.na(temp)), aes(x = date, y = temp), linewidth = 0.8, color = "black") + # Filter NA temps
  # Example record points (DOTS) in the legend
  annotate("point", x = min_pt_date, y = min_pt_y_dot, color = "blue", size = 2.5) +
  annotate("point", x = max_pt_date, y = max_pt_y_dot, color = "red", size = 2.5) +
  annotate("text",
    x = min_pt_date - days(2), # Adjust position relative to dot date
    y = min_pt_y_dot - 2, # Adjust position relative to dot y
    label = "Rekordtief dieses Jahr", hjust = 0, size = 3
  ) +
  annotate("text",
    x = max_pt_date - days(2), # Adjust position relative to dot date
    y = max_pt_y_dot + 2, # Adjust position relative to dot y
    label = "Rekordhoch dieses Jahr", hjust = 0, size = 3
  ) +
  ggrepel::geom_text_repel(
    data = filter(legend.labels, filter_day == max(filter_day)),
    aes(
      x = make_date(year = year.to.plot, month = 1, day = 1) + days(filter_day - 1), # provide x aesthetic
      y = value, label = label
    ),
    min.segment.length = 0, size = 3,
    direction = "y", hjust = 0, nudge_x = 5, # Nudge right
    na.rm = TRUE
  ) + # Add na.rm
  ggrepel::geom_text_repel(
    data = filter(legend.labels, filter_day == min(filter_day)),
    aes(
      x = make_date(year = year.to.plot, month = 1, day = 1) + days(filter_day - 1), # provide x aesthetic
      y = value, label = label
    ),
    min.segment.length = 0, size = 3,
    direction = "y", hjust = 1, nudge_x = -5, # Nudge left
    na.rm = TRUE
  ) # Add na.rm


# --- 7. Save the Plot ---

# Create the directory if it doesn't exist
dir.create("graphs", showWarnings = FALSE)

# Save the final plot
ggsave("graphs/DailyHighTemp_dwd.png",
  plot = max.graph2,
  width = 8, height = 4
)

max.graph2
