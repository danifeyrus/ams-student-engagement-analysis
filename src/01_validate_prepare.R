run_data_preparation <- function(
    raw_dir = file.path("data", "raw", "oulad"),
    processed_dir = file.path("data", "processed"),
    results_dir = "results",
    window_start = 0L,
    window_end = 27L) {

  message("[Phase 2] Reading and validating OULAD tables...")
  ensure_dirs(c(processed_dir, results_dir))

  required_files <- c(
    "courses.csv", "assessments.csv", "vle.csv", "studentInfo.csv",
    "studentRegistration.csv", "studentAssessment.csv", "studentVle.csv"
  )
  raw_paths <- file.path(raw_dir, required_files)
  assert_true(all(file.exists(raw_paths)), "One or more required OULAD CSV files are missing.")

  courses <- data.table::fread(file.path(raw_dir, "courses.csv"), na.strings = c("", "NA", "?"))
  assessments <- data.table::fread(file.path(raw_dir, "assessments.csv"), na.strings = c("", "NA", "?"))
  vle <- data.table::fread(file.path(raw_dir, "vle.csv"), na.strings = c("", "NA", "?"))
  student_info <- data.table::fread(file.path(raw_dir, "studentInfo.csv"), na.strings = c("", "NA", "?"))
  registration <- data.table::fread(file.path(raw_dir, "studentRegistration.csv"), na.strings = c("", "NA", "?"))
  student_assessment <- data.table::fread(file.path(raw_dir, "studentAssessment.csv"), na.strings = c("", "NA", "?"))
  student_vle <- data.table::fread(file.path(raw_dir, "studentVle.csv"), na.strings = c("", "NA", "?"))

  # The official CSVs quote the "?" missing-value token, so fread retains it
  # as text. Replace it explicitly, then recover numeric types where possible.
  normalize_official_missing <- function(dt) {
    for (col in names(dt)) {
      if (is.character(dt[[col]])) {
        values <- dt[[col]]
        values[values == "?" | values == ""] <- NA_character_
        data.table::set(dt, j = col, value = type.convert(values, as.is = TRUE))
      }
    }
    dt
  }
  courses <- normalize_official_missing(courses)
  assessments <- normalize_official_missing(assessments)
  vle <- normalize_official_missing(vle)
  student_info <- normalize_official_missing(student_info)
  registration <- normalize_official_missing(registration)
  student_assessment <- normalize_official_missing(student_assessment)
  student_vle <- normalize_official_missing(student_vle)

  expected_columns <- list(
    courses = c("code_module", "code_presentation", "module_presentation_length"),
    assessments = c("code_module", "code_presentation", "id_assessment", "assessment_type", "date", "weight"),
    vle = c("id_site", "code_module", "code_presentation", "activity_type", "week_from", "week_to"),
    student_info = c("code_module", "code_presentation", "id_student", "gender", "region", "highest_education", "imd_band", "age_band", "num_of_prev_attempts", "studied_credits", "disability", "final_result"),
    registration = c("code_module", "code_presentation", "id_student", "date_registration", "date_unregistration"),
    student_assessment = c("id_assessment", "id_student", "date_submitted", "is_banked", "score"),
    student_vle = c("code_module", "code_presentation", "id_student", "id_site", "date", "sum_click")
  )
  tables <- list(
    courses = courses,
    assessments = assessments,
    vle = vle,
    student_info = student_info,
    registration = registration,
    student_assessment = student_assessment,
    student_vle = student_vle
  )
  for (nm in names(tables)) {
    assert_true(
      identical(names(tables[[nm]]), expected_columns[[nm]]),
      sprintf("Unexpected schema for %s. Found: %s", nm, paste(names(tables[[nm]]), collapse = ", "))
    )
  }

  keys <- c("code_module", "code_presentation", "id_student")
  key_specs <- list(
    courses = c("code_module", "code_presentation"),
    assessments = "id_assessment",
    vle = c("code_module", "code_presentation", "id_site"),
    student_info = keys,
    registration = keys,
    student_assessment = c("id_assessment", "id_student"),
    student_vle = c(keys, "id_site", "date")
  )

  table_validation <- data.table::rbindlist(lapply(names(tables), function(nm) {
    dt <- tables[[nm]]
    key <- key_specs[[nm]]
    data.table::data.table(
      table = nm,
      rows = nrow(dt),
      columns = ncol(dt),
      unique_key_rows = data.table::uniqueN(dt, by = key),
      repeated_grain_rows = nrow(dt) - data.table::uniqueN(dt, by = key),
      uniqueness_required = nm != "student_vle",
      key_columns = paste(key, collapse = " + ")
    )
  }))
  assert_true(
    all(table_validation[uniqueness_required == TRUE]$repeated_grain_rows == 0),
    "Duplicate rows found on one or more documented dimension/enrollment keys."
  )

  missingness <- data.table::rbindlist(lapply(names(tables), function(nm) {
    dt <- tables[[nm]]
    data.table::data.table(
      table = nm,
      variable = names(dt),
      missing_n = vapply(dt, function(x) sum(is.na(x)), numeric(1)),
      missing_pct = vapply(dt, function(x) mean(is.na(x)), numeric(1))
    )
  }))

  course_key <- c("code_module", "code_presentation")
  join_checks <- data.table::data.table(
    check = c(
      "studentInfo keys missing from courses",
      "studentRegistration keys missing from courses",
      "vle keys missing from courses",
      "studentVle enrollment keys missing from studentInfo",
      "studentVle resource keys missing from vle",
      "studentAssessment assessment IDs missing from assessments",
      "studentInfo keys missing from registration",
      "registration keys missing from studentInfo"
    ),
    unmatched_rows = c(
      student_info[!courses, on = course_key, .N],
      registration[!courses, on = course_key, .N],
      vle[!courses, on = course_key, .N],
      student_vle[!student_info, on = keys, .N],
      student_vle[!vle, on = c("code_module", "code_presentation", "id_site"), .N],
      student_assessment[!assessments, on = "id_assessment", .N],
      student_info[!registration, on = keys, .N],
      registration[!student_info, on = keys, .N]
    )
  )
  assert_true(all(join_checks$unmatched_rows == 0), "One or more documented joins contain unmatched rows.")

  expected_outcomes <- c("Distinction", "Fail", "Pass", "Withdrawn")
  assert_true(
    identical(sort(unique(student_info$final_result)), sort(expected_outcomes)),
    "Unexpected final_result values found."
  )

  enrollment <- merge(student_info, registration, by = keys, all.x = TRUE, sort = FALSE)
  assert_true(nrow(enrollment) == nrow(student_info), "studentInfo-registration join changed enrollment cardinality.")
  enrollment[, registered_by_day0 := !is.na(date_registration) & date_registration <= window_start]
  enrollment[, active_at_day0 := registered_by_day0 & (is.na(date_unregistration) | date_unregistration >= window_start)]
  enrollment[, eligible_full_window := active_at_day0 & (is.na(date_unregistration) | date_unregistration > window_end)]
  enrollment[, early_unregistration := active_at_day0 & !is.na(date_unregistration) & date_unregistration <= window_end]

  early_vle <- student_vle[
    date >= window_start & date <= window_end,
    .(
      total_clicks = sum(sum_click),
      active_days = data.table::uniqueN(date),
      distinct_resources = data.table::uniqueN(id_site),
      interaction_rows = .N
    ),
    by = keys
  ]

  eligible_features_all <- merge(
    enrollment[eligible_full_window == TRUE], early_vle,
    by = keys, all.x = TRUE, sort = FALSE
  )
  fill_cols <- c("total_clicks", "active_days", "distinct_resources", "interaction_rows")
  for (col in fill_cols) data.table::set(eligible_features_all, which(is.na(eligible_features_all[[col]])), col, 0)

  cohort_counts <- enrollment[, .(
    enrollment_n = .N,
    registration_date_observed = sum(!is.na(date_registration)),
    registered_by_day0 = sum(registered_by_day0),
    active_at_day0 = sum(active_at_day0),
    early_unregistered_days_0_27 = sum(early_unregistration),
    eligible_full_window = sum(eligible_full_window)
  ), by = course_key]

  cohort_early_vle <- student_vle[date >= window_start & date <= window_end, .(
    early_vle_rows = .N,
    early_vle_students = data.table::uniqueN(id_student),
    coverage_days = data.table::uniqueN(date),
    min_activity_day = min(date),
    max_activity_day = max(date),
    early_clicks = sum(sum_click)
  ), by = course_key]

  eligible_zeros <- eligible_features_all[, .(
    eligible_zero_click_n = sum(total_clicks == 0),
    eligible_with_click_n = sum(total_clicks > 0)
  ), by = course_key]

  early_unmatched_resource <- student_vle[
    date >= window_start & date <= window_end
  ][!vle, on = c("code_module", "code_presentation", "id_site"), .N, by = course_key]

  cohort_comparison <- Reduce(
    function(x, y) merge(x, y, by = course_key, all.x = TRUE, sort = FALSE),
    list(courses, cohort_counts, cohort_early_vle, eligible_zeros)
  )
  for (col in setdiff(names(cohort_comparison), c(course_key, "module_presentation_length"))) {
    data.table::set(cohort_comparison, which(is.na(cohort_comparison[[col]])), col, 0)
  }
  cohort_comparison <- merge(
    cohort_comparison,
    early_unmatched_resource,
    by = course_key,
    all.x = TRUE,
    sort = FALSE
  )
  cohort_comparison[is.na(N), N := 0L]
  data.table::setnames(cohort_comparison, "N", "unmatched_early_resource_rows")
  cohort_comparison[, resource_linkage_rate := data.table::fifelse(
    early_vle_rows > 0,
    1 - unmatched_early_resource_rows / early_vle_rows,
    NA_real_
  )]
  cohort_comparison[, eligible_zero_click_pct := data.table::fifelse(
    eligible_full_window > 0,
    eligible_zero_click_n / eligible_full_window,
    NA_real_
  )]
  cohort_comparison[, selection_eligible :=
    module_presentation_length >= (window_end + 1L) &
      coverage_days == (window_end - window_start + 1L) &
      resource_linkage_rate == 1 &
      eligible_full_window >= 500L]

  valid_cohorts <- cohort_comparison[selection_eligible == TRUE]
  assert_true(nrow(valid_cohorts) > 0, "No cohort meets the predeclared size, length, coverage, and linkage requirements.")
  data.table::setorder(valid_cohorts, -eligible_full_window, code_module, code_presentation)
  selected <- valid_cohorts[1]
  selected_module <- selected$code_module
  selected_presentation <- selected$code_presentation
  cohort_comparison[, selected_cohort :=
    code_module == selected_module & code_presentation == selected_presentation]

  analysis <- eligible_features_all[
    code_module == selected_module & code_presentation == selected_presentation
  ]
  assert_true(nrow(analysis) == selected$eligible_full_window, "Selected-cohort feature rows do not match eligible count.")
  assert_true(data.table::uniqueN(analysis, by = keys) == nrow(analysis), "Selected analysis cohort is not unique by enrollment key.")

  original_features <- c("total_clicks", "active_days", "distinct_resources")
  log_features <- paste0("log_", original_features)
  z_features <- paste0("z_", original_features)
  for (j in seq_along(original_features)) {
    analysis[, (log_features[j]) := log1p(get(original_features[j]))]
    feature_mean <- mean(analysis[[log_features[j]]])
    feature_sd <- stats::sd(analysis[[log_features[j]]])
    assert_true(is.finite(feature_sd) && feature_sd > 0, paste("Zero or invalid variance for", original_features[j]))
    analysis[, (z_features[j]) := (get(log_features[j]) - feature_mean) / feature_sd]
  }
  assert_true(!anyNA(analysis[, ..z_features]), "Missing values found in final model inputs.")

  correlation_log <- stats::cor(analysis[, ..log_features], method = "pearson")
  correlation_original <- stats::cor(analysis[, ..original_features], method = "spearman")
  upper_values <- abs(correlation_log[upper.tri(correlation_log)])
  max_abs_log_correlation <- if (length(upper_values)) max(upper_values) else 0
  correlation_condition_number <- kappa(correlation_log)
  assert_true(max_abs_log_correlation < 0.95, "Candidate features are too redundant after log1p transformation (|r| >= 0.95).")
  assert_true(correlation_condition_number < 30, "Candidate feature correlation matrix is ill-conditioned.")

  transform_parameters <- data.table::rbindlist(lapply(seq_along(original_features), function(j) {
    data.table::data.table(
      original_feature = original_features[j],
      transformed_feature = log_features[j],
      model_feature = z_features[j],
      transform = "log1p then z-score",
      log_mean = mean(analysis[[log_features[j]]]),
      log_sd = stats::sd(analysis[[log_features[j]]])
    )
  }))

  selected_enrollment <- enrollment[
    code_module == selected_module & code_presentation == selected_presentation
  ]
  cohort_flow <- data.table::data.table(
    stage = c(
      "All recorded enrollments",
      "Registration date observed",
      "Registered by day 0",
      "Registered and active at day 0",
      "Observed through day 27 (primary cohort)"
    ),
    n = c(
      nrow(selected_enrollment),
      sum(!is.na(selected_enrollment$date_registration)),
      sum(selected_enrollment$registered_by_day0),
      sum(selected_enrollment$active_at_day0),
      sum(selected_enrollment$eligible_full_window)
    )
  )
  cohort_flow[, excluded_from_previous := c(NA_integer_, -diff(n))]

  daily_activity <- student_vle[
    code_module == selected_module &
      code_presentation == selected_presentation &
      date >= window_start & date <= window_end,
    .(
      clicks = sum(sum_click),
      active_students = data.table::uniqueN(id_student),
      resources_accessed = data.table::uniqueN(id_site)
    ),
    by = date
  ]
  complete_days <- data.table::data.table(date = seq.int(window_start, window_end))
  daily_activity <- merge(complete_days, daily_activity, by = "date", all.x = TRUE)
  for (col in c("clicks", "active_students", "resources_accessed")) {
    data.table::set(daily_activity, which(is.na(daily_activity[[col]])), col, 0)
  }

  primary_keys <- analysis[, ..keys]
  vle_14 <- student_vle[
    code_module == selected_module & code_presentation == selected_presentation &
      date >= 0L & date <= 13L,
    .(
      total_clicks = sum(sum_click),
      active_days = data.table::uniqueN(date),
      distinct_resources = data.table::uniqueN(id_site)
    ),
    by = keys
  ]
  analysis_14 <- merge(primary_keys, vle_14, by = keys, all.x = TRUE, sort = FALSE)
  for (col in original_features) data.table::set(analysis_14, which(is.na(analysis_14[[col]])), col, 0)
  for (j in seq_along(original_features)) {
    analysis_14[, (log_features[j]) := log1p(get(original_features[j]))]
    analysis_14[, (z_features[j]) := as.numeric(scale(get(log_features[j])))]
  }

  opportunity <- selected_enrollment[active_at_day0 == TRUE]
  opportunity[, observation_end := data.table::fifelse(
    is.na(date_unregistration),
    window_end,
    pmin(window_end, as.integer(date_unregistration))
  )]
  opportunity[, opportunity_days := observation_end - window_start + 1L]
  assert_true(all(opportunity$opportunity_days >= 1L & opportunity$opportunity_days <= 28L), "Invalid opportunity-day calculation.")
  opportunity_keys <- opportunity[, c(keys, "observation_end"), with = FALSE]
  opportunity_vle_rows <- merge(
    student_vle[
      code_module == selected_module & code_presentation == selected_presentation &
        date >= window_start & date <= window_end
    ],
    opportunity_keys,
    by = keys,
    all = FALSE,
    sort = FALSE
  )[date <= observation_end]
  opportunity_features <- opportunity_vle_rows[, .(
    total_clicks = sum(sum_click),
    active_days = data.table::uniqueN(date),
    distinct_resources = data.table::uniqueN(id_site)
  ), by = keys]
  opportunity <- merge(opportunity, opportunity_features, by = keys, all.x = TRUE, sort = FALSE)
  for (col in original_features) data.table::set(opportunity, which(is.na(opportunity[[col]])), col, 0)
  opportunity[, clicks_per_day := total_clicks / opportunity_days]
  opportunity[, active_day_share := active_days / opportunity_days]
  opportunity[, resources_per_day := distinct_resources / opportunity_days]
  opportunity[, log_clicks_per_day := log1p(clicks_per_day)]
  opportunity[, logit_active_day_share := stats::qlogis((active_days + 0.5) / (opportunity_days + 1))]
  opportunity[, log_resources_per_day := log1p(resources_per_day)]
  opportunity_z <- c("z_clicks_per_day", "z_active_day_share", "z_resources_per_day")
  opportunity[, (opportunity_z[1]) := as.numeric(scale(log_clicks_per_day))]
  opportunity[, (opportunity_z[2]) := as.numeric(scale(logit_active_day_share))]
  opportunity[, (opportunity_z[3]) := as.numeric(scale(log_resources_per_day))]
  assert_true(!anyNA(opportunity[, ..opportunity_z]), "Missing opportunity-adjusted model inputs.")

  outcome_counts <- student_info[, .N, by = final_result][order(final_result)]
  withdrawal_consistency <- enrollment[, .(
    n = .N,
    unregistration_recorded_n = sum(!is.na(date_unregistration)),
    unregistration_recorded_pct = mean(!is.na(date_unregistration))
  ), by = final_result]
  data.table::setnames(withdrawal_consistency, "final_result", "outcome")

  date_ranges <- data.table::data.table(
    variable = c("registration date", "unregistration date", "student VLE date", "assessment due date", "assessment submission date"),
    minimum = c(
      min(registration$date_registration, na.rm = TRUE),
      min(registration$date_unregistration, na.rm = TRUE),
      min(student_vle$date, na.rm = TRUE),
      min(assessments$date, na.rm = TRUE),
      min(student_assessment$date_submitted, na.rm = TRUE)
    ),
    maximum = c(
      max(registration$date_registration, na.rm = TRUE),
      max(registration$date_unregistration, na.rm = TRUE),
      max(student_vle$date, na.rm = TRUE),
      max(assessments$date, na.rm = TRUE),
      max(student_assessment$date_submitted, na.rm = TRUE)
    )
  )

  raw_manifest <- data.table::data.table(
    file = required_files,
    bytes = file.info(raw_paths)$size,
    md5 = unname(tools::md5sum(raw_paths))
  )

  write_csv(table_validation, file.path(results_dir, "raw_table_validation.csv"))
  write_csv(missingness, file.path(results_dir, "raw_missingness.csv"))
  write_csv(join_checks, file.path(results_dir, "join_validation.csv"))
  write_csv(date_ranges, file.path(results_dir, "raw_date_ranges.csv"))
  write_csv(outcome_counts, file.path(results_dir, "raw_outcome_counts.csv"))
  write_csv(withdrawal_consistency, file.path(results_dir, "withdrawal_registration_consistency.csv"))
  write_csv(raw_manifest, file.path(results_dir, "raw_file_manifest.csv"))
  write_csv(cohort_comparison, file.path(results_dir, "cohort_comparison.csv"))
  write_csv(selected, file.path(results_dir, "selected_cohort.csv"))
  write_csv(cohort_flow, file.path(results_dir, "cohort_inclusion_flow.csv"))
  write_csv(daily_activity, file.path(results_dir, "selected_cohort_daily_activity.csv"))
  write_csv(transform_parameters, file.path(results_dir, "feature_transform_parameters.csv"))
  write_csv(data.table::as.data.table(correlation_log, keep.rownames = "feature"), file.path(results_dir, "feature_correlation_log_pearson.csv"))
  write_csv(data.table::as.data.table(correlation_original, keep.rownames = "feature"), file.path(results_dir, "feature_correlation_original_spearman.csv"))

  write_csv(analysis, file.path(processed_dir, "analysis_cohort.csv"))
  saveRDS(analysis, file.path(processed_dir, "analysis_cohort.rds"))
  saveRDS(analysis_14, file.path(processed_dir, "analysis_cohort_14day.rds"))
  saveRDS(opportunity, file.path(processed_dir, "opportunity_sensitivity_cohort.rds"))
  saveRDS(
    list(
      selected_module = selected_module,
      selected_presentation = selected_presentation,
      original_features = original_features,
      log_features = log_features,
      z_features = z_features,
      opportunity_z_features = opportunity_z,
      window = c(window_start, window_end),
      max_abs_log_correlation = max_abs_log_correlation,
      correlation_condition_number = correlation_condition_number
    ),
    file.path(processed_dir, "analysis_spec.rds")
  )

  message(sprintf(
    "[Phase 2] Selected %s-%s: %d eligible enrollments; %d zero-click enrollments.",
    selected_module, selected_presentation, nrow(analysis), sum(analysis$total_clicks == 0)
  ))

  invisible(list(
    analysis = analysis,
    analysis_14 = analysis_14,
    opportunity = opportunity,
    spec = readRDS(file.path(processed_dir, "analysis_spec.rds")),
    cohort_comparison = cohort_comparison,
    cohort_flow = cohort_flow,
    daily_activity = daily_activity
  ))
}

