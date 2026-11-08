run_robustness_analysis <- function(
    processed_dir = file.path("data", "processed"),
    results_dir = "results",
    figures_dir = "figures",
    seed = 20261108L) {

  message("[Phase 4] Running robust clustering and sensitivity analyses...")
  analysis <- data.table::as.data.table(readRDS(file.path(processed_dir, "analysis_cohort.rds")))
  analysis_14 <- data.table::as.data.table(readRDS(file.path(processed_dir, "analysis_cohort_14day.rds")))
  opportunity <- data.table::as.data.table(readRDS(file.path(processed_dir, "opportunity_sensitivity_cohort.rds")))
  spec <- readRDS(file.path(processed_dir, "analysis_spec.rds"))
  mclust_fit <- readRDS(file.path(processed_dir, "mclust_final_fit.rds"))
  component_map <- data.table::fread(file.path(results_dir, "mclust_component_profile_map.csv"))
  z_features <- spec$z_features
  opportunity_z_features <- spec$opportunity_z_features
  x <- as.matrix(analysis[, ..z_features])
  k_selected <- mclust_fit$G

  fit_tclust_safe <- function(x, k, alpha, restriction, fit_seed, nstart = 100L) {
    set.seed(fit_seed)
    tryCatch(
      capture_warnings(tclust::tclust(
        x = x,
        k = k,
        alpha = alpha,
        restr.fact = restriction,
        nstart = nstart,
        nkeep = min(10L, nstart),
        trace = 0
      )),
      error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
    )
  }

  match_tclust_to_mclust <- function(tclust_fit, mclust_fit, component_map) {
    t_centers <- tclust_fit$centers
    m_means <- mclust_fit$parameters$mean
    cost <- matrix(NA_real_, nrow = ncol(t_centers), ncol = ncol(m_means))
    for (i in seq_len(ncol(t_centers))) {
      for (j in seq_len(ncol(m_means))) {
        cost[i, j] <- sqrt(sum((t_centers[, i] - m_means[, j])^2))
      }
    }
    assignment <- as.integer(clue::solve_LSAP(cost))
    data.table::data.table(
      tclust_cluster = seq_along(assignment),
      mclust_component = assignment,
      center_distance = cost[cbind(seq_along(assignment), assignment)]
    )[component_map, on = "mclust_component"]
  }

  fitted_eigenvalue_ratio <- function(fit) {
    covariance <- fit$cov
    if (length(dim(covariance)) == 2L) covariance <- array(covariance, dim = c(nrow(covariance), ncol(covariance), 1L))
    values <- unlist(lapply(seq_len(dim(covariance)[3]), function(j) {
      eigen(covariance[, , j, drop = TRUE], symmetric = TRUE, only.values = TRUE)$values
    }))
    max(values) / min(values)
  }

  config <- data.table::data.table(
    config_id = c("alpha0_c20", "alpha0025_c20", "primary_alpha005_c20", "alpha010_c20", "alpha005_c5", "alpha005_c50"),
    alpha = c(0, 0.025, 0.05, 0.10, 0.05, 0.05),
    restriction_factor = c(20, 20, 20, 20, 5, 50)
  )

  config_fits <- vector("list", nrow(config))
  config_rows <- vector("list", nrow(config))
  match_rows <- list()
  for (i in seq_len(nrow(config))) {
    starts_i <- if (config$config_id[i] == "primary_alpha005_c20") 500L else 100L
    run <- fit_tclust_safe(
      x, k_selected, config$alpha[i], config$restriction_factor[i], seed + 100L + i, nstart = starts_i
    )
    fit <- run$value
    config_fits[[i]] <- fit
    if (is.null(fit)) {
      config_rows[[i]] <- data.table::data.table(
        config_id = config$config_id[i], alpha = config$alpha[i],
        restriction_factor = config$restriction_factor[i], success = FALSE,
        objective = NA_real_, trimmed_n = NA_integer_, trimmed_pct = NA_real_,
        min_cluster_n = NA_integer_, max_cluster_n = NA_integer_,
        ARI_vs_mclust_retained = NA_real_, warnings = paste(run$warnings, collapse = " | ")
      )
      next
    }
    retained <- fit$cluster > 0
    positive_sizes <- as.integer(table(fit$cluster[retained]))
    nonempty_clusters <- length(positive_sizes)
    actual_ratio <- fitted_eigenvalue_ratio(fit)
    ari_retained <- if (nonempty_clusters == k_selected) {
      mclust::adjustedRandIndex(fit$cluster[retained], mclust_fit$classification[retained])
    } else {
      NA_real_
    }
    config_rows[[i]] <- data.table::data.table(
      config_id = config$config_id[i],
      alpha = config$alpha[i],
      restriction_factor = config$restriction_factor[i],
      success = TRUE,
      objective = fit$obj,
      trimmed_n = sum(!retained),
      trimmed_pct = mean(!retained),
      min_cluster_n = min(positive_sizes),
      max_cluster_n = max(positive_sizes),
      nonempty_clusters = nonempty_clusters,
      all_requested_clusters_nonempty = nonempty_clusters == k_selected,
      ARI_vs_mclust_retained = ari_retained,
      fitted_eigenvalue_ratio = actual_ratio,
      package_reported_unrestricted_ratio = fit$unrestr.fact,
      fitted_constraint_satisfied = is.finite(actual_ratio) && actual_ratio <= config$restriction_factor[i] * (1 + 1e-6),
      nstart = starts_i,
      warnings = paste(run$warnings, collapse = " | ")
    )
    mapping <- match_tclust_to_mclust(fit, mclust_fit, component_map)
    mapping[, config_id := config$config_id[i]]
    match_rows[[length(match_rows) + 1L]] <- mapping
  }
  config_summary <- data.table::rbindlist(config_rows, fill = TRUE)
  config_mapping <- data.table::rbindlist(match_rows, fill = TRUE)
  primary_index <- which(config$config_id == "primary_alpha005_c20")
  primary_fit <- config_fits[[primary_index]]
  assert_true(
    !is.null(primary_fit),
    paste("Primary TCLUST fit failed:", config_summary[config_id == "primary_alpha005_c20"]$warnings)
  )

  # Search the primary TCLUST specification in independent batches and retain
  # the maximum objective actually observed. This avoids designating a local
  # solution merely because it came from the largest single batch.
  primary_candidate_fits <- vector("list", 11L)
  primary_candidate_warnings <- vector("list", 11L)
  primary_candidate_starts <- c(500L, rep(50L, 10L))
  primary_candidate_fits[[1L]] <- primary_fit
  primary_candidate_warnings[[1L]] <- config_summary[
    config_id == "primary_alpha005_c20"
  ]$warnings
  for (r in seq_len(10L)) {
    run <- fit_tclust_safe(x, k_selected, 0.05, 20, seed + 500L + r, nstart = 50L)
    primary_candidate_fits[[r + 1L]] <- run$value
    primary_candidate_warnings[[r + 1L]] <- paste(run$warnings, collapse = " | ")
  }
  candidate_objectives <- vapply(
    primary_candidate_fits,
    function(fit) if (is.null(fit)) -Inf else fit$obj,
    numeric(1)
  )
  selected_primary_batch <- which.max(candidate_objectives) - 1L
  primary_fit <- primary_candidate_fits[[selected_primary_batch + 1L]]
  primary_retained <- primary_fit$cluster > 0L
  primary_sizes <- as.integer(table(primary_fit$cluster[primary_retained]))
  primary_nonempty <- length(primary_sizes)
  primary_ratio <- fitted_eigenvalue_ratio(primary_fit)
  primary_ari <- if (primary_nonempty == k_selected) {
    mclust::adjustedRandIndex(
      primary_fit$cluster[primary_retained],
      mclust_fit$classification[primary_retained]
    )
  } else {
    NA_real_
  }
  config_summary[config_id == "primary_alpha005_c20", `:=`(
    objective = primary_fit$obj,
    trimmed_n = sum(!primary_retained),
    trimmed_pct = mean(!primary_retained),
    min_cluster_n = min(primary_sizes),
    max_cluster_n = max(primary_sizes),
    nonempty_clusters = primary_nonempty,
    all_requested_clusters_nonempty = primary_nonempty == k_selected,
    ARI_vs_mclust_retained = primary_ari,
    fitted_eigenvalue_ratio = primary_ratio,
    package_reported_unrestricted_ratio = primary_fit$unrestr.fact,
    fitted_constraint_satisfied = is.finite(primary_ratio) && primary_ratio <= 20 * (1 + 1e-6),
    nstart = sum(primary_candidate_starts),
    selected_search_batch = selected_primary_batch,
    warnings = paste(unique(unlist(primary_candidate_warnings)), collapse = " | ")
  )]
  config_fits[[primary_index]] <- primary_fit
  config_mapping <- config_mapping[config_id != "primary_alpha005_c20"]
  primary_mapping <- match_tclust_to_mclust(primary_fit, mclust_fit, component_map)
  primary_mapping[, config_id := "primary_alpha005_c20"]
  config_mapping <- data.table::rbindlist(list(config_mapping, primary_mapping), fill = TRUE)

  repeat_rows <- vector("list", length(primary_candidate_fits))
  for (j in seq_along(primary_candidate_fits)) {
    fit <- primary_candidate_fits[[j]]
    batch_id <- j - 1L
    if (is.null(fit)) {
      repeat_rows[[j]] <- data.table::data.table(
        search_batch = batch_id,
        nstart = primary_candidate_starts[j],
        success = FALSE,
        selected_primary = FALSE,
        objective = NA_real_,
        trimmed_n = NA_integer_,
        ARI_vs_selected_common_retained = NA_real_,
        warnings = primary_candidate_warnings[[j]]
      )
    } else {
      common <- fit$cluster > 0 & primary_fit$cluster > 0
      repeat_rows[[j]] <- data.table::data.table(
        search_batch = batch_id,
        nstart = primary_candidate_starts[j],
        success = TRUE,
        selected_primary = batch_id == selected_primary_batch,
        objective = fit$obj,
        trimmed_n = sum(fit$cluster == 0),
        ARI_vs_selected_common_retained = mclust::adjustedRandIndex(
          fit$cluster[common], primary_fit$cluster[common]
        ),
        common_retained_n = sum(common),
        warnings = primary_candidate_warnings[[j]]
      )
    }
  }
  repeat_summary <- data.table::rbindlist(repeat_rows, fill = TRUE)

  primary_mapping_for_join <- data.table::copy(primary_mapping)
  data.table::setnames(
    primary_mapping_for_join,
    "mclust_component",
    "tclust_matched_mclust_component"
  )

  base <- data.table::copy(analysis)
  base[, mclust_component := as.integer(mclust_fit$classification)]
  base[, uncertainty := 1 - apply(mclust_fit$z, 1, max)]
  base <- component_map[base, on = "mclust_component"]
  data.table::setnames(base, c("profile_id", "profile_order"), c("mclust_profile_id", "mclust_profile_order"))
  base[, tclust_cluster := as.integer(primary_fit$cluster)]
  base <- primary_mapping_for_join[
    base,
    on = "tclust_cluster"
  ]
  base[, tclust_profile_id := data.table::fifelse(tclust_cluster == 0L, "Trimmed", profile_id)]
  base[, tclust_profile_order := data.table::fifelse(tclust_cluster == 0L, 0L, profile_order)]

  primary_profile_summary <- base[tclust_cluster > 0, .(
    n = .N,
    total_clicks_mean = mean(total_clicks),
    total_clicks_median = as.numeric(stats::median(total_clicks)),
    active_days_mean = mean(active_days),
    active_days_median = as.numeric(stats::median(active_days)),
    distinct_resources_mean = mean(distinct_resources),
    distinct_resources_median = as.numeric(stats::median(distinct_resources))
  ), by = .(tclust_cluster, tclust_profile_order, tclust_profile_id)]
  data.table::setorder(primary_profile_summary, tclust_profile_order)

  q99 <- vapply(spec$original_features, function(v) stats::quantile(analysis[[v]], 0.99), numeric(1))
  trimmed <- base[tclust_cluster == 0]
  trimmed[, trim_description := data.table::fcase(
    total_clicks == 0, "zero recorded activity",
    total_clicks > q99["total_clicks"] |
      active_days > q99["active_days"] |
      distinct_resources > q99["distinct_resources"], "upper-tail recorded activity",
    default = "multivariate atypical engagement pattern"
  )]
  trimmed_output <- trimmed[, c(
    "code_module", "code_presentation", "id_student", "final_result",
    spec$original_features, "mclust_component", "mclust_profile_id", "uncertainty",
    "trim_description"
  ), with = FALSE]

  k_values <- sort(unique(pmax(1L, c(k_selected - 1L, k_selected, k_selected + 1L))))
  k_rows <- list()
  for (k in k_values) {
    if (k == k_selected) {
      fit <- primary_fit
      warnings <- ""
    } else {
      run <- fit_tclust_safe(x, k, 0.05, 20, seed + 900L + k, nstart = 100L)
      fit <- run$value
      warnings <- paste(run$warnings, collapse = " | ")
    }
    if (is.null(fit)) {
      k_rows[[length(k_rows) + 1L]] <- data.table::data.table(
        k = k, success = FALSE, objective = NA_real_, trimmed_n = NA_integer_,
        min_cluster_n = NA_integer_, max_cluster_n = NA_integer_, warnings = warnings
      )
    } else {
      sizes <- as.integer(table(fit$cluster[fit$cluster > 0]))
      k_rows[[length(k_rows) + 1L]] <- data.table::data.table(
        k = k, success = TRUE, objective = fit$obj,
        trimmed_n = sum(fit$cluster == 0),
        min_cluster_n = min(sizes), max_cluster_n = max(sizes),
        warnings = warnings,
        comparison_note = "Objectives are compared only at fixed alpha=0.05 and c=20; ARI is not computed across unmatched K."
      )
    }
  }
  k_sensitivity <- data.table::rbindlist(k_rows, fill = TRUE)

  match_by_overlap <- function(alternative, reference, k) {
    tab <- table(alternative, reference)
    assert_true(all(dim(tab) == c(k, k)), "Cannot construct a complete K-by-K overlap table for label matching.")
    assignment <- as.integer(clue::solve_LSAP(max(tab) - tab))
    data.table::data.table(alternative_component = seq_len(k), reference_component = assignment)
  }

  x14 <- as.matrix(analysis_14[, ..z_features])
  set.seed(seed + 1190L)
  fit14_primary_covariance_run <- tryCatch(
    capture_warnings(mclust::Mclust(
      x14, G = k_selected, modelNames = mclust_fit$modelName
    )),
    error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
  )
  fit14_primary_covariance <- fit14_primary_covariance_run$value
  set.seed(seed + 1200L)
  fit14_run <- capture_warnings(mclust::Mclust(x14, G = k_selected))
  fit14 <- fit14_run$value
  assert_true(!is.null(fit14), "No estimable Gaussian mixture was found for the 14-day sensitivity at the fixed component count.")
  ari14 <- mclust::adjustedRandIndex(fit14$classification, mclust_fit$classification)
  map14 <- match_by_overlap(fit14$classification, mclust_fit$classification, k_selected)

  x_opportunity <- as.matrix(opportunity[, ..opportunity_z_features])
  set.seed(seed + 1290L)
  opportunity_primary_covariance_run <- tryCatch(
    capture_warnings(mclust::Mclust(
      x_opportunity, G = k_selected, modelNames = mclust_fit$modelName
    )),
    error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
  )
  opportunity_primary_covariance <- opportunity_primary_covariance_run$value
  set.seed(seed + 1300L)
  opportunity_run <- capture_warnings(mclust::Mclust(
    x_opportunity,
    G = k_selected
  ))
  opportunity_fit <- opportunity_run$value
  assert_true(!is.null(opportunity_fit), "No estimable Gaussian mixture was found for the opportunity sensitivity at the fixed component count.")
  opportunity[, alternative_component := opportunity_fit$classification]
  primary_reference <- data.table::data.table(
    code_module = analysis$code_module,
    code_presentation = analysis$code_presentation,
    id_student = analysis$id_student,
    reference_component = mclust_fit$classification
  )
  overlap <- merge(
    opportunity[, .(code_module, code_presentation, id_student, alternative_component)],
    primary_reference,
    by = c("code_module", "code_presentation", "id_student")
  )
  opportunity_ari <- mclust::adjustedRandIndex(overlap$alternative_component, overlap$reference_component)
  opportunity_map <- match_by_overlap(
    overlap$alternative_component, overlap$reference_component, k_selected
  )
  opportunity <- opportunity_map[opportunity, on = "alternative_component"]
  opportunity <- component_map[
    opportunity,
    on = c(mclust_component = "reference_component")
  ]
  opportunity_outcomes <- opportunity[, .N, by = .(profile_id, final_result)]
  opportunity_outcomes[, profile_n := sum(N), by = profile_id]
  opportunity_outcomes[, proportion := N / profile_n]

  alternative_sensitivity <- data.table::data.table(
    sensitivity = c("14-day window in primary cohort", "Opportunity-adjusted inclusion of early withdrawals"),
    n = c(nrow(analysis_14), nrow(opportunity)),
    overlap_n = c(nrow(analysis_14), nrow(overlap)),
    G_fixed = k_selected,
    reference_covariance_model = mclust_fit$modelName,
    sensitivity_covariance_model = c(fit14$modelName, opportunity_fit$modelName),
    reference_covariance_estimable = c(
      !is.null(fit14_primary_covariance), !is.null(opportunity_primary_covariance)
    ),
    reference_covariance_BIC = c(
      if (is.null(fit14_primary_covariance)) NA_real_ else fit14_primary_covariance$bic,
      if (is.null(opportunity_primary_covariance)) NA_real_ else opportunity_primary_covariance$bic
    ),
    ARI_on_common_enrollments = c(ari14, opportunity_ari),
    BIC = c(fit14$bic, opportunity_fit$bic),
    log_likelihood = c(fit14$loglik, opportunity_fit$loglik),
    warnings = c(
      paste(c(fit14_run$warnings, fit14_primary_covariance_run$warnings), collapse = " | "),
      paste(c(opportunity_run$warnings, opportunity_primary_covariance_run$warnings), collapse = " | ")
    ),
    comparison_scope = c(
      "Same enrollments; activity measured on days 0-13 instead of 0-27.",
      "Adds early withdrawals and replaces counts with opportunity-adjusted rate/share features."
    ),
    model_selection_note = paste0(
      "Component count is fixed at the primary value. The primary covariance family is tested explicitly, ",
      "while the reported sensitivity partition reselects covariance by BIC within each alternative feature set."
    )
  )

  tclust_assignment_output <- base[, c(
    "code_module", "code_presentation", "id_student", "final_result",
    spec$original_features, "mclust_component", "mclust_profile_id", "uncertainty",
    "tclust_cluster", "tclust_matched_mclust_component",
    "tclust_profile_id", "tclust_profile_order"
  ), with = FALSE]

  write_csv(config_summary, file.path(results_dir, "tclust_configuration_sensitivity.csv"))
  write_csv(config_mapping, file.path(results_dir, "tclust_profile_matching.csv"))
  write_csv(primary_profile_summary, file.path(results_dir, "tclust_primary_profile_summary.csv"))
  write_csv(tclust_assignment_output, file.path(results_dir, "tclust_primary_assignments.csv"))
  write_csv(trimmed_output, file.path(results_dir, "tclust_trimmed_observations.csv"))
  write_csv(repeat_summary, file.path(results_dir, "tclust_initialization_stability.csv"))
  write_csv(k_sensitivity, file.path(results_dir, "tclust_k_sensitivity.csv"))
  write_csv(alternative_sensitivity, file.path(results_dir, "alternative_specification_sensitivity.csv"))
  write_csv(opportunity_outcomes, file.path(results_dir, "opportunity_sensitivity_outcomes.csv"))
  saveRDS(primary_fit, file.path(processed_dir, "tclust_primary_fit.rds"))
  saveRDS(tclust_assignment_output, file.path(processed_dir, "tclust_primary_assignments.rds"))
  saveRDS(fit14, file.path(processed_dir, "mclust_14day_fit.rds"))
  saveRDS(opportunity_fit, file.path(processed_dir, "mclust_opportunity_fit.rds"))

  plot_config <- config_summary[success == TRUE & is.finite(ARI_vs_mclust_retained)]
  plot_config[, label := sprintf("alpha=%.3f, c=%g", alpha, restriction_factor)]
  p_config <- ggplot2::ggplot(plot_config, ggplot2::aes(reorder(label, ARI_vs_mclust_retained), ARI_vs_mclust_retained)) +
    ggplot2::geom_col(ggplot2::aes(fill = config_id == "primary_alpha005_c20"), width = 0.72) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("ARI %.2f\ntrim %.1f%%", ARI_vs_mclust_retained, 100 * trimmed_pct)),
      hjust = -0.05,
      size = 3.2
    ) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c(`FALSE` = "#A7B6C2", `TRUE` = "#D55E00"), guide = "none") +
    ggplot2::scale_y_continuous(limits = c(0, 1.08), expand = ggplot2::expansion(mult = c(0, 0))) +
    ggplot2::labs(
      title = "TCLUST sensitivity relative to the Gaussian-mixture partition",
      subtitle = "ARI uses only observations retained by TCLUST; objectives are not compared across alpha",
      x = NULL,
      y = "Adjusted Rand index on retained observations"
    ) +
    project_theme()
  save_plot(p_config, file.path(figures_dir, "14_tclust_configuration_sensitivity.png"), width = 9, height = 5.5)

  plot_base <- data.table::copy(base)
  plot_base[, display_group := data.table::fifelse(tclust_cluster == 0L, "Trimmed", tclust_profile_id)]
  profile_colors <- stats::setNames(
    grDevices::hcl.colors(k_selected, palette = "Dark 3"),
    paste0("P", seq_len(k_selected))
  )
  display_colors <- c(profile_colors, Trimmed = "black")
  p_tclust <- ggplot2::ggplot(
    plot_base,
    ggplot2::aes(log_total_clicks, log_active_days, color = display_group, shape = tclust_cluster == 0L)
  ) +
    ggplot2::geom_point(alpha = 0.65, size = 1.45) +
    ggplot2::scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 4), labels = c("Retained", "Trimmed")) +
    ggplot2::scale_color_manual(values = display_colors) +
    ggplot2::labs(
      title = "Primary robust clustering solution",
      subtitle = "TCLUST: alpha = 0.05, eigenvalue restriction c = 20; labels matched by center distance",
      x = "log1p(total clicks)",
      y = "log1p(active days)",
      color = "Matched profile",
      shape = "TCLUST status"
    ) +
    project_theme()
  save_plot(p_tclust, file.path(figures_dir, "15_tclust_primary_solution.png"), width = 8.5, height = 6)

  p_alternative <- ggplot2::ggplot(
    alternative_sensitivity,
    ggplot2::aes(reorder(sensitivity, ARI_on_common_enrollments), ARI_on_common_enrollments)
  ) +
    ggplot2::geom_col(fill = "#176B87", width = 0.65) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("ARI %.2f", ARI_on_common_enrollments)),
      hjust = -0.08,
      size = 3.5
    ) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(limits = c(0, 1.05), expand = ggplot2::expansion(mult = c(0, 0))) +
    ggplot2::labs(
      title = "Sensitivity to window and observation opportunity",
      subtitle = "Same component count; covariance family is reselected and ARI uses only common enrollments",
      x = NULL,
      y = "Adjusted Rand index"
    ) +
    project_theme()
  save_plot(p_alternative, file.path(figures_dir, "16_alternative_specification_sensitivity.png"), width = 9, height = 4.5)

  primary_config <- config_summary[config_id == "primary_alpha005_c20"]
  message(sprintf(
    "[Phase 4] Primary TCLUST retained %d/%d; ARI vs mclust=%.3f. 14-day ARI=%.3f; opportunity ARI=%.3f.",
    nrow(x) - primary_config$trimmed_n, nrow(x), primary_config$ARI_vs_mclust_retained,
    ari14, opportunity_ari
  ))

  invisible(list(
    primary_fit = primary_fit,
    config_summary = config_summary,
    initialization_stability = repeat_summary,
    alternative_sensitivity = alternative_sensitivity
  ))
}

