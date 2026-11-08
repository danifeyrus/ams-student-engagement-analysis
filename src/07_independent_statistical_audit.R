manual_adjusted_rand_index <- function(labels_a, labels_b) {
  assert_true(length(labels_a) == length(labels_b), "ARI label vectors must have equal length.")
  tab <- table(labels_a, labels_b)
  choose2 <- function(v) v * (v - 1) / 2
  n_pairs <- choose2(sum(tab))
  sum_cells <- sum(choose2(tab))
  sum_rows <- sum(choose2(rowSums(tab)))
  sum_cols <- sum(choose2(colSums(tab)))
  expected <- sum_rows * sum_cols / n_pairs
  maximum <- (sum_rows + sum_cols) / 2
  if (maximum == expected) return(1)
  (sum_cells - expected) / (maximum - expected)
}

between_total_ratio <- function(x, labels) {
  labels <- as.factor(labels)
  center <- colMeans(x)
  total <- sum(rowSums((x - matrix(center, nrow(x), ncol(x), byrow = TRUE))^2))
  between <- sum(vapply(levels(labels), function(g) {
    ids <- labels == g
    sum(ids) * sum((colMeans(x[ids, , drop = FALSE]) - center)^2)
  }, numeric(1)))
  between / total
}

run_independent_statistical_audit <- function(
    processed_dir = file.path("data", "processed"),
    results_dir = "results",
    figures_dir = "figures",
    seed = 20261108L,
    subsample_repetitions = 25L) {

  message("[Independent audit] Verifying agreement, geometry, and stability...")
  ensure_dirs(c(processed_dir, results_dir, figures_dir))
  analysis <- data.table::as.data.table(readRDS(file.path(processed_dir, "analysis_cohort.rds")))
  spec <- readRDS(file.path(processed_dir, "analysis_spec.rds"))
  mclust_fit <- readRDS(file.path(processed_dir, "mclust_final_fit.rds"))
  tclust_fit <- readRDS(file.path(processed_dir, "tclust_primary_fit.rds"))
  component_map <- data.table::fread(file.path(results_dir, "mclust_component_profile_map.csv"))
  recorded_tclust <- data.table::fread(file.path(results_dir, "tclust_primary_assignments.csv"))

  z_features <- spec$z_features
  original_features <- spec$original_features
  x <- as.matrix(analysis[, ..z_features])
  storage.mode(x) <- "double"
  n <- nrow(x)
  selected_g <- mclust_fit$G
  selected_model <- mclust_fit$modelName
  primary_model_label <- sprintf("Mclust G=%d %s", selected_g, selected_model)
  tclust_model_label <- sprintf("TCLUST retained G=%d", selected_g)
  assert_true(n == length(mclust_fit$classification), "Mclust assignment length mismatch in independent audit.")
  assert_true(n == length(tclust_fit$cluster), "TCLUST assignment length mismatch in independent audit.")
  assert_true(!"final_result" %in% colnames(x), "Outcome leakage detected in independent audit matrix.")

  keys <- c("code_module", "code_presentation", "id_student")
  independent_assignments <- analysis[, ..keys]
  independent_assignments[, mclust_component := as.integer(mclust_fit$classification)]
  independent_assignments[, tclust_cluster := as.integer(tclust_fit$cluster)]
  key_unique <- uniqueN(independent_assignments, by = keys) == n
  recorded_compare <- merge(
    independent_assignments,
    recorded_tclust[, c(keys, "mclust_component", "tclust_cluster"), with = FALSE],
    by = keys,
    suffixes = c("_independent", "_recorded"),
    sort = TRUE
  )
  key_alignment_exact <- nrow(recorded_compare) == n &&
    all(recorded_compare$mclust_component_independent == recorded_compare$mclust_component_recorded) &&
    all(recorded_compare$tclust_cluster_independent == recorded_compare$tclust_cluster_recorded)

  retained <- tclust_fit$cluster > 0L
  package_ari <- mclust::adjustedRandIndex(
    tclust_fit$cluster[retained], mclust_fit$classification[retained]
  )
  manual_ari <- manual_adjusted_rand_index(
    tclust_fit$cluster[retained], mclust_fit$classification[retained]
  )
  full_label_ari <- manual_adjusted_rand_index(tclust_fit$cluster, mclust_fit$classification)
  ari_verification <- data.table::data.table(
    comparison = c(
      "Package ARI on TCLUST-retained observations",
      "Independent manual ARI on TCLUST-retained observations",
      "Diagnostic only: ARI treating trimmed cases as a fourth label"
    ),
    n_compared = c(sum(retained), sum(retained), n),
    trimmed_excluded = c(TRUE, TRUE, FALSE),
    ari = c(package_ari, manual_ari, full_label_ari),
    valid_primary_comparison = c(TRUE, TRUE, FALSE),
    note = c(
      sprintf("Same enrollment order and same %d requested clusters; TCLUST label 0 excluded.", selected_g),
      "Computed directly from pair-count contingency formula; independent of mclust ARI code.",
      "Reported only to show why treating trimming as a substantive cluster is inappropriate."
    ),
    unique_enrollment_keys = key_unique,
    recorded_assignment_alignment_exact = key_alignment_exact
  )

  comparison <- data.table::data.table(
    mclust_component = as.integer(mclust_fit$classification),
    tclust_cluster = as.integer(tclust_fit$cluster)
  )
  comparison <- component_map[comparison, on = "mclust_component"]
  retained_tab <- comparison[tclust_cluster > 0L, .N, by = .(tclust_cluster, profile_id)]
  retained_tab[, tclust_n := sum(N), by = tclust_cluster]
  retained_tab[, mclust_profile_n_retained := sum(N), by = profile_id]
  retained_tab[, proportion_within_tclust := N / tclust_n]
  retained_tab[, proportion_of_mclust_profile_retained := N / mclust_profile_n_retained]
  data.table::setorder(retained_tab, tclust_cluster, profile_id)

  trimmed_profile <- comparison[tclust_cluster == 0L, .N, by = profile_id]
  trimmed_profile[, trimmed_proportion := N / sum(N)]
  total_profile <- comparison[, .(profile_total_n = .N), by = profile_id]
  trimmed_profile <- total_profile[trimmed_profile, on = "profile_id"]
  trimmed_profile[, proportion_of_profile_trimmed := N / profile_total_n]

  pca <- stats::prcomp(x, center = FALSE, scale. = FALSE)
  pca_variance <- pca$sdev^2
  pca_table <- data.table::data.table(
    component = paste0("PC", seq_along(pca_variance)),
    eigenvalue = pca_variance,
    variance_proportion = pca_variance / sum(pca_variance),
    cumulative_variance_proportion = cumsum(pca_variance / sum(pca_variance))
  )
  loadings <- data.table::as.data.table(pca$rotation, keep.rownames = "model_feature")
  loadings_long <- data.table::melt(
    loadings,
    id.vars = "model_feature",
    variable.name = "component",
    value.name = "loading"
  )

  silhouette_mclust <- cluster::silhouette(mclust_fit$classification, stats::dist(x))[, "sil_width"]
  silhouette_tclust <- cluster::silhouette(
    tclust_fit$cluster[retained], stats::dist(x[retained, , drop = FALSE])
  )[, "sil_width"]
  posterior_entropy <- -rowSums(mclust_fit$z * log(pmax(mclust_fit$z, .Machine$double.xmin))) / log(mclust_fit$G)
  separation <- data.table::data.table(
    method = c(primary_model_label, tclust_model_label),
    n = c(n, sum(retained)),
    k_nonempty = c(length(unique(mclust_fit$classification)), length(unique(tclust_fit$cluster[retained]))),
    mean_silhouette = c(mean(silhouette_mclust), mean(silhouette_tclust)),
    median_silhouette = c(stats::median(silhouette_mclust), stats::median(silhouette_tclust)),
    negative_silhouette_proportion = c(mean(silhouette_mclust < 0), mean(silhouette_tclust < 0)),
    between_total_ss_ratio = c(
      between_total_ratio(x, mclust_fit$classification),
      between_total_ratio(x[retained, , drop = FALSE], tclust_fit$cluster[retained])
    ),
    mean_normalized_posterior_entropy = c(mean(posterior_entropy), NA_real_)
  )

  bic_grid <- data.table::fread(file.path(results_dir, "mclust_bic_grid.csv"))
  best_bic <- max(bic_grid$BIC, na.rm = TRUE)
  best_by_g <- bic_grid[is.finite(BIC), .SD[which.max(BIC)], by = G]
  best_by_g[, delta_from_global_best := best_bic - BIC]
  best_by_g[, evidence_note := data.table::fcase(
    delta_from_global_best < 2, "competitive with global best",
    delta_from_global_best < 10, "materially less supported",
    default = "strongly less supported by BIC"
  )]
  data.table::setorder(best_by_g, G)

  robust_initialization_x <- apply(x, 2, function(v) {
    scale_value <- stats::mad(v)
    if (!is.finite(scale_value) || scale_value == 0) scale_value <- stats::sd(v)
    (v - stats::median(v)) / scale_value
  })
  icl_initializations <- list(
    full_standardized_hierarchy = list(hcPairs = mclust::hc(
      x,
      modelName = mclust::mclust.options("hcModelName"),
      use = mclust::mclust.options("hcUse")
    )),
    full_robust_affine_hierarchy = list(hcPairs = mclust::hc(
      robust_initialization_x,
      modelName = mclust::mclust.options("hcModelName"),
      use = mclust::mclust.options("hcUse")
    ))
  )
  for (s in seq_len(3L)) {
    set.seed(seed + 2000L + s)
    icl_initializations[[paste0("random_subset_", s)]] <- list(
      subset = sample.int(n, min(n - 1L, 1000L), replace = FALSE)
    )
  }
  icl_rows <- list()
  for (init_id in names(icl_initializations)) {
    run <- tryCatch(
      capture_warnings(mclust::mclustICL(
        data = x,
        G = 1:9,
        modelNames = mclust::mclust.options("emModelNames"),
        initialization = icl_initializations[[init_id]]
      )),
      error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
    )
    if (is.null(run$value)) next
    this_icl <- data.table::as.data.table(as.table(as.matrix(run$value)))
    data.table::setnames(this_icl, c("G", "model", "ICL"))
    this_icl[, G := as.integer(as.character(G))]
    this_icl[, model := as.character(model)]
    this_icl[, initialization_id := init_id]
    this_icl[, warnings := paste(run$warnings, collapse = " | ")]
    icl_rows[[length(icl_rows) + 1L]] <- this_icl
  }
  assert_true(length(icl_rows) >= 2L, "Too few successful ICL initialization searches.")
  icl_initialization_audit <- data.table::rbindlist(icl_rows, fill = TRUE)
  icl_long <- icl_initialization_audit[is.finite(ICL), .SD[which.max(ICL)], by = .(G, model)]
  data.table::setorder(icl_long, -ICL)
  icl_long[, icl_rank := seq_len(.N)]

  rank_gaussian <- function(v) {
    stats::qnorm((rank(v, ties.method = "average") - 0.5) / length(v))
  }
  standardize_matrix <- function(mat) {
    ans <- scale(mat)
    storage.mode(ans) <- "double"
    ans
  }
  original <- as.matrix(analysis[, ..original_features])
  log_matrix <- log1p(original)
  robust_center <- apply(log_matrix, 2, stats::median)
  robust_scale <- apply(log_matrix, 2, stats::mad)
  robust_scale[robust_scale == 0] <- apply(log_matrix, 2, stats::sd)[robust_scale == 0]
  robust_scaled <- sweep(sweep(log_matrix, 2, robust_center, "-"), 2, robust_scale, "/")
  pca_rotated <- pca$x

  specification_matrices <- list(
    primary_log1p_three_features = x,
    log1p_robust_affine_scaling = robust_scaled,
    log1p_orthogonal_pc_rotation = pca_rotated,
    square_root_three_features = standardize_matrix(sqrt(original)),
    marginal_rank_gaussian_three_features = standardize_matrix(apply(original, 2, rank_gaussian)),
    first_principal_component_only = matrix(pca$x[, 1], ncol = 1L, dimnames = list(NULL, "PC1")),
    log1p_without_total_clicks = x[, setdiff(colnames(x), "z_total_clicks"), drop = FALSE],
    log1p_without_active_days = x[, setdiff(colnames(x), "z_active_days"), drop = FALSE],
    log1p_without_distinct_resources = x[, setdiff(colnames(x), "z_distinct_resources"), drop = FALSE]
  )
  specification_descriptions <- c(
    primary_log1p_three_features = "Primary specification",
    log1p_robust_affine_scaling = "Affine re-scaling check for initialization and numerical equivariance",
    log1p_orthogonal_pc_rotation = "Coordinate-rotation check for initialization and covariance search",
    square_root_three_features = "Less aggressive defensible count transformation",
    marginal_rank_gaussian_three_features = "Diagnostic marginal Gaussianization; changes metric and count spacing",
    first_principal_component_only = "One-dimensional engagement-intensity sensitivity; PC1 retains most variance",
    log1p_without_total_clicks = "Leave-one-feature-out redundancy check",
    log1p_without_active_days = "Leave-one-feature-out redundancy check",
    log1p_without_distinct_resources = "Leave-one-feature-out redundancy check"
  )

  specification_rows <- vector("list", length(specification_matrices))
  names_spec <- names(specification_matrices)
  for (i in seq_along(specification_matrices)) {
    spec_name <- names_spec[i]
    mat <- specification_matrices[[i]]
    if (spec_name == "primary_log1p_three_features") {
      fit <- mclust_fit
      warnings <- ""
    } else {
      set.seed(seed + 3000L + i)
      run <- tryCatch(
        capture_warnings(mclust::Mclust(mat, G = 1:9)),
        error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
      )
      fit <- run$value
      warnings <- paste(run$warnings, collapse = " | ")
    }
    if (is.null(fit)) {
      specification_rows[[i]] <- data.table::data.table(
        specification = spec_name,
        description = specification_descriptions[[spec_name]],
        success = FALSE,
        dimensions = ncol(mat),
        selected_G = NA_integer_, selected_model = NA_character_, BIC = NA_real_,
        ARI_vs_primary = NA_real_, mean_uncertainty = NA_real_, minimum_component_n = NA_integer_,
        warnings = warnings
      )
    } else {
      specification_rows[[i]] <- data.table::data.table(
        specification = spec_name,
        description = specification_descriptions[[spec_name]],
        success = TRUE,
        dimensions = ncol(mat),
        selected_G = fit$G,
        selected_model = fit$modelName,
        BIC = fit$bic,
        ARI_vs_primary = mclust::adjustedRandIndex(fit$classification, mclust_fit$classification),
        mean_uncertainty = mean(1 - apply(fit$z, 1, max)),
        minimum_component_n = min(table(fit$classification)),
        warnings = warnings
      )
    }
  }
  specification_sensitivity <- data.table::rbindlist(specification_rows, fill = TRUE)
  specification_sensitivity[, bic_comparison_note := "BIC values are not compared across transformations or dimensions."]

  subsample_rows <- vector("list", subsample_repetitions)
  subsample_n <- floor(0.80 * n)
  for (r in seq_len(subsample_repetitions)) {
    set.seed(seed + 4000L + r)
    ids <- sample.int(n, subsample_n, replace = FALSE)
    fixed_run <- tryCatch(
      capture_warnings(mclust::Mclust(
        x[ids, , drop = FALSE], G = selected_g, modelNames = selected_model
      )),
      error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
    )
    selected_run <- tryCatch(
      capture_warnings(mclust::Mclust(x[ids, , drop = FALSE], G = 1:9)),
      error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
    )
    fixed_fit <- fixed_run$value
    selected_fit <- selected_run$value
    fixed_prediction <- if (is.null(fixed_fit)) NULL else tryCatch(
      predict(fixed_fit, newdata = x)$classification,
      error = function(e) NULL
    )
    selected_prediction <- if (is.null(selected_fit)) NULL else tryCatch(
      predict(selected_fit, newdata = x)$classification,
      error = function(e) NULL
    )
    subsample_rows[[r]] <- data.table::data.table(
      repetition = r,
      sample_fraction = 0.80,
      sample_n = subsample_n,
      fixed_primary_success = !is.null(fixed_prediction),
      fixed_primary_ARI_vs_primary = if (is.null(fixed_prediction)) NA_real_ else
        mclust::adjustedRandIndex(fixed_prediction, mclust_fit$classification),
      selected_model_success = !is.null(selected_prediction),
      selected_G = if (is.null(selected_fit)) NA_integer_ else selected_fit$G,
      selected_model = if (is.null(selected_fit)) NA_character_ else selected_fit$modelName,
      selected_ARI_vs_primary = if (is.null(selected_prediction)) NA_real_ else
        mclust::adjustedRandIndex(selected_prediction, mclust_fit$classification),
      fixed_warnings = paste(fixed_run$warnings, collapse = " | "),
      selected_warnings = paste(selected_run$warnings, collapse = " | ")
    )
  }
  subsample_stability <- data.table::rbindlist(subsample_rows, fill = TRUE)
  selection_frequency <- subsample_stability[selected_model_success == TRUE, .N, by = .(selected_G, selected_model)]
  selection_frequency[, proportion := N / sum(N)]
  data.table::setorder(selection_frequency, -N, selected_G, selected_model)

  fit_tclust_audit <- function(alpha, restriction, fit_seed, nstart = 200L) {
    set.seed(fit_seed)
    tryCatch(
      capture_warnings(tclust::tclust(
        x = x, k = selected_g, alpha = alpha, restr.fact = restriction,
        nstart = nstart, nkeep = 10L, trace = 0
      )),
      error = function(e) list(value = NULL, warnings = paste("ERROR:", conditionMessage(e)))
    )
  }
  extended_grid <- data.table::CJ(alpha = c(0, 0.05), restriction_factor = c(20, 200, 1000))
  extended_rows <- vector("list", nrow(extended_grid))
  for (i in seq_len(nrow(extended_grid))) {
    run <- fit_tclust_audit(
      extended_grid$alpha[i], extended_grid$restriction_factor[i], seed + 5000L + i
    )
    fit <- run$value
    if (is.null(fit)) {
      extended_rows[[i]] <- data.table::data.table(
        alpha = extended_grid$alpha[i], restriction_factor = extended_grid$restriction_factor[i],
        success = FALSE, nonempty_clusters = NA_integer_, retained_n = NA_integer_,
        ARI_vs_mclust_retained = NA_real_, objective = NA_real_, warnings = paste(run$warnings, collapse = " | ")
      )
    } else {
      keep <- fit$cluster > 0L
      nonempty <- length(unique(fit$cluster[keep]))
      extended_rows[[i]] <- data.table::data.table(
        alpha = extended_grid$alpha[i], restriction_factor = extended_grid$restriction_factor[i],
        success = TRUE, nonempty_clusters = nonempty, retained_n = sum(keep),
        min_cluster_n = min(table(fit$cluster[keep])), max_cluster_n = max(table(fit$cluster[keep])),
        ARI_vs_mclust_retained = if (nonempty == selected_g) mclust::adjustedRandIndex(
          fit$cluster[keep], mclust_fit$classification[keep]
        ) else NA_real_,
        objective = fit$obj, warnings = paste(run$warnings, collapse = " | ")
      )
    }
  }
  extended_tclust <- data.table::rbindlist(extended_rows, fill = TRUE)

  pc_scores <- data.table::data.table(
    PC1 = pca$x[, 1],
    mclust_component = as.integer(mclust_fit$classification),
    tclust_cluster = as.integer(tclust_fit$cluster)
  )
  pc_scores <- component_map[pc_scores, on = "mclust_component"]
  density_plot_data <- data.table::rbindlist(list(
    pc_scores[, .(PC1, method = "Mclust", group = profile_id)],
    pc_scores[, .(
      PC1,
      method = "TCLUST",
      group = data.table::fifelse(tclust_cluster == 0L, "Trimmed", paste0("T", tclust_cluster))
    )]
  ))

  p_disagreement <- ggplot2::ggplot(
    retained_tab,
    ggplot2::aes(profile_id, factor(tclust_cluster), fill = proportion_within_tclust)
  ) +
    ggplot2::geom_tile(color = "white", linewidth = 0.8) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("n=%d\n%.1f%%", N, 100 * proportion_within_tclust)), size = 3.5) +
    ggplot2::scale_fill_gradient(low = "#F7FBFF", high = "#176B87", labels = scales::percent_format()) +
    ggplot2::labs(
      title = "Why Mclust and TCLUST disagree",
      subtitle = "Cell percentages are within TCLUST groups; 101 trimmed observations are excluded",
      x = "Gaussian-mixture profile",
      y = "TCLUST cluster (unmatched numeric label)",
      fill = "Within TCLUST"
    ) +
    project_theme()
  save_plot(p_disagreement, file.path(figures_dir, "17_method_disagreement_crosstab.png"), width = 8, height = 5.5)

  p_pc1 <- ggplot2::ggplot(density_plot_data, ggplot2::aes(PC1, color = group, fill = group)) +
    ggplot2::geom_density(alpha = 0.12, linewidth = 0.8) +
    ggplot2::facet_wrap(~method, ncol = 1, scales = "free_y") +
    ggplot2::labs(
      title = "Both methods partition a dominant engagement axis differently",
      subtitle = sprintf("PC1 explains %.1f%% of standardized log-feature variance", 100 * pca_table$variance_proportion[1]),
      x = "First principal-component score",
      y = "Density",
      color = "Assigned group",
      fill = "Assigned group"
    ) +
    project_theme()
  save_plot(p_pc1, file.path(figures_dir, "18_engagement_axis_by_method.png"), width = 9, height = 7)

  stability_plot_data <- data.table::rbindlist(list(
    subsample_stability[fixed_primary_success == TRUE, .(
      repetition, fit = "Fixed primary specification", ARI = fixed_primary_ARI_vs_primary
    )],
    subsample_stability[selected_model_success == TRUE, .(
      repetition, fit = "BIC reselected G/model", ARI = selected_ARI_vs_primary
    )]
  ))
  p_stability <- ggplot2::ggplot(stability_plot_data, ggplot2::aes(fit, ARI, fill = fit)) +
    ggplot2::geom_boxplot(width = 0.5, outlier.shape = NA, alpha = 0.55) +
    ggplot2::geom_jitter(width = 0.08, height = 0, alpha = 0.7, size = 1.7) +
    ggplot2::scale_fill_manual(values = c("Fixed primary specification" = "#D55E00", "BIC reselected G/model" = "#176B87"), guide = "none") +
    ggplot2::coord_cartesian(ylim = c(0, 1)) +
    ggplot2::labs(
      title = "Case-subsampling stability of the Gaussian partition",
      subtitle = sprintf("%d outcome-blind 80%% subsamples; predictions evaluated on all %d enrollments", subsample_repetitions, n),
      x = NULL,
      y = "ARI versus the primary Gaussian partition"
    ) +
    project_theme()
  save_plot(p_stability, file.path(figures_dir, "19_mclust_subsample_stability.png"), width = 8.5, height = 5.5)

  plot_spec <- specification_sensitivity[success == TRUE]
  p_spec <- ggplot2::ggplot(
    plot_spec,
    ggplot2::aes(reorder(specification, ARI_vs_primary), ARI_vs_primary)
  ) +
    ggplot2::geom_col(fill = "#5B4B8A", width = 0.7) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("ARI %.2f | G=%d %s", ARI_vs_primary, selected_G, selected_model)),
      hjust = -0.03, size = 3
    ) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(limits = c(0, 1.18), expand = ggplot2::expansion(mult = c(0, 0))) +
    ggplot2::labs(
      title = "Sensitivity to transformations and feature omission",
      subtitle = "Each alternative reselects G and covariance by BIC; outcomes are never used",
      x = NULL,
      y = sprintf("ARI versus primary G=%d %s partition", selected_g, selected_model)
    ) +
    project_theme()
  save_plot(p_spec, file.path(figures_dir, "20_mclust_specification_sensitivity.png"), width = 10, height = 6.5)

  fixed_success <- subsample_stability[fixed_primary_success == TRUE]$fixed_primary_ARI_vs_primary
  selected_success <- subsample_stability[selected_model_success == TRUE]$selected_ARI_vs_primary
  top_icl <- icl_long[1]
  second_bic <- bic_grid[is.finite(BIC)][order(-BIC)][2]
  summary_table <- data.table::data.table(
    diagnostic = c(
      "Primary ARI independently verified",
      "Retained observations",
      "Trimmed observations excluded from primary ARI",
      "PC1 variance proportion",
      "Mclust mean silhouette",
      "Mclust negative silhouette proportion",
      "Mean normalized posterior entropy",
      "BIC gap to second-ranked model",
      "ICL preferred specification",
      sprintf("Fixed G=%d %s subsample ARI median", selected_g, selected_model),
      "BIC-reselected subsample ARI median",
      sprintf("Fixed G=%d %s subsample successes", selected_g, selected_model),
      "BIC-reselected subsample successes"
    ),
    value = c(
      sprintf("%.9f", manual_ari),
      as.character(sum(retained)),
      as.character(sum(!retained)),
      sprintf("%.4f", pca_table$variance_proportion[1]),
      sprintf("%.4f", separation[method == primary_model_label]$mean_silhouette),
      sprintf("%.4f", separation[method == primary_model_label]$negative_silhouette_proportion),
      sprintf("%.4f", mean(posterior_entropy)),
      sprintf("%.3f", best_bic - second_bic$BIC),
      sprintf("G=%d %s", top_icl$G, top_icl$model),
      sprintf("%.4f", stats::median(fixed_success, na.rm = TRUE)),
      sprintf("%.4f", stats::median(selected_success, na.rm = TRUE)),
      sprintf("%d/%d", length(fixed_success), subsample_repetitions),
      sprintf("%d/%d", length(selected_success), subsample_repetitions)
    ),
    interpretation = c(
      "Matches package ARI to numerical tolerance on identical retained enrollments.",
      sprintf("Only TCLUST labels 1-%d are compared.", selected_g),
      "TCLUST label 0 is trimming status, not a fourth cluster.",
      "High concentration on one engagement-intensity direction explains method-dependent cut points.",
      "Low values indicate weak Euclidean separation despite likelihood-based density improvement.",
      "Negative values indicate many cases are closer on average to another hard group.",
      "Posterior overlap is material and hard labels discard information.",
      "BIC favors the primary density model, but BIC does not prove natural clusters.",
      "ICL explicitly penalizes classification entropy and is an important clustering diagnostic.",
      "Conditional stability of the chosen specification under case perturbation.",
      "Joint model-selection and assignment stability under case perturbation.",
      "Technical success count for fixed-specification subsampling.",
      "Technical success count for model-reselection subsampling."
    )
  )

  write_csv(ari_verification, file.path(results_dir, "independent_ari_verification.csv"))
  write_csv(retained_tab, file.path(results_dir, "method_disagreement_crosstab.csv"))
  write_csv(trimmed_profile, file.path(results_dir, "trimmed_profile_composition.csv"))
  write_csv(pca_table, file.path(results_dir, "engagement_geometry_pca.csv"))
  write_csv(loadings_long, file.path(results_dir, "engagement_geometry_loadings.csv"))
  write_csv(separation, file.path(results_dir, "cluster_separation_diagnostics.csv"))
  write_csv(best_by_g, file.path(results_dir, "mclust_best_model_by_g.csv"))
  write_csv(icl_long, file.path(results_dir, "mclust_icl_grid.csv"))
  write_csv(icl_initialization_audit, file.path(results_dir, "mclust_icl_initialization_audit.csv"))
  write_csv(specification_sensitivity, file.path(results_dir, "mclust_specification_sensitivity.csv"))
  write_csv(subsample_stability, file.path(results_dir, "mclust_subsample_stability.csv"))
  write_csv(selection_frequency, file.path(results_dir, "mclust_subsample_selection_frequency.csv"))
  write_csv(extended_tclust, file.path(results_dir, "tclust_extended_restriction_sensitivity.csv"))
  write_csv(summary_table, file.path(results_dir, "independent_statistical_audit_summary.csv"))

  assert_true(key_unique && key_alignment_exact, "Independent audit found assignment-key misalignment.")
  assert_true(abs(package_ari - manual_ari) < 1e-12, "Independent manual ARI does not match package ARI.")
  assert_true(length(fixed_success) > 0L, "All fixed-specification subsample fits failed.")
  assert_true(length(selected_success) > 0L, "All model-selection subsample fits failed.")

  message(sprintf(
    paste0(
      "[Independent audit] ARI verified at %.6f on %d retained cases; PC1 explains %.1f%%; ",
      "median subsample ARI fixed/reselected = %.3f/%.3f."
    ),
    manual_ari, sum(retained), 100 * pca_table$variance_proportion[1],
    stats::median(fixed_success), stats::median(selected_success)
  ))

  invisible(list(
    ari_verification = ari_verification,
    disagreement = retained_tab,
    pca = pca_table,
    separation = separation,
    specification_sensitivity = specification_sensitivity,
    subsample_stability = subsample_stability,
    extended_tclust = extended_tclust,
    summary = summary_table
  ))
}
