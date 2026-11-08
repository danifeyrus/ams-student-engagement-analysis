# AMS interactive oral-exam demonstration for Visual Studio Code
#
# In VS Code:
#   1. Run "R: Create R terminal" from the Command Palette.
#   2. Open this file and run it with Ctrl+Shift+S (source file).
#   3. Use the ams_demo_* functions listed at the end of the console output.
#
# The demonstration reads verified cached artifacts. It does not refit models.

required_packages <- c("data.table", "ggplot2", "mclust", "scales")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop(
    "Missing project packages: ", paste(missing_packages, collapse = ", "),
    ". Run renv::restore() first.",
    call. = FALSE
  )
}

source(file.path("src", "00_utils.R"))
source(file.path("src", "exam_demo.R"))

demo_required_files <- c(
  file.path("data", "processed", "mclust_assignments.rds"),
  file.path("data", "processed", "mclust_final_fit.rds"),
  file.path("data", "processed", "tclust_primary_fit.rds"),
  file.path("results", "mclust_bic_grid.csv"),
  file.path("results", "mclust_profile_summary.csv"),
  file.path("results", "outcome_by_profile_long.csv"),
  file.path("results", "tclust_configuration_sensitivity.csv"),
  file.path("results", "cluster_separation_diagnostics.csv"),
  file.path("results", "independent_statistical_audit_summary.csv"),
  file.path("results", "warnings_and_limitations.csv"),
  file.path("results", "verification_summary.csv")
)
if (!all(file.exists(demo_required_files))) {
  stop(
    "Verified cached artifacts are missing. Run source('main.R') first.",
    call. = FALSE
  )
}

ams_demo_results <- run_exam_demo()
ams_assignments <- data.table::as.data.table(
  readRDS(file.path("data", "processed", "mclust_assignments.rds"))
)
ams_selected_model <- readRDS(file.path("data", "processed", "mclust_final_fit.rds"))
ams_tclust_fit <- readRDS(file.path("data", "processed", "tclust_primary_fit.rds"))
ams_bic_grid <- data.table::fread(file.path("results", "mclust_bic_grid.csv"))
ams_profile_summary <- data.table::fread(file.path("results", "mclust_profile_summary.csv"))
ams_outcomes <- data.table::fread(file.path("results", "outcome_by_profile_long.csv"))
ams_tclust_sensitivity <- data.table::fread(
  file.path("results", "tclust_configuration_sensitivity.csv")
)
ams_separation <- data.table::fread(file.path("results", "cluster_separation_diagnostics.csv"))
ams_audit_summary <- data.table::fread(
  file.path("results", "independent_statistical_audit_summary.csv")
)
ams_limitations <- data.table::fread(file.path("results", "warnings_and_limitations.csv"))
ams_verification <- data.table::fread(file.path("results", "verification_summary.csv"))

ams_profile_colors <- c(P1 = "#1B9E77", P2 = "#D95F02", P3 = "#7570B3", P4 = "#E7298A")

ams_demo_data <- function() {
  visible_columns <- c(
    "code_module", "code_presentation", "id_student", "final_result",
    "total_clicks", "active_days", "distinct_resources",
    "profile_id", "posterior_max", "uncertainty"
  )
  table_to_view <- ams_assignments[, ..visible_columns]
  if (interactive()) {
    utils::View(table_to_view, title = "AMS analytical dataset and GMM assignments")
  } else {
    print(utils::head(table_to_view, 12L))
  }
  invisible(table_to_view)
}

ams_demo_descriptives <- function() {
  cat("\nSECTION: verified profile summaries\n")
  print(ams_profile_summary[, .(
    profile_id, n, total_clicks_median, active_days_median,
    distinct_resources_median, uncertainty_mean
  )])
  cat("\nSECTION: separation diagnostics\n")
  print(ams_separation)
  invisible(ams_profile_summary)
}

ams_demo_model <- function() {
  cat("\nSECTION: selected Gaussian mixture\n")
  print(summary(ams_selected_model, parameters = TRUE))
  cat("\nSelected G:", ams_selected_model$G, "\n")
  cat("Covariance model:", ams_selected_model$modelName, "\n")
  cat("BIC:", format(ams_selected_model$bic, digits = 10), "\n")
  invisible(ams_selected_model)
}

ams_demo_bic <- function() {
  plot_grid <- ams_bic_grid[is.finite(BIC)]
  selected <- plot_grid[selected_specification == TRUE]
  p <- ggplot2::ggplot(
    plot_grid,
    ggplot2::aes(x = G, y = BIC, color = model, group = model)
  ) +
    ggplot2::geom_line(linewidth = 0.5, alpha = 0.65) +
    ggplot2::geom_point(size = 1.4) +
    ggplot2::geom_point(
      data = selected,
      shape = 21,
      size = 4.2,
      stroke = 1.1,
      color = "black",
      fill = "#F4C95D",
      inherit.aes = FALSE,
      ggplot2::aes(x = G, y = BIC)
    ) +
    ggplot2::scale_x_continuous(breaks = sort(unique(ams_bic_grid$G))) +
    ggplot2::labs(
      title = "Gaussian-mixture model selection",
      subtitle = sprintf("Selected G=%d %s; higher BIC is better", selected$G[1], selected$model[1]),
      x = "Number of components (G)",
      y = "BIC",
      color = "Covariance model"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "bottom")
  print(p)
  invisible(p)
}

