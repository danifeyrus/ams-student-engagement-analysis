run_eda <- function(
    processed_dir = file.path("data", "processed"),
    results_dir = "results",
    figures_dir = "figures") {

  message("[Phase 2] Producing EDA tables and figures...")
  ensure_dirs(c(results_dir, figures_dir))
  analysis <- data.table::as.data.table(readRDS(file.path(processed_dir, "analysis_cohort.rds")))
  spec <- readRDS(file.path(processed_dir, "analysis_spec.rds"))
  original_features <- spec$original_features
  log_features <- spec$log_features

  summarize_feature <- function(x, variable, scale_name) {
    q <- stats::quantile(x, probs = c(0.01, 0.25, 0.50, 0.75, 0.95, 0.99), names = FALSE)
    data.table::data.table(
      variable = variable,
      scale = scale_name,
      n = length(x),
      missing_n = sum(is.na(x)),
      zero_n = sum(x == 0, na.rm = TRUE),
      zero_pct = mean(x == 0, na.rm = TRUE),
      mean = mean(x, na.rm = TRUE),
      sd = stats::sd(x, na.rm = TRUE),
      minimum = min(x, na.rm = TRUE),
      p01 = q[1],
      q1 = q[2],
      median = q[3],
      q3 = q[4],
      p95 = q[5],
      p99 = q[6],
      maximum = max(x, na.rm = TRUE),
      skewness = sample_skewness(x),
      excess_kurtosis = sample_excess_kurtosis(x)
    )
  }

  feature_summary <- data.table::rbindlist(c(
    lapply(original_features, function(v) summarize_feature(analysis[[v]], v, "original")),
    lapply(log_features, function(v) summarize_feature(analysis[[v]], v, "log1p"))
  ))

  outlier_summary <- data.table::rbindlist(lapply(original_features, function(v) {
    x <- analysis[[v]]
    qs <- stats::quantile(x, c(0.25, 0.75), names = FALSE)
    cutoff <- qs[2] + 1.5 * (qs[2] - qs[1])
    data.table::data.table(
      variable = v,
      iqr_upper_cutoff = cutoff,
      above_cutoff_n = sum(x > cutoff),
      above_cutoff_pct = mean(x > cutoff),
      maximum = max(x)
    )
  }))

  selected_outcomes <- analysis[, .N, by = final_result][order(final_result)]
  selected_outcomes[, proportion := N / sum(N)]

  original_cor <- stats::cor(analysis[, ..original_features], method = "spearman")
  log_cor <- stats::cor(analysis[, ..log_features], method = "pearson")
  original_cor_long <- data.table::as.data.table(as.table(original_cor))
  log_cor_long <- data.table::as.data.table(as.table(log_cor))
  data.table::setnames(original_cor_long, c("feature_x", "feature_y", "correlation"))
  data.table::setnames(log_cor_long, c("feature_x", "feature_y", "correlation"))
  original_cor_long[, method := "Spearman, original scale"]
  log_cor_long[, method := "Pearson, log1p scale"]
  correlation_long <- data.table::rbindlist(list(original_cor_long, log_cor_long))

  write_csv(feature_summary, file.path(results_dir, "eda_feature_summary.csv"))
  write_csv(outlier_summary, file.path(results_dir, "eda_outlier_summary.csv"))
  write_csv(selected_outcomes, file.path(results_dir, "selected_cohort_outcomes_overall.csv"))
  write_csv(correlation_long, file.path(results_dir, "eda_feature_correlations_long.csv"))

  cohort_comparison <- data.table::fread(file.path(results_dir, "cohort_comparison.csv"))
  cohort_comparison[, cohort := paste(code_module, code_presentation, sep = "-")]
  data.table::setorder(cohort_comparison, eligible_full_window)
  cohort_comparison[, cohort := factor(cohort, levels = cohort)]
  p_cohort <- ggplot2::ggplot(
    cohort_comparison,
    ggplot2::aes(x = cohort, y = eligible_full_window, fill = selected_cohort)
  ) +
    ggplot2::geom_col(width = 0.78) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c(`FALSE` = "#B9C2CC", `TRUE` = "#176B87"), guide = "none") +
    ggplot2::labs(
      title = "Outcome-blind cohort comparison",
      subtitle = "Eligible enrollments registered by day 0 and observed through day 27",
      x = NULL,
      y = "Eligible enrollments"
    ) +
    project_theme()
  save_plot(p_cohort, file.path(figures_dir, "01_cohort_comparison.png"), width = 8, height = 7)

  cohort_flow <- data.table::fread(file.path(results_dir, "cohort_inclusion_flow.csv"))
  cohort_flow[, stage := factor(stage, levels = rev(stage))]
  p_flow <- ggplot2::ggplot(cohort_flow, ggplot2::aes(stage, n)) +
    ggplot2::geom_col(fill = "#176B87", width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = scales::comma(n)), hjust = -0.12, size = 3.5) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.14))) +
    ggplot2::labs(
      title = "Primary cohort inclusion flow",
      subtitle = paste(spec$selected_module, spec$selected_presentation),
      x = NULL,
      y = "Enrollments"
    ) +
    project_theme()
  save_plot(p_flow, file.path(figures_dir, "02_cohort_inclusion_flow.png"), width = 8, height = 4.8)

  daily_activity <- data.table::fread(file.path(results_dir, "selected_cohort_daily_activity.csv"))
  p_daily <- ggplot2::ggplot(daily_activity, ggplot2::aes(date, active_students)) +
    ggplot2::geom_area(fill = "#64CCC5", alpha = 0.55) +
    ggplot2::geom_line(color = "#176B87", linewidth = 0.8) +
    ggplot2::scale_x_continuous(breaks = seq(0, 27, 3)) +
    ggplot2::labs(
      title = "Daily activity coverage in the 28-day window",
      subtitle = "Distinct students with at least one recorded VLE interaction",
      x = "Course day",
      y = "Active students"
    ) +
    project_theme()
  save_plot(p_daily, file.path(figures_dir, "03_daily_activity_coverage.png"), width = 8, height = 4.8)

  original_long <- data.table::melt(
    analysis[, ..original_features],
    measure.vars = original_features,
    variable.name = "feature",
    value.name = "value"
  )
  p99_limits <- original_long[, .(p99 = stats::quantile(value, 0.99)), by = feature]
  original_display <- merge(original_long, p99_limits, by = "feature")[value <= p99]
  p_original <- ggplot2::ggplot(original_display, ggplot2::aes(value)) +
    ggplot2::geom_histogram(bins = 35, fill = "#176B87", color = "white", linewidth = 0.2) +
    ggplot2::facet_wrap(~feature, scales = "free", ncol = 1) +
    ggplot2::labs(
      title = "Early-engagement indicators on their original scales",
      subtitle = "Primary cohort, course days 0-27",
      caption = "Axes are limited to each feature's 99th percentile for readability; maxima are retained in analysis and reported in the EDA table.",
      x = NULL,
      y = "Enrollments"
    ) +
    project_theme()
  save_plot(p_original, file.path(figures_dir, "04_feature_distributions_original.png"), width = 8, height = 8)

  log_long <- data.table::melt(
    analysis[, ..log_features],
    measure.vars = log_features,
    variable.name = "feature",
    value.name = "value"
  )
  p_log <- ggplot2::ggplot(log_long, ggplot2::aes(value)) +
    ggplot2::geom_histogram(bins = 35, fill = "#DA7B27", color = "white", linewidth = 0.2) +
    ggplot2::facet_wrap(~feature, scales = "free", ncol = 1) +
    ggplot2::labs(
      title = "Log1p-transformed engagement indicators",
      subtitle = "Log transformation reduces, but does not guarantee removal of, skewness or non-Gaussian structure",
      x = NULL,
      y = "Enrollments"
    ) +
    project_theme()
  save_plot(p_log, file.path(figures_dir, "05_feature_distributions_log1p.png"), width = 8, height = 8)

  p_cor <- ggplot2::ggplot(
    correlation_long,
    ggplot2::aes(feature_x, feature_y, fill = correlation)
  ) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", correlation)), size = 3.3) +
    ggplot2::facet_wrap(~method) +
    ggplot2::scale_fill_gradient2(low = "#B2182B", mid = "white", high = "#2166AC", midpoint = 0, limits = c(-1, 1)) +
    ggplot2::coord_equal() +
    ggplot2::labs(
      title = "Feature dependence before clustering",
      x = NULL,
      y = NULL,
      fill = "Correlation"
    ) +
    project_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))
  save_plot(p_cor, file.path(figures_dir, "06_feature_correlation.png"), width = 10, height = 5)

  selected_outcomes[, final_result := factor(final_result, levels = c("Distinction", "Pass", "Fail", "Withdrawn"))]
  p_outcome <- ggplot2::ggplot(selected_outcomes, ggplot2::aes(final_result, proportion, fill = final_result)) +
    ggplot2::geom_col(width = 0.72, show.legend = FALSE) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%s\n%.1f%%", scales::comma(N), 100 * proportion)),
      vjust = -0.25,
      size = 3.4
    ) +
    ggplot2::scale_y_continuous(labels = scales::label_percent(), expand = ggplot2::expansion(mult = c(0, 0.15))) +
    ggplot2::scale_fill_brewer(palette = "Set2") +
    ggplot2::labs(
      title = "Recorded outcomes in the selected cohort",
      subtitle = "Shown descriptively; outcomes are not clustering inputs",
      x = NULL,
      y = "Proportion of eligible enrollments"
    ) +
    project_theme()
  save_plot(p_outcome, file.path(figures_dir, "07_selected_cohort_outcomes_overall.png"), width = 8, height = 5)

  message("[Phase 2] EDA outputs written.")
  invisible(list(feature_summary = feature_summary, outcome_counts = selected_outcomes))
}

