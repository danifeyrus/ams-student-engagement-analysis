options(stringsAsFactors = FALSE, warn = 1)

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

ensure_dirs <- function(paths) {
  invisible(lapply(paths, dir.create, recursive = TRUE, showWarnings = FALSE))
}

write_csv <- function(x, path) {
  data.table::fwrite(x, path, na = "")
  invisible(path)
}

capture_warnings <- function(expr) {
  warnings <- character()
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = unique(warnings))
}

sample_skewness <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 3L || stats::sd(x) == 0) return(NA_real_)
  m <- mean(x)
  s <- stats::sd(x)
  n / ((n - 1) * (n - 2)) * sum(((x - m) / s)^3)
}

sample_excess_kurtosis <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 4L || stats::sd(x) == 0) return(NA_real_)
  m <- mean(x)
  s <- stats::sd(x)
  term1 <- n * (n + 1) / ((n - 1) * (n - 2) * (n - 3)) *
    sum(((x - m) / s)^4)
  term2 <- 3 * (n - 1)^2 / ((n - 2) * (n - 3))
  term1 - term2
}

wilson_interval <- function(x, n, level = 0.95) {
  if (n == 0) return(c(lower = NA_real_, upper = NA_real_))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- x / n
  denom <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / denom
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom
  c(lower = max(0, center - half), upper = min(1, center + half))
}

cramers_v <- function(tab) {
  test <- suppressWarnings(stats::chisq.test(tab, correct = FALSE))
  n <- sum(tab)
  dims <- dim(tab)
  sqrt(unname(test$statistic) / (n * min(dims[1] - 1, dims[2] - 1)))
}

save_plot <- function(plot, filename, width = 8, height = 5, dpi = 180) {
  ggplot2::ggsave(
    filename = filename,
    plot = plot,
    width = width,
    height = height,
    dpi = dpi,
    bg = "white"
  )
  invisible(filename)
}

project_theme <- function() {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title.position = "plot",
      plot.title = ggplot2::element_text(face = "bold"),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "bottom"
    )
}