ams_demo_profiles <- function() {
  p <- ggplot2::ggplot(
    ams_assignments,
    ggplot2::aes(
      x = log_total_clicks,
      y = log_active_days,
      color = profile_id,
      alpha = posterior_max
    )
  ) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::scale_color_manual(values = ams_profile_colors) +
    ggplot2::scale_alpha_continuous(range = c(0.25, 0.9), guide = "none") +
    ggplot2::labs(
      title = "Selected Gaussian-mixture engagement profiles",
      subtitle = "Transparency reflects posterior classification certainty",
      x = "log1p(total clicks, days 0-27)",
      y = "log1p(active days, days 0-27)",
      color = "Profile"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "bottom")
  print(p)
  invisible(p)
}

ams_demo_outcomes <- function() {
  ams_outcomes[, profile_id := factor(profile_id, levels = paste0("P", 1:4))]
  p <- ggplot2::ggplot(
    ams_outcomes,
    ggplot2::aes(x = profile_id, y = within_profile_proportion, fill = final_result)
  ) +
    ggplot2::geom_col(width = 0.72, color = "white", linewidth = 0.25) +
    ggplot2::scale_y_continuous(labels = scales::label_percent()) +
    ggplot2::labs(
      title = "Recorded outcomes by engagement profile",
      subtitle = "Descriptive association only; outcomes were not used for clustering",
      x = "Early-engagement profile",
      y = "Within-profile proportion",
      fill = "Recorded outcome"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "bottom")
  print(p)
  invisible(p)
}

ams_demo_uncertainty <- function() {
  p <- ggplot2::ggplot(
    ams_assignments,
    ggplot2::aes(x = uncertainty, fill = profile_id)
  ) +
    ggplot2::geom_histogram(binwidth = 0.025, boundary = 0, color = "white") +
    ggplot2::facet_wrap(~profile_id, ncol = 1, scales = "free_y") +
    ggplot2::scale_fill_manual(values = ams_profile_colors, guide = "none") +
    ggplot2::labs(
      title = "Posterior allocation uncertainty",
      subtitle = "Uncertainty = 1 - maximum posterior membership probability",
      x = "Allocation uncertainty",
      y = "Enrollments"
    ) +
    ggplot2::theme_minimal(base_size = 12)
  print(p)
  invisible(p)
}

ams_demo_robustness <- function() {
  plot_data <- ams_tclust_sensitivity[success == TRUE]
  plot_data[, label := sprintf("alpha=%.3f, c=%s", alpha, restriction_factor)]
  plot_data[, primary := config_id == "primary_alpha005_c20"]
  p <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(x = stats::reorder(label, ARI_vs_mclust_retained), y = ARI_vs_mclust_retained, fill = primary)
  ) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c(`FALSE` = "#A8B8C5", `TRUE` = "#D95F02"), guide = "none") +
    ggplot2::scale_y_continuous(limits = c(0, 1)) +
    ggplot2::labs(
      title = "TCLUST sensitivity relative to the Gaussian partition",
      subtitle = "ARI uses only observations retained by each TCLUST fit",
      x = NULL,
      y = "Adjusted Rand index"
    ) +
    ggplot2::theme_minimal(base_size = 12)
  print(p)
  invisible(p)
}

ams_demo_limitations <- function() {
  cat("\nSECTION: independent statistical audit\n")
  print(ams_audit_summary)
  cat("\nSECTION: warnings and interpretation boundaries\n")
  print(ams_limitations)
  cat("\nSECTION: technical verification status\n")
  print(ams_verification[, .N, by = .(level, status)])
  invisible(list(audit = ams_audit_summary, limitations = ams_limitations))
}

ams_demo_all <- function(open_data = interactive()) {
  ams_demo_descriptives()
  ams_demo_model()
  if (open_data) ams_demo_data()
  ams_demo_bic()
  ams_demo_profiles()
  ams_demo_outcomes()
  ams_demo_uncertainty()
  ams_demo_robustness()
  ams_demo_limitations()
  invisible(TRUE)
}

cat("\nAMS VS CODE EXAM DEMO READY\n")
cat("============================\n")
cat("Cached verified objects are loaded in the Global Environment.\n")
cat("Run these functions section by section:\n")
cat("  ams_demo_data()          # open the analytical data table\n")
cat("  ams_demo_descriptives()  # profile and separation summaries\n")
cat("  ams_demo_model()         # inspect the selected G=4 VVE fit\n")
cat("  ams_demo_bic()           # BIC model-selection plot\n")
cat("  ams_demo_profiles()      # engagement-profile plot\n")
cat("  ams_demo_outcomes()      # outcome proportions\n")
cat("  ams_demo_uncertainty()   # posterior ambiguity\n")
cat("  ams_demo_robustness()    # TCLUST comparison\n")
cat("  ams_demo_limitations()   # audit and limitations\n")
cat("  ams_demo_all()           # run the complete cached demo\n")

if (interactive()) {
  ams_demo_model()
  ams_demo_data()
  ams_demo_bic()
} else {
  ams_demo_limitations()
}
