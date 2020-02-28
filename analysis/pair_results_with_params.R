library(tidyverse)
library(janitor)
library(here)

params_df <-
  read_csv("sobol_emily.csv") %>%
  rowid_to_column()

results_df <-
  read_csv("sobol-experiment.csv", skip = 6) %>%
  left_join(params_df, by = c("param-line-to-use" = "rowid")) %>%
  clean_names() %>%
  select(-run_number, -param_line_to_use, -load_params_from_file)

write_csv(results_df, "results.csv")