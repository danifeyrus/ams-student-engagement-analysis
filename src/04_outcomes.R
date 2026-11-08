run_outcome_description <- function(
    processed_dir = file.path("data", "processed"),
    results_dir = "results",
    figures_dir = "figures") {

  message("[Phase 3] Describing recorded outcomes after clustering...")
  assignments <- data.table::as.data.table(readRDS(file.path(processed_dir, "mclust_assignments.rds")))
  expected_outcomes <- c("Distinction", "Pass", "Fail", "Withdrawn")
  assert_true(all(assignments$final_result %in% expected_outcomes), "Unexpected outcome value in clustered cohort.")
  profile_levels <- paste0("P", seq_len(max(assignments$profile_order)))
  assignments[, profile_id := factor(profile_id, levels = profile_levels)]
  assignments[, final_result := factor(final_result, levels = expected_outcomes)]

  counts <- assignments[, .N, by = .(profile_order, profile_id, final_result)]
  complete_grid <- data.table::CJ(
    profile_id = factor(profile_levels, levels = profile_levels),
    final_result = factor(expected_outcomes, levels = expected_outcomes),
    unique = TRUE
  )
  counts <- merge(complete_grid, counts, by = c("profile_id", "final_result"), all.x = TRUE)
  counts[is.na(N), N := 0L]
  counts[, profile_order := match(as.character(profile_id), profile_levels)]
  counts[, profile_n := sum(N), by = profile_id]
  counts[, outcome_n := sum(N), by = final_result]
  counts[, within_profile_proportion := N / profile_n]
  counts[, within_outcome_proportion := N / outcome_n]
  intervals <- t(mapply(wilson_interval, counts$N, counts$profile_n))
  counts[, wilson_95_lower := intervals[, "lower"]]
  counts[, wilson_95_upper := intervals[, "upper"]]
  data.table::setorder(counts, profile_order, final_result)

  contingency <- xtabs(N ~ profile_id + final_result, data = counts)
  chi <- suppressWarnings(stats::chisq.test(contingency, correct = FALSE))
  expected_min <- min(chi$expected)
  expected_below_5 <- sum(chi$expected < 5)
  association_summary <- data.table::data.table(
    statistic = unname(chi$statistic),
    degrees_of_freedom = unname(chi$parameter),
    p_value = chi$p.value,
    cramers_v = cramers_v(contingency),
    minimum_expected_count = expected_min,
    expected_cells_below_5 = expected_below_5,
    n = sum(contingency),
    interpretation_scope = "Descriptive association in the restricted CCC-2014J cohort; not causal and not predictive."
  )
  assert_true(expected_below_5 == 0, "Chi-squared approximation is unreliable because expected cell counts below 5 are present.")

  residuals <- data.table::as.data.table(as.table(chi$stdres))
  data.table::setnames(residuals, c("profile_id", "final_result", "standardized_residual"))
  residuals[, profile_id := factor(as.character(profile_id), levels = profile_levels)]
  residuals[, final_result := factor(as.character(final_result), levels = expected_outcomes)]
  expected_table <- data.table::as.data.table(as.table(chi$expected))
  data.table::setnames(expected_table, c("profile_id", "final_result", "expected_count"))
  residuals <- merge(residuals, expected_table, by = c("profile_id", "final_result"))

  profile_outcome_summary <- data.table::dcast(
    counts,
    profile_id + profile_n ~ final_result,
    value.var = "within_profile_proportion"
  )

  write_csv(counts, file.path(results_dir, "outcome_by_profile_long.csv"))
  write_csv(profile_outcome_summary, file.path(results_dir, "outcome_by_profile_proportions_wide.csv"))
  write_csv(association_summary, file.path(results_dir, "outcome_profile_association.csv"))
  write_csv(residuals, file.path(results_dir, "outcome_profile_standardized_residuals.csv"))

  p_outcomes <- ggplot2::ggplot(
    counts,
    ggplot2::aes(profile_id, within_profile_proportion, fill = final_result)
  ) +
    ggplot2::geom_col(width = 0.72, color = "white", linewidth = 0.2) +
    ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
    ggplot2::scale_fill_brewer(palette = "Set2") +
    ggplot2::labs(
      title = "Recorded course outcomes differ across engagement profiles",
      subtitle = "Within-profile proportions; clustering used engagement indicators only",
      x = "Early-engagement profile",
      y = "Within-profile proportion",
      fill = "Recorded outcome",
      caption = "Associations are descriptive for the restricted CCC-2014J cohort and do not establish causation."
    ) +
    project_theme()
  save_plot(p_outcomes, file.path(figures_dir, "12_outcomes_by_profile.png"), width = 8.5, height = 5.5)

  p_residual <- ggplot2::ggplot(
    residuals,
    ggplot2::aes(final_result, profile_id, fill = standardized_residual)
  ) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f", standardized_residual)), size = 3.8) +
    ggplot2::scale_fill_gradient2(
      low = "#B2182B", mid = "white", high = "#2166AC", midpoint = 0
    ) +
    ggplot2::labs(
      title = "Where the profile-outcome table differs from independence",
      subtitle = "Pearson standardized residuals; signs indicate fewer or more observations than expected",
      x = "Recorded outcome",
      y = "Early-engagement profile",
      fill = "Standardized\nresidual"
    ) +
    project_theme()
  save_plot(p_residual, file.path(figures_dir, "13_outcome_association_residuals.png"), width = 8.5, height = 4.8)

  message(sprintf(
    "[Phase 3] Outcome association: chi-squared(%d)=%.2f, Cramer's V=%.3f.",
    association_summary$degrees_of_freedom,
    association_summary$statistic,
    association_summary$cramers_v
  ))
  invisible(list(counts = counts, association = association_summary, residuals = residuals))
}

