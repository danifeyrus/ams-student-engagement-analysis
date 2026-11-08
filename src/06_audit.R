run_final_audit <- function(
    processed_dir = file.path("data", "processed"),
    results_dir = "results",
    figures_dir = "figures") {

  message("[Phase 5] Auditing generated outputs and numerical invariants...")
  checks <- list()
  add_check <- function(name, condition, detail, level = "required") {
    checks[[length(checks) + 1L]] <<- data.table::data.table(
      check = name,
      level = level,
      status = if (isTRUE(condition)) "PASS" else if (level == "required") "FAIL" else "REVIEW",
      detail = as.character(detail)
    )
  }

  raw_validation <- data.table::fread(file.path(results_dir, "raw_table_validation.csv"))
  expected_rows <- c(
    courses = 22L, assessments = 206L, vle = 6364L,
    student_info = 32593L, registration = 32593L,
    student_assessment = 173912L, student_vle = 10655280L
  )
  actual_rows <- stats::setNames(raw_validation$rows, raw_validation$table)
  add_check(
    "Official raw-table row counts",
    identical(as.integer(actual_rows[names(expected_rows)]), as.integer(expected_rows)),
    paste(sprintf("%s=%s", names(expected_rows), actual_rows[names(expected_rows)]), collapse = "; ")
  )

  join_validation <- data.table::fread(file.path(results_dir, "join_validation.csv"))
  add_check(
    "All documented join keys matched",
    all(join_validation$unmatched_rows == 0),
    paste("Total unmatched rows:", sum(join_validation$unmatched_rows))
  )

  raw_manifest <- data.table::fread(file.path(results_dir, "raw_file_manifest.csv"))
  raw_paths <- file.path("data", "raw", "oulad", raw_manifest$file)
  current_md5 <- unname(tools::md5sum(raw_paths))
  add_check(
    "Extracted raw files unchanged since preparation",
    identical(current_md5, raw_manifest$md5),
    paste("Files checked:", length(raw_paths))
  )

  analysis <- data.table::as.data.table(readRDS(file.path(processed_dir, "analysis_cohort.rds")))
  selected <- data.table::fread(file.path(results_dir, "selected_cohort.csv"))
  add_check(
    "Selected cohort cardinality",
    nrow(analysis) == selected$eligible_full_window,
    sprintf("analysis rows=%d; selected eligible=%d", nrow(analysis), selected$eligible_full_window)
  )
  add_check(
    "Zero-click enrollments retained",
    sum(analysis$total_clicks == 0) == selected$eligible_zero_click_n,
    paste("Zero-click enrollments:", sum(analysis$total_clicks == 0))
  )

  spec <- readRDS(file.path(processed_dir, "analysis_spec.rds"))
  z_features <- spec$z_features
  add_check(
    "Finite Gaussian-mixture input",
    all(vapply(analysis[, ..z_features], function(x) all(is.finite(x)), logical(1))),
    paste("Model features:", paste(spec$z_features, collapse = ", "))
  )
  add_check(
    "Outcome excluded from model inputs",
    !"final_result" %in% c(spec$original_features, spec$log_features, spec$z_features),
    paste("Outcome-blind features:", paste(spec$z_features, collapse = ", "))
  )

  mclust_fit <- readRDS(file.path(processed_dir, "mclust_final_fit.rds"))
  mclust_summary <- data.table::fread(file.path(results_dir, "mclust_selected_model.csv"))
  profile_summary <- data.table::fread(file.path(results_dir, "mclust_profile_summary.csv"))
  component_diagnostics <- data.table::fread(file.path(results_dir, "mclust_component_diagnostics.csv"))
  restart_diagnostics <- data.table::fread(file.path(results_dir, "mclust_restart_diagnostics.csv"))
  bic_grid <- data.table::fread(file.path(results_dir, "mclust_bic_grid.csv"))
  selected_grid <- bic_grid[selected_specification == TRUE]
  add_check(
    "Mclust BIC search uses multiple outcome-blind initializations",
    mclust_summary$bic_search_initializations >= 2L &&
      nrow(selected_grid) == 1L && selected_grid$BIC == max(bic_grid$BIC, na.rm = TRUE),
    sprintf(
      "initializations=%d; selected G=%d %s; grid BIC=%.3f",
      mclust_summary$bic_search_initializations, mclust_summary$selected_G,
      mclust_summary$selected_model, selected_grid$BIC
    )
  )
  add_check(
    "Mclust assignment cardinality",
    length(mclust_fit$classification) == nrow(analysis) && sum(profile_summary$n) == nrow(analysis),
    sprintf("assignments=%d; profile total=%d", length(mclust_fit$classification), sum(profile_summary$n))
  )
  add_check(
    "Selected Mclust restart has maximum recorded log-likelihood",
    abs(mclust_fit$loglik - max(restart_diagnostics$log_likelihood, na.rm = TRUE)) < 1e-7,
    sprintf("final=%.8f; recorded max=%.8f", mclust_fit$loglik, max(restart_diagnostics$log_likelihood, na.rm = TRUE))
  )
  add_check(
    "No tiny or near-singular Gaussian components",
    !any(component_diagnostics$small_component_flag) && !any(component_diagnostics$near_singular_flag),
    sprintf(
      "minimum component n=%d; minimum covariance eigenvalue=%.6g",
      min(component_diagnostics$n), min(component_diagnostics$min_covariance_eigenvalue)
    )
  )
  add_check(
    "Posterior uncertainty requires substantive caution",
    mclust_summary$mean_uncertainty < 0.10,
    sprintf("mean uncertainty=%.3f; n above 0.20=%d", mclust_summary$mean_uncertainty, mclust_summary$uncertainty_above_0_20_n),
    level = "diagnostic"
  )

  outcome_long <- data.table::fread(file.path(results_dir, "outcome_by_profile_long.csv"))
  association <- data.table::fread(file.path(results_dir, "outcome_profile_association.csv"))
  add_check(
    "Outcome table denominators",
    sum(outcome_long$N) == nrow(analysis) && all(outcome_long[, sum(N) == unique(profile_n), by = profile_id]$V1),
    sprintf("Outcome total=%d; cohort n=%d", sum(outcome_long$N), nrow(analysis))
  )
  add_check(
    "Chi-squared expected-count condition",
    association$expected_cells_below_5 == 0,
    sprintf("minimum expected count=%.2f", association$minimum_expected_count)
  )

  tclust_summary <- data.table::fread(file.path(results_dir, "tclust_configuration_sensitivity.csv"))
  primary_tclust <- tclust_summary[config_id == "primary_alpha005_c20"]
  tclust_assignments <- data.table::as.data.table(readRDS(file.path(processed_dir, "tclust_primary_assignments.rds")))
  add_check(
    "TCLUST trimming count",
    sum(tclust_assignments$tclust_cluster == 0) == primary_tclust$trimmed_n,
    sprintf("trimmed=%d of %d", sum(tclust_assignments$tclust_cluster == 0), nrow(tclust_assignments))
  )
  add_check(
    "TCLUST fitted eigenvalue constraint",
    isTRUE(primary_tclust$fitted_constraint_satisfied),
    sprintf("fitted ratio=%.6f; c=%g", primary_tclust$fitted_eigenvalue_ratio, primary_tclust$restriction_factor)
  )
  add_check(
    "TCLUST requested components nonempty",
    isTRUE(primary_tclust$all_requested_clusters_nonempty),
    paste("Nonempty clusters:", primary_tclust$nonempty_clusters)
  )
  add_check(
    "Robust agreement requires substantive caution",
    primary_tclust$ARI_vs_mclust_retained >= 0.80,
    sprintf("ARI on retained observations=%.3f", primary_tclust$ARI_vs_mclust_retained),
    level = "diagnostic"
  )

  independent_ari <- data.table::fread(file.path(results_dir, "independent_ari_verification.csv"))
  manual_ari <- independent_ari[grepl("manual", comparison, ignore.case = TRUE)]
  package_ari <- independent_ari[grepl("Package ARI", comparison)]
  add_check(
    "Independent ARI verification and key alignment",
    nrow(manual_ari) == 1L && nrow(package_ari) == 1L &&
      abs(manual_ari$ari - package_ari$ari) < 1e-12 &&
      abs(manual_ari$ari - primary_tclust$ARI_vs_mclust_retained) < 1e-12 &&
      isTRUE(manual_ari$unique_enrollment_keys) &&
      isTRUE(manual_ari$recorded_assignment_alignment_exact) &&
      manual_ari$n_compared == nrow(analysis) - primary_tclust$trimmed_n,
    sprintf("manual/package ARI=%.9f; compared n=%d", manual_ari$ari, manual_ari$n_compared)
  )

  separation <- data.table::fread(file.path(results_dir, "cluster_separation_diagnostics.csv"))
  gaussian_separation <- separation[grepl("Mclust", method)]
  add_check(
    "Hard Gaussian partition separation requires caution",
    gaussian_separation$mean_silhouette >= 0.50 && gaussian_separation$negative_silhouette_proportion <= 0.05,
    sprintf(
      "mean silhouette=%.3f; negative silhouette proportion=%.3f",
      gaussian_separation$mean_silhouette, gaussian_separation$negative_silhouette_proportion
    ),
    level = "diagnostic"
  )

  icl_grid <- data.table::fread(file.path(results_dir, "mclust_icl_grid.csv"))
  top_icl <- icl_grid[which.max(ICL)]
  add_check(
    "BIC and classification-focused ICL agree",
    top_icl$G == mclust_summary$selected_G && top_icl$model == mclust_summary$selected_model,
    sprintf(
      "BIC selects G=%d %s; ICL selects G=%d %s",
      mclust_summary$selected_G, mclust_summary$selected_model, top_icl$G, top_icl$model
    ),
    level = "diagnostic"
  )

  subsample <- data.table::fread(file.path(results_dir, "mclust_subsample_stability.csv"))
  reselection_rate <- mean(
    subsample$selected_G == mclust_summary$selected_G &
      subsample$selected_model == mclust_summary$selected_model,
    na.rm = TRUE
  )
  add_check(
    "Gaussian model selection stable under 80 percent case subsampling",
    reselection_rate >= 0.80,
    sprintf(
      "primary G/model reselection rate=%.1f%%; median selected-partition ARI=%.3f",
      100 * reselection_rate, stats::median(subsample$selected_ARI_vs_primary, na.rm = TRUE)
    ),
    level = "diagnostic"
  )

  required_figures <- sprintf("%02d_", 1:20)
  figure_files <- list.files(figures_dir, pattern = "\\.png$", full.names = TRUE)
  figure_names <- basename(figure_files)
  figures_present <- vapply(required_figures, function(prefix) any(startsWith(figure_names, prefix)), logical(1))
  add_check(
    "Required figure set exists and is nonempty",
    all(figures_present) && all(file.info(figure_files)$size > 1000),
    sprintf("PNG figures found=%d; expected prefixes present=%d/20", length(figure_files), sum(figures_present))
  )

  required_results <- c(
    "cohort_comparison.csv", "eda_feature_summary.csv", "mclust_bic_grid.csv",
    "mclust_profile_summary.csv", "outcome_by_profile_long.csv",
    "tclust_configuration_sensitivity.csv", "alternative_specification_sensitivity.csv",
    "independent_ari_verification.csv", "independent_statistical_audit_summary.csv",
    "mclust_subsample_stability.csv", "mclust_specification_sensitivity.csv"
  )
  result_paths <- file.path(results_dir, required_results)
  add_check(
    "Core machine-readable result files exist",
    all(file.exists(result_paths)) && all(file.info(result_paths)$size > 0),
    paste(required_results, collapse = ", ")
  )

  warnings_and_limitations <- data.table::data.table(
    item = c(
      "mclust fit diagnostics",
      "mclust BIC initialization dependence",
      "mclust restart sensitivity",
      "posterior allocation uncertainty",
      "component Gaussian adequacy",
      "hard-partition separation",
      "BIC versus ICL",
      "case-subsample model-selection stability",
      "TCLUST agreement",
      "TCLUST initialization sensitivity",
      "TCLUST tuning sensitivity",
      "alternative covariance estimability",
      "early-withdrawal selection"
    ),
    status = c(
      "Investigated",
      "Material finding",
      "Investigated",
      "Material limitation",
      "Approximate, not exact",
      "Material limitation",
      "Material limitation",
      "Sensitivity limitation",
      "Material limitation",
      "Material limitation",
      "Sensitivity limitation",
      "Sensitivity limitation",
      "Primary-cohort limitation"
    ),
    evidence = c(
      sprintf(
        "%d of %d selected-specification restarts failed or returned NULL; failures and emitted messages are recorded.",
        sum(!restart_diagnostics$success), nrow(restart_diagnostics)
      ),
      sprintf(
        "A %d-initialization outcome-blind BIC search selected G=%d %s; the earlier single-initialization result was not retained.",
        mclust_summary$bic_search_initializations, mclust_summary$selected_G, mclust_summary$selected_model
      ),
      sprintf("ARI across successful restarts ranges %.3f to %.3f; best recorded log-likelihood retained.", min(restart_diagnostics$ARI_vs_final, na.rm = TRUE), max(restart_diagnostics$ARI_vs_final, na.rm = TRUE)),
      sprintf("Mean uncertainty %.3f; %d assignments above 0.20.", mclust_summary$mean_uncertainty, mclust_summary$uncertainty_above_0_20_n),
      sprintf("Mahalanobis Q-Q correlations range %.3f to %.3f; log1p does not ensure normality.", min(component_diagnostics$mahalanobis_qq_correlation), max(component_diagnostics$mahalanobis_qq_correlation)),
      sprintf(
        "Mean silhouette %.3f; %.1f%% of Gaussian assignments have negative silhouette.",
        gaussian_separation$mean_silhouette, 100 * gaussian_separation$negative_silhouette_proportion
      ),
      sprintf(
        "BIC selects G=%d %s, whereas entropy-penalized ICL selects G=%d %s.",
        mclust_summary$selected_G, mclust_summary$selected_model, top_icl$G, top_icl$model
      ),
      sprintf(
        "The primary G/model is reselected in %.1f%% of 80%% subsamples; median selected-partition ARI is %.3f.",
        100 * reselection_rate, stats::median(subsample$selected_ARI_vs_primary, na.rm = TRUE)
      ),
      sprintf("Primary TCLUST ARI %.3f on retained observations.", primary_tclust$ARI_vs_mclust_retained),
      "Recorded in results/tclust_initialization_stability.csv; repeated-start agreement is variable.",
      sprintf(
        "Across like-for-like configurations, retained-case ARI ranges %.3f to %.3f; component sizes can be highly unbalanced.",
        min(tclust_summary$ARI_vs_mclust_retained, na.rm = TRUE),
        max(tclust_summary$ARI_vs_mclust_retained, na.rm = TRUE)
      ),
      paste(
        "The primary covariance family is explicitly tested in both alternative feature sets;",
        "covariance is reselected by BIC for the reported alternative partitions."
      ),
      sprintf("%d enrollments unregistering on days 0-27 were excluded from the %d-enrollment primary cohort.", selected$early_unregistered_days_0_27, nrow(analysis))
    )
  )
  write_csv(warnings_and_limitations, file.path(results_dir, "warnings_and_limitations.csv"))

  package_names <- c("data.table", "ggplot2", "mclust", "tclust", "clue", "scales", "cluster", "renv")
  package_versions <- data.table::data.table(
    package = package_names,
    version = vapply(package_names, function(pkg) as.character(utils::packageVersion(pkg)), character(1))
  )
  write_csv(package_versions, file.path(results_dir, "package_versions.csv"))
  session_lines <- trimws(capture.output(sessionInfo()), which = "right")
  writeLines(session_lines, file.path(results_dir, "session-info.txt"), useBytes = TRUE)

  verification <- data.table::rbindlist(checks, fill = TRUE)
  write_csv(verification, file.path(results_dir, "verification_summary.csv"))

  manifest_files <- sort(unique(c(
    list.files(results_dir, full.names = TRUE),
    list.files(figures_dir, full.names = TRUE),
    list.files("src", pattern = "\\.R$", full.names = TRUE),
    list.files("publication", recursive = TRUE, full.names = TRUE),
    list.files("docs", recursive = TRUE, full.names = TRUE),
    "main.R", "EXAM_DEMO.R", ".Rprofile",
    file.path(".vscode", c("settings.example.json", "tasks.json", "extensions.json")),
    ".gitattributes", ".gitignore", ".renvignore", "renv/activate.R", "README.md", "renv.lock",
    file.path("scripts", "run-r.ps1")
  )))
  manifest_files <- setdiff(manifest_files, file.path(results_dir, "output_manifest.csv"))
  manifest_files <- setdiff(manifest_files, c(
    file.path(results_dir, "vscode_full_execution.log"),
    file.path(results_dir, "vscode_environment_verification.csv")
  ))
  manifest_files <- manifest_files[file.exists(manifest_files)]
  output_manifest <- data.table::data.table(
    file = manifest_files,
    bytes = file.info(manifest_files)$size,
    md5 = unname(tools::md5sum(manifest_files))
  )
  write_csv(output_manifest, file.path(results_dir, "output_manifest.csv"))

  failed <- verification[level == "required" & status == "FAIL"]
  if (nrow(failed)) {
    stop(
      paste("Final audit failed:", paste(failed$check, collapse = "; ")),
      call. = FALSE
    )
  }
  message(sprintf(
    "[Phase 5] Audit passed %d required checks; %d diagnostics require interpretation.",
    sum(verification$level == "required" & verification$status == "PASS"),
    sum(verification$level == "diagnostic" & verification$status == "REVIEW")
  ))
  invisible(verification)
}

