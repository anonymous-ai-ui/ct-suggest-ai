#Define required packages
required_packages <- c(
  "dplyr", "DT", "shiny", "openai", "jsonlite",
  "RCurl", "rlist", "tidyr", "stringr", "purrr", "bslib", "shinyjs"
  )

# Identify packages that are not installed
missing_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]

# Install missing packages
if (length(missing_packages) > 0) {
  install.packages(missing_packages, dependencies = TRUE)
}

# Load required libraries
lapply(required_packages, library, character.only = TRUE)

# install library from github
if (!require("tidyverse")) {
  remotes::install_github("aourednik/SPARQLchunks", build_vignettes = TRUE)
  library(SPARQLchunks)
}  


