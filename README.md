## Automatisierte Wettergrafiken im Tufte-Stil für Frankfurt am Main

Dieses Repository erstellt die untenstehenden Wettergrafiken (inspiriert von [Edward Tufte](https://www.edwardtufte.com/bboard/q-and-a-fetch-msg?msg_id=00014g) und [jdjohn215](https://github.com/jdjohn215/milwaukee-weather)). Aktualisierte Daten werden direkt vom Deutschen Wetterdienstes (DWD) bezogen und lokal gespeichert. Der gesamte Prozess wird mithilfe von Github Actions automatisiert.

![Tägliche Höchsttemperatur in Frankfurt am Main](graphs/DailyHighTemp_dwd.png)
![Kumulierter Jahresniederschlag in Frankfurt am Main](graphs/AnnualCumulativePrecipitation_dwd.png)

## Über diese Daten

Die Daten stammen vom Deutschen Wetterdienstes (DWD), das historische tägliche Klimadaten für zahlreiche Wetterstationen in Deutschland bereitstellt. Für dieses Repository werden die Daten der Station **Frankfurt/Main (Stations-ID: 1420)** verwendet.

## Daten für eine andere Station abrufen

Der DWD stellt Daten für viele Wetterstationen in Deutschland bereit. Jede Station hat eine eindeutige Stations-ID. Dieses Repository verwendet die Daten der DWD-Station **Frankfurt/Main** mit der **Stations-ID 1420**.

Um Daten für eine andere Station zu verwenden:

1. Finden Sie die gewünschte Stations-ID über das [DWD CDC Portal](https://cdc.dwd.de/portal/) oder die [Stationslisten](https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/daily/kl/historical/KL_Tageswerte_Beschreibung_Stationen.txt).
2. Passen Sie den Stationsnamen (oder die ID) im Skript `R/Retrieve_dwd.R` an.

Das Skript `R/Retrieve_dwd.R` lädt die historischen und kürzlichen Tagesdaten (`*.zip`) für die angegebene Station vom DWD FTP-Server herunter (gespeichert in `data/dwd_raw/`), verarbeitet diese und speichert die kombinierten, bereinigten Klimadaten im effizienten [Apache Parquet](https://parquet.apache.org/)-Format unter `data/clim_clean.parquet`.

## Grafik replizieren oder anpassen

Die Grafiken werden aus der Datei `data/clim_clean.parquet` generiert:

- Die Grafik `graphs/DailyHighTemp_dwd.png` wird durch das Skript `R/BuildDailyHigh_dwd.R` erstellt.
- Die Grafik `graphs/AnnualCumulativePrecipitation_dwd.png` wird durch das Skript `R/BuildCumulativePrecipitation_dwd.R` erstellt.

## Automatische Aktualisierung mit Github Actions

Der automatisierte Workflow in [/.github/workflows](/.github/workflows) führt regelmäßig folgende Schritte aus:

1. Führt das Skript `R/Retrieve_dwd.R` aus, um die DWD-Daten herunterzuladen und `data/clim_clean.parquet` zu aktualisieren.
2. Führt die Skripte `R/BuildDailyHigh_dwd.R` und `R/BuildCumulativePrecipitation_dwd.R` aus, um die Grafiken im `graphs/`-Ordner neu zu erstellen.
3. Committet die aktualisierte Parquet-Datei (`data/clim_clean.parquet`) und die neuen Grafiken (`graphs/*.png`) in das Repository.

Der gesamte Vorgang dauert pro Durchlauf typischerweise etwa 1-2 Minuten.
