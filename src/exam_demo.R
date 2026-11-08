run_exam_demo <- function(results_dir = "results", processed_dir = file.path("data", "processed")) {
  required <- c(
    file.path(results_dir, "selected_cohort.csv"),
    file.path(results_dir, "mclust_selected_model.csv"),
    file.path(results_dir, "mclust_profile_summary.csv"),
    file.path(results_dir, "outcome_by_profile_proportions_wide.csv"),
    file.path(results_dir, "tclust_configuration_sensitivity.csv"),
    file.path(results_dir, "alternative_specification_sensitivity.csv"),
    file.path(results_dir, "independent_statistical_audit_summary.csv")
  )
  if (!all(file.exists(required))) {
    stop("Cached verified outputs are missing. Run source('main.R') first.", call. = FALSE)
  }

  selected_cohort <- data.table::fread(required[1])
  selected_model <- data.table::fread(required[2])
  profile_summary <- data.table::fread(required[3])
  outcome_by_profile <- data.table::fread(required[4])
  tclust_sensitivity <- data.table::fread(required[5])
  alternative_sensitivity <- data.table::fread(required[6])
  independent_audit <- data.table::fread(required[7])

  cat("\nAMS exam demo - cached verified outputs\n")
  cat("========================================\n")
  print(selected_cohort[, .(
    code_module, code_presentation, enrollment_n,
    early_unregistered_days_0_27, eligible_full_window, eligible_zero_click_n
  )])
  cat("\nSelected Gaussian mixture:\n")
  print(selected_model[, .(
    selected_G, selected_model, BIC, minimum_component_n,
    mean_uncertainty, uncertainty_above_0_20_n
  )])
  cat("\nProfiles on original scales:\n")
  print(profile_summary[, .(
    profile_id, n, total_clicks_median, active_days_median,
    distinct_resources_median, uncertainty_mean
  )])
  cat("\nRecorded outcome proportions by profile:\n")
  print(outcome_by_profile)
  cat("\nPrimary TCLUST comparison:\n")
  print(tclust_sensitivity[config_id == "primary_alpha005_c20", .(
    alpha, restriction_factor, nstart, trimmed_n,
    min_cluster_n, max_cluster_n, ARI_vs_mclust_retained,
    fitted_eigenvalue_ratio, fitted_constraint_satisfied
  )])
  cat("\nAlternative specifications:\n")
  print(alternative_sensitivity[, .(
    sensitivity, n, sensitivity_covariance_model, ARI_on_common_enrollments
  )])
  cat("\nIndependent statistical audit highlights:\n")
  print(independent_audit)
  cat("\nKey figures:\n")
  cat("  figures/08_mclust_bic_grid.png\n")
  cat("  figures/09_mclust_profiles.png\n")
  cat("  figures/12_outcomes_by_profile.png\n")
  cat("  figures/14_tclust_configuration_sensitivity.png\n")
  cat("  figures/16_alternative_specification_sensitivity.png\n")
  cat("  figures/17_method_disagreement_crosstab.png\n")
  cat("  figures/19_mclust_subsample_stability.png\n")
  cat("  figures/20_mclust_specification_sensitivity.png\n")

  if (interactive()) {
    assign("ams_selected_model", readRDS(file.path(processed_dir, "mclust_final_fit.rds")), envir = .GlobalEnv)
    assign("ams_assignments", readRDS(file.path(processed_dir, "mclust_assignments.rds")), envir = .GlobalEnv)
    assign("ams_tclust_fit", readRDS(file.path(processed_dir, "tclust_primary_fit.rds")), envir = .GlobalEnv)
    message("Loaded ams_selected_model, ams_assignments, and ams_tclust_fit into the Global Environment.")
  }
  invisible(list(
    selected_cohort = selected_cohort,
    selected_model = selected_model,
    profile_summary = profile_summary,
    outcomes = outcome_by_profile,
    tclust = tclust_sensitivity,
    alternatives = alternative_sensitivity,
    independent_audit = independent_audit
  ))
}

