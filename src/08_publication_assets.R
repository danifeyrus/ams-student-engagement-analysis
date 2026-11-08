prepare_publication_assets <- function(
    results_dir = "results",
    figures_dir = "figures",
    publication_dir = "publication") {

  message("[Team handoff] Preparing report-ready figures and tables...")
  figure_output <- file.path(publication_dir, "figures")
  table_output <- file.path(publication_dir, "tables")
  ensure_dirs(c(figure_output, table_output))

  selected_figures <- c(
    "02_cohort_inclusion_flow.png",
    "04_feature_distributions_original.png",
    "06_feature_correlation.png",
    "08_mclust_bic_grid.png",
    "09_mclust_profiles.png",
    "10_mclust_uncertainty.png",
    "12_outcomes_by_profile.png",
    "14_tclust_configuration_sensitivity.png",
    "17_method_disagreement_crosstab.png",
    "19_mclust_subsample_stability.png"
  )
  source_figures <- file.path(figures_dir, selected_figures)
  assert_true(all(file.exists(source_figures)), "One or more selected publication figures are missing.")
  copied <- file.copy(source_figures, figure_output, overwrite = TRUE)
  assert_true(all(copied), "One or more publication figures could not be copied.")

  selected <- data.table::fread(file.path(results_dir, "selected_cohort.csv"))
  cohort <- selected[, .(
    module = code_module,
    presentation = code_presentation,
    recorded_enrollments = enrollment_n,
    registered_by_day_0 = registered_by_day0,
    active_at_day_0 = active_at_day0,
    early_unregistrations_days_0_27 = early_unregistered_days_0_27,
    analytical_sample = eligible_full_window,
    zero_click_enrollments = eligible_zero_click_n
  )]

  variables <- data.table::data.table(
    variable = c("total_clicks", "active_days", "distinct_resources"),
    source = c("studentVle.sum_click", "studentVle.date", "studentVle.id_site"),
    definition = c(
      "Sum of recorded VLE clicks on course days 0-27",
      "Number of distinct course days with at least one VLE interaction on days 0-27",
      "Number of distinct VLE resources accessed on course days 0-27"
    ),
    model_transformation = "log1p followed by z-standardization",
    interpretation_scale = "Original count scale"
  )

  descriptives <- data.table::fread(file.path(results_dir, "eda_feature_summary.csv"))[
    scale == "original",
    .(variable, n, missing_n, zero_n, zero_pct, mean, sd, minimum, q1, median, q3, p95, maximum)
  ]
  numeric_columns <- setdiff(names(descriptives), c("variable", "n", "missing_n", "zero_n"))
  descriptives[, (numeric_columns) := lapply(.SD, round, 3), .SDcols = numeric_columns]

  model <- data.table::fread(file.path(results_dir, "mclust_selected_model.csv"))[, .(
    components = selected_G,
    covariance_model = selected_model,
    BIC = round(BIC, 3),
    log_likelihood = round(log_likelihood, 3),
    degrees_of_freedom,
    n,
    bic_search_initializations,
    successful_restarts,
    failed_restarts,
    minimum_component_n,
    mean_uncertainty = round(mean_uncertainty, 3),
    assignments_uncertainty_above_0_20 = uncertainty_above_0_20_n
  )]

  bic <- data.table::fread(file.path(results_dir, "mclust_bic_grid.csv"))[
    is.finite(BIC) & bic_rank <= 10,
    .(bic_rank, components = G, covariance_model = model,
      BIC = round(BIC, 3), successful_initializations,
      selected = selected_specification)
  ][order(bic_rank)]

  profiles <- data.table::fread(file.path(results_dir, "mclust_profile_summary.csv"))[, .(
    profile = profile_id,
    n,
    proportion = round(proportion, 3),
    median_total_clicks = total_clicks_median,
    median_active_days = active_days_median,
    median_distinct_resources = distinct_resources_median,
    mean_uncertainty = round(uncertainty_mean, 3),
    assignments_uncertainty_above_0_20 = high_uncertainty_n
  )]

  outcomes <- data.table::fread(file.path(results_dir, "outcome_by_profile_proportions_wide.csv"))
  outcome_numeric <- setdiff(names(outcomes), c("profile_id"))
  outcomes[, (outcome_numeric) := lapply(.SD, function(x) round(x, 3)), .SDcols = outcome_numeric]

  association <- data.table::fread(file.path(results_dir, "outcome_profile_association.csv"))
  association[, c("statistic", "p_value", "cramers_v", "minimum_expected_count") := .(
    round(statistic, 3), signif(p_value, 4), round(cramers_v, 3), round(minimum_expected_count, 2)
  )]

  robustness <- data.table::fread(file.path(results_dir, "tclust_configuration_sensitivity.csv"))[, .(
    configuration = config_id,
    alpha,
    restriction_factor,
    retained_n = 2011L - trimmed_n,
    trimmed_n,
    minimum_cluster_n = min_cluster_n,
    maximum_cluster_n = max_cluster_n,
    ARI_vs_mclust_retained = round(ARI_vs_mclust_retained, 3),
    fitted_eigenvalue_ratio = round(fitted_eigenvalue_ratio, 3),
    starts = nstart
  )]

  diagnostics <- data.table::fread(file.path(results_dir, "independent_statistical_audit_summary.csv"))
  sensitivity <- data.table::fread(file.path(results_dir, "alternative_specification_sensitivity.csv"))[, .(
    specification = sensitivity,
    n,
    overlap_n,
    fixed_components = G_fixed,
    covariance_model = sensitivity_covariance_model,
    primary_covariance_estimable = reference_covariance_estimable,
    ARI_on_common_enrollments = round(ARI_on_common_enrollments, 3),
    comparison_scope
  )]

  tables <- list(
    "01_cohort_summary.csv" = cohort,
    "02_cohort_inclusion_flow.csv" = data.table::fread(file.path(results_dir, "cohort_inclusion_flow.csv")),
    "03_variable_dictionary.csv" = variables,
    "04_descriptive_statistics.csv" = descriptives,
    "05_selected_model.csv" = model,
    "06_bic_top_models.csv" = bic,
    "07_profile_summary.csv" = profiles,
    "08_outcomes_by_profile.csv" = outcomes,
    "09_outcome_association.csv" = association,
    "10_tclust_robustness.csv" = robustness,
    "11_key_diagnostics.csv" = diagnostics,
    "12_specification_sensitivity.csv" = sensitivity,
    "13_method_disagreement_crosstab.csv" = data.table::fread(file.path(results_dir, "method_disagreement_crosstab.csv"))
  )
  for (name in names(tables)) write_csv(tables[[name]], file.path(table_output, name))

  message(sprintf(
    "[Team handoff] Prepared %d figures and %d tables.",
    length(selected_figures), length(tables)
  ))
  invisible(list(figures = selected_figures, tables = names(tables)))
}
