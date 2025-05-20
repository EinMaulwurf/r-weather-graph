library(dplyr)
library(rdwd) # Muss aktuellste Version sein! Version von CRAN eventuell veraltet. Verwende rdwd::updateRdwd() oder installiere von GitHub.

# findID("Frankfurt/Main", exactmatch = FALSE) # 1420

# rdwd::selectDWD() is currently broken
# see https://github.com/brry/rdwd/issues/47#issuecomment-2893840683
# I'm setting the links manually
# link <- selectDWD("Frankfurt/Main", res = "daily", var = "kl", per = "hr")

link <- c(
  "ftp://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/daily/kl/historical/tageswerte_KL_01420_19350701_20241231_hist.zip", 
  "ftp://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/daily/kl/recent/tageswerte_KL_01420_akt.zip"
)

file <- dataDWD(link, read = FALSE, dir = "data", force = TRUE)
clim <- readDWD(file, varnames = TRUE, hr = 4)

clim_clean <- clim %>%
  as_tibble() %>%
  janitor::clean_names() %>%
  select(
    datum = mess_datum,
    temp = tmk_lufttemperatur,
    temp_min = tnk_lufttemperatur_min,
    temp_max = txk_lufttemperatur_max,
    nieder = rsk_niederschlagshoehe
  )

write.csv2(clim_clean, "data/clim_clean.csv")
