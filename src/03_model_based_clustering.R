run_model_based_clustering <- function(
    processed_dir = file.path("data", "processed"),
    results_dir = "results",
    figures_dir = "figures",
    seed = 20261108L,
    g_values = 1:9,
    restart_count = 20L) {

  message("[Phase 3] Fitting Gaussian model-based clustering...")
  ensure_dirs(c(processed_dir, results_dir, figures_dir))
  analysis <- data.table::as.data.table(readRDS(file.path(processed_dir, "analysis_cohort.rds")))
  spec <- readRDS(file.path(processed_dir, "analysis_spec.rds"))
  z_features <- spec$z_features
  x <- as.matrix(analysis[, ..z_features])
  storage.mode(x) <- "double"
  assert_true(!anyNA(x) && all(is.finite(x)), "Non-finite values found in Gaussian-mixture input.")
  assert_true(nrow(x) > 20L && ncol(x) >= 2L, "Insufficient data dimensions for model-based clustering.")

  model_names <- mclust::mclust.options("emModelNames")
  robust_x <- apply(x, 2, function(v) {
    scale_value <- stats::mad(v)
    if (!is.finite(scale_value) || scale_value == 0) scale_value <- stats::sd(v)
    (v - stats::median(v)) / scale_value
  })
  storage.mode(robust_x) <- "double"
  set.seed(seed)
  initialization_specs <- list(
    full_standardized_hierarchy = list(hcPairs = mclust::hc(
      x,
      modelName = mclust::mclust.options("hcModelName"),
      use = mclust::mclust.options("hcUse")
    )),
    full_robust_affine_hierarchy = list(hcPairs = mclust::hc(
      robust_x,
      modelName = mclust::mclust.options("hcModelName"),
      use = mclust::mclust.options("hcUse")
    ))
  )
  search_subset_n <- min(nrow(x) - 1L, 1000L)
  for (s in seq_len(5L)) {
    set.seed(seed + 100L + s)
    initialization_specs[[paste0("random_subset_", s)]] <- list(
      subset = sample.int(nrow(x), search_subset_n, replace = FALSE)
    )
  }

  bic_initialization_rows <- list()
  bic_objects <- list()
  bic_warning_lines <- character()
  for (init_id in names(initialization_specs)) {
    run <- tryCatch(
      capture_warnings(mclust::mclustBIC(
        data = x,
        G = g_values,
        modelNames = model_names,
        initialization = initialization_specs[[init_id]]
      )),
      error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
    )
    bic_warning_lines <- c(bic_warning_lines, run$warnings)
    if (is.null(run$value)) next
    bic_objects[[init_id]] <- run$value
    init_long <- data.table::as.data.table(as.table(as.matrix(run$value)))
    data.table::setnames(init_long, c("G", "model", "BIC"))
    init_long[, G := as.integer(as.character(G))]
    init_long[, model := as.character(model)]
    init_long[, initialization_id := init_id]
    init_long[, initialization_type := data.table::fifelse(
      grepl("random_subset", init_id), "random subset hierarchy", "full-data hierarchy"
    )]
    init_long[, initialization_n := data.table::fifelse(
      grepl("random_subset", init_id), search_subset_n, nrow(x)
    )]
    bic_initialization_rows[[length(bic_initialization_rows) + 1L]] <- init_long
  }
  assert_true(length(bic_objects) >= 2L, "Too few successful BIC initialization searches.")
  bic_initialization_audit <- data.table::rbindlist(bic_initialization_rows, fill = TRUE)
  candidate_grid <- data.table::CJ(G = as.integer(g_values), model = as.character(model_names))
  best_cells <- bic_initialization_audit[is.finite(BIC), .SD[which.max(BIC)], by = .(G, model)]
  successful_counts <- bic_initialization_audit[is.finite(BIC), .(
    successful_initializations = .N
  ), by = .(G, model)]
  bic_long <- best_cells[candidate_grid, on = .(G, model)]
  bic_long <- successful_counts[bic_long, on = .(G, model)]
  data.table::setnames(bic_long, "initialization_id", "winning_initialization")
  bic_long[, selected_specification := FALSE]
  selected_cell <- bic_long[is.finite(BIC)][which.max(BIC)]
  selected_g <- selected_cell$G
  selected_model <- selected_cell$model
  winning_initialization <- selected_cell$winning_initialization
  bic_long[G == selected_g & model == selected_model, selected_specification := TRUE]
  bic_long <- bic_long[order(-BIC, na.last = TRUE)]
  bic_long[, bic_rank := data.table::frank(-BIC, ties.method = "min", na.last = "keep")]

  initial_run <- capture_warnings(mclust::Mclust(
    data = x,
    G = selected_g,
    modelNames = selected_model,
    initialization = initialization_specs[[winning_initialization]]
  ))
  initial_fit <- initial_run$value
  assert_true(!is.null(initial_fit), "The winning BIC specification could not be refitted.")

  restart_rows <- list()
  restart_fits <- list(initial_fit)
  restart_rows[[1]] <- data.table::data.table(
    start = 0L,
    initialization = paste("winning grid initialization:", winning_initialization),
    subset_n = selected_cell$initialization_n,
    success = TRUE,
    log_likelihood = initial_fit$loglik,
    BIC = initial_fit$bic,
    min_component_n = min(table(initial_fit$classification)),
    warnings = paste(initial_run$warnings, collapse = " | ")
  )

  subset_n <- min(nrow(x) - 1L, 1000L)
  if (subset_n < max(50L, 5L * selected_g)) subset_n <- min(nrow(x) - 1L, max(50L, 5L * selected_g))
  for (s in seq_len(restart_count)) {
    set.seed(seed + s)
    subset_ids <- sample.int(nrow(x), subset_n, replace = FALSE)
    run <- tryCatch(
      capture_warnings(mclust::Mclust(
        data = x,
        G = selected_g,
        modelNames = selected_model,
        initialization = list(subset = subset_ids)
      )),
      error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
    )
    if (is.null(run$value)) {
      failure_message <- paste(run$warnings, collapse = " | ")
      if (!nzchar(failure_message)) failure_message <- "Mclust returned NULL for this initialization."
      restart_rows[[length(restart_rows) + 1L]] <- data.table::data.table(
        start = s,
        initialization = "random clean-subset candidate",
        subset_n = subset_n,
        success = FALSE,
        log_likelihood = NA_real_,
        BIC = NA_real_,
        min_component_n = NA_integer_,
        warnings = failure_message
      )
    } else {
      restart_fits[[length(restart_fits) + 1L]] <- run$value
      restart_rows[[length(restart_rows) + 1L]] <- data.table::data.table(
        start = s,
        initialization = "random subset hierarchical initialization",
        subset_n = subset_n,
        success = TRUE,
        log_likelihood = run$value$loglik,
        BIC = run$value$bic,
        min_component_n = min(table(run$value$classification)),
        warnings = paste(run$warnings, collapse = " | ")
      )
    }
  }
  restart_table <- data.table::rbindlist(restart_rows, fill = TRUE)
  successful_rows <- restart_table[success == TRUE]
  assert_true(nrow(successful_rows) > 0L, "All fits for the selected Gaussian-mixture specification failed.")
  best_success_position <- which.max(successful_rows$log_likelihood)
  successful_fit_indices <- which(restart_table$success)
  best_restart_row <- successful_fit_indices[best_success_position]
  # restart_fits contains successful fits in exactly the same order as successful rows.
  final_fit <- restart_fits[[best_success_position]]
  restart_table[, ARI_vs_final := NA_real_]
  successful_counter <- 0L
  for (i in seq_len(nrow(restart_table))) {
    if (restart_table$success[i]) {
      successful_counter <- successful_counter + 1L
      restart_table$ARI_vs_final[i] <- mclust::adjustedRandIndex(
        restart_fits[[successful_counter]]$classification,
        final_fit$classification
      )
    }
  }

  analysis[, mclust_component := as.integer(final_fit$classification)]
  analysis[, posterior_max := apply(final_fit$z, 1, max)]
  analysis[, uncertainty := 1 - posterior_max]

  component_order <- analysis[, .(
    median_total_clicks = as.numeric(stats::median(total_clicks)),
    median_active_days = as.numeric(stats::median(active_days)),
    median_distinct_resources = as.numeric(stats::median(distinct_resources))
  ), by = mclust_component]
  data.table::setorder(component_order, median_total_clicks, median_active_days, median_distinct_resources)
  component_order[, profile_order := seq_len(.N)]
  component_order[, profile_id := paste0("P", profile_order)]
  component_order[, profile_label := paste("Profile", profile_order)]
  analysis <- component_order[
    analysis,
    on = "mclust_component"
  ]
  data.table::setorder(analysis, code_module, code_presentation, id_student)

  profile_summary <- analysis[, .(
    n = .N,
    proportion = .N / nrow(analysis),
    total_clicks_mean = mean(total_clicks),
    total_clicks_median = as.numeric(stats::median(total_clicks)),
    total_clicks_q1 = stats::quantile(total_clicks, 0.25),
    total_clicks_q3 = stats::quantile(total_clicks, 0.75),
    active_days_mean = mean(active_days),
    active_days_median = as.numeric(stats::median(active_days)),
    active_days_q1 = stats::quantile(active_days, 0.25),
    active_days_q3 = stats::quantile(active_days, 0.75),
    distinct_resources_mean = mean(distinct_resources),
    distinct_resources_median = as.numeric(stats::median(distinct_resources)),
    distinct_resources_q1 = stats::quantile(distinct_resources, 0.25),
    distinct_resources_q3 = stats::quantile(distinct_resources, 0.75),
    zero_click_n = sum(total_clicks == 0),
    uncertainty_mean = mean(uncertainty),
    uncertainty_median = stats::median(uncertainty),
    uncertainty_p90 = stats::quantile(uncertainty, 0.90),
    high_uncertainty_n = sum(uncertainty > 0.20)
  ), by = .(profile_order, profile_id, profile_label, mclust_component)]
  data.table::setorder(profile_summary, profile_order)

  get_sigma <- function(fit, k) {
    sigma <- fit$parameters$variance$sigma
    if (length(dim(sigma)) == 2L) sigma else sigma[, , k, drop = TRUE]
  }

  component_diagnostics <- data.table::rbindlist(lapply(seq_len(selected_g), function(k) {
    ids <- which(final_fit$classification == k)
    sigma_k <- get_sigma(final_fit, k)
    eigenvalues <- eigen(sigma_k, symmetric = TRUE, only.values = TRUE)$values
    mu_k <- final_fit$parameters$mean[, k]
    md2 <- stats::mahalanobis(x[ids, , drop = FALSE], center = mu_k, cov = sigma_k)
    theoretical <- stats::qchisq(stats::ppoints(length(md2)), df = ncol(x))
    data.table::data.table(
      mclust_component = k,
      n = length(ids),
      proportion = length(ids) / nrow(x),
      covariance_determinant = det(sigma_k),
      min_covariance_eigenvalue = min(eigenvalues),
      max_covariance_eigenvalue = max(eigenvalues),
      covariance_eigenvalue_ratio = max(eigenvalues) / min(eigenvalues),
      mahalanobis_qq_correlation = stats::cor(sort(md2), theoretical),
      mahalanobis_above_chisq_975_pct = mean(md2 > stats::qchisq(0.975, df = ncol(x))),
      mean_uncertainty = mean(analysis[mclust_component == k]$uncertainty),
      small_component_flag = length(ids) < max(20L, ceiling(0.02 * nrow(x))),
      near_singular_flag = min(eigenvalues) < 1e-6
    )
  }))
  component_diagnostics <- component_order[
    component_diagnostics,
    on = "mclust_component"
  ]
  data.table::setorder(component_diagnostics, profile_order)

  normality_by_feature <- data.table::rbindlist(lapply(seq_len(selected_g), function(k) {
    ids <- which(final_fit$classification == k)
    data.table::rbindlist(lapply(spec$z_features, function(v) {
      data.table::data.table(
        mclust_component = k,
        model_feature = v,
        n = length(ids),
        skewness = sample_skewness(analysis[mclust_component == k][[v]]),
        excess_kurtosis = sample_excess_kurtosis(analysis[mclust_component == k][[v]])
      )
    }))
  }))
  normality_by_feature <- component_order[
    normality_by_feature,
    on = "mclust_component"
  ]

  qq_data <- data.table::rbindlist(lapply(seq_len(selected_g), function(k) {
    ids <- which(final_fit$classification == k)
    sigma_k <- get_sigma(final_fit, k)
    mu_k <- final_fit$parameters$mean[, k]
    observed <- sort(stats::mahalanobis(x[ids, , drop = FALSE], center = mu_k, cov = sigma_k))
    data.table::data.table(
      mclust_component = k,
      theoretical = stats::qchisq(stats::ppoints(length(observed)), df = ncol(x)),
      observed = observed
    )
  }))
  qq_data <- component_order[qq_data, on = "mclust_component"]

  model_summary <- data.table::data.table(
    selected_G = selected_g,
    selected_model = selected_model,
    BIC = final_fit$bic,
    log_likelihood = final_fit$loglik,
    degrees_of_freedom = final_fit$df,
    n = final_fit$n,
    model_dimension = final_fit$d,
    bic_search_initializations = length(bic_objects),
    winning_bic_initialization = winning_initialization,
    best_initialization_row = best_restart_row,
    successful_restarts = sum(restart_table$success),
    failed_restarts = sum(!restart_table$success),
    minimum_component_n = min(table(final_fit$classification)),
    mean_uncertainty = mean(analysis$uncertainty),
    median_uncertainty = stats::median(analysis$uncertainty),
    uncertainty_above_0_20_n = sum(analysis$uncertainty > 0.20),
    any_small_component = any(component_diagnostics$small_component_flag),
    any_near_singular_component = any(component_diagnostics$near_singular_flag),
    initial_to_final_loglik_gain = final_fit$loglik - initial_fit$loglik
  )

  warning_lines <- unique(c(bic_warning_lines, initial_run$warnings, restart_table$warnings[nzchar(restart_table$warnings)]))
  if (!length(warning_lines)) warning_lines <- "No warnings captured during mclust BIC search or selected-model restarts."
  writeLines(warning_lines, file.path(results_dir, "mclust_warnings.txt"), useBytes = TRUE)

  assignment_columns <- c(
    "code_module", "code_presentation", "id_student", "final_result",
    spec$original_features, spec$log_features, spec$z_features,
    "mclust_component", "profile_order", "profile_id", "profile_label",
    "posterior_max", "uncertainty"
  )
  assignments <- analysis[, ..assignment_columns]
  write_csv(bic_long, file.path(results_dir, "mclust_bic_grid.csv"))
  write_csv(bic_initialization_audit, file.path(results_dir, "mclust_bic_initialization_audit.csv"))
  write_csv(restart_table, file.path(results_dir, "mclust_restart_diagnostics.csv"))
  write_csv(model_summary, file.path(results_dir, "mclust_selected_model.csv"))
  write_csv(component_order, file.path(results_dir, "mclust_component_profile_map.csv"))
  write_csv(profile_summary, file.path(results_dir, "mclust_profile_summary.csv"))
  write_csv(component_diagnostics, file.path(results_dir, "mclust_component_diagnostics.csv"))
  write_csv(normality_by_feature, file.path(results_dir, "mclust_component_univariate_shape.csv"))
  write_csv(assignments, file.path(results_dir, "mclust_assignments.csv"))
  saveRDS(final_fit, file.path(processed_dir, "mclust_final_fit.rds"))
  saveRDS(assignments, file.path(processed_dir, "mclust_assignments.rds"))

  bic_plot_data <- bic_long[is.finite(BIC)]
  p_bic <- ggplot2::ggplot(bic_plot_data, ggplot2::aes(G, BIC, group = model, color = model)) +
    ggplot2::geom_line(alpha = 0.7, linewidth = 0.55) +
    ggplot2::geom_point(size = 1.2) +
    ggplot2::geom_point(
      data = bic_plot_data[selected_specification == TRUE],
      color = "black",
      fill = "#FFD166",
      shape = 21,
      size = 4,
      stroke = 1
    ) +
    ggplot2::scale_x_continuous(breaks = g_values) +
    ggplot2::labs(
      title = "Gaussian-mixture model selection",
      subtitle = sprintf(
        "Selected: G = %d, covariance model %s; best BIC across %d outcome-blind initializations",
        selected_g, selected_model, length(bic_objects)
      ),
      x = "Number of mixture components (G)",
      y = "BIC",
      color = "Covariance model"
    ) +
    project_theme() +
    ggplot2::guides(color = ggplot2::guide_legend(nrow = 2, byrow = TRUE))
  save_plot(p_bic, file.path(figures_dir, "08_mclust_bic_grid.png"), width = 9, height = 6)

  p_profiles <- ggplot2::ggplot(
    analysis,
    ggplot2::aes(log_total_clicks, log_active_days, color = profile_id, alpha = 1 - uncertainty)
  ) +
    ggplot2::geom_point(size = 1.35) +
    ggplot2::scale_alpha_continuous(range = c(0.2, 0.85), guide = "none") +
    ggplot2::scale_color_brewer(palette = "Dark2") +
    ggplot2::labs(
      title = "Selected Gaussian-mixture engagement profiles",
      subtitle = "Profiles are ordered by median total clicks; transparency reflects posterior certainty",
      x = "log1p(total clicks, days 0-27)",
      y = "log1p(active days, days 0-27)",
      color = "Profile"
    ) +
    project_theme()
  save_plot(p_profiles, file.path(figures_dir, "09_mclust_profiles.png"), width = 8, height = 6)

  p_uncertainty <- ggplot2::ggplot(analysis, ggplot2::aes(uncertainty, fill = profile_id)) +
    ggplot2::geom_histogram(binwidth = 0.025, boundary = 0, color = "white", linewidth = 0.15) +
    ggplot2::facet_wrap(~profile_id, scales = "free_y", ncol = 1) +
    ggplot2::scale_fill_brewer(palette = "Dark2", guide = "none") +
    ggplot2::labs(
      title = "Posterior allocation uncertainty",
      subtitle = "Uncertainty = 1 - maximum posterior membership probability",
      x = "Allocation uncertainty",
      y = "Enrollments"
    ) +
    project_theme()
  save_plot(p_uncertainty, file.path(figures_dir, "10_mclust_uncertainty.png"), width = 8, height = 7)

  p_qq <- ggplot2::ggplot(qq_data, ggplot2::aes(theoretical, observed, color = profile_id)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, color = "grey45", linetype = 2) +
    ggplot2::geom_point(size = 0.8, alpha = 0.65) +
    ggplot2::facet_wrap(~profile_id, scales = "free", ncol = 2) +
    ggplot2::scale_color_brewer(palette = "Dark2", guide = "none") +
    ggplot2::labs(
      title = "Within-component Mahalanobis Q-Q diagnostics",
      subtitle = "Departures from the reference line indicate imperfect component Gaussian fit",
      x = "Theoretical chi-squared quantiles",
      y = "Observed squared Mahalanobis distances"
    ) +
    project_theme()
  save_plot(p_qq, file.path(figures_dir, "11_mclust_mahalanobis_qq.png"), width = 9, height = 7)

  message(sprintf(
    "[Phase 3] Selected G=%d, model=%s, BIC=%.2f; mean uncertainty=%.3f.",
    selected_g, selected_model, final_fit$bic, mean(analysis$uncertainty)
  ))
  invisible(list(
    fit = final_fit,
    assignments = assignments,
    model_summary = model_summary,
    profile_summary = profile_summary,
    diagnostics = component_diagnostics
  ))
}

