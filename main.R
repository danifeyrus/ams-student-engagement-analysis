# AMS project: Learning Engagement Profiles and Course Outcomes
# Full reproducible pipeline. Run from the repository root.

args <- commandArgs(trailingOnly = TRUE)
demo_mode <- "--demo" %in% args

required_packages <- c("data.table", "ggplot2", "mclust", "tclust", "clue", "scales", "cluster")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages)) {
  stop(
    paste0(
      "Missing required packages: ", paste(missing_packages, collapse = ", "),
      ". Run renv::restore() from the project root."
    ),
    call. = FALSE
  )
}

source(file.path("src", "00_utils.R"))
source(file.path("src", "00_acquire_data.R"))
library(data.table)

if (demo_mode) {
  source(file.path("src", "exam_demo.R"))
  run_exam_demo()
} else {
  library(ggplot2)
  library(mclust)
  library(tclust)
  library(clue)

  source(file.path("src", "01_validate_prepare.R"))
  source(file.path("src", "02_eda.R"))
  source(file.path("src", "03_model_based_clustering.R"))
  source(file.path("src", "04_outcomes.R"))
  source(file.path("src", "05_robustness.R"))
  source(file.path("src", "07_independent_statistical_audit.R"))
  source(file.path("src", "08_publication_assets.R"))
  source(file.path("src", "06_audit.R"))

  set.seed(20261108L)
  acquire_oulad()
  run_data_preparation()
  run_eda()
  run_model_based_clustering()
  run_outcome_description()
  run_robustness_analysis()
  run_independent_statistical_audit()
  prepare_publication_assets()
  run_final_audit()

  message("AMS pipeline completed successfully. See results/, figures/, and AMS_DEFENSE_MASTER_GUIDE.md.")
}

