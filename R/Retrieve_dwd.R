# rdwd::updateRdwd() # Wichtig, sonst werden die korrekten Dateien nicht gefunden!

library(dplyr)
library(rdwd) # Muss aktuellste Version sein!

# findID("Frankfurt/Main", exactmatch = FALSE)

link <- selectDWD("Frankfurt/Main", res = "daily", var = "kl", per = "hr")
file <- dataDWD(link, read = FALSE, dir = "data")
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

saveRDS(clim_clean, "data/clim_clean.rds")
