acquire_oulad <- function(raw_root = file.path("data", "raw")) {
  archive_url <- "https://archive.ics.uci.edu/static/public/349/open%2Buniversity%2Blearning%2Banalytics%2Bdataset.zip"
  expected_sha256 <- "f2ed1902616c1fe8d2824d872c0b7d2d72be435bf0124d077044fe4be2c6d3e4"
  archive_path <- file.path(raw_root, "oulad_uci_349.zip")
  extract_dir <- file.path(raw_root, "oulad")
  required_files <- c(
    "courses.csv", "assessments.csv", "vle.csv", "studentInfo.csv",
    "studentRegistration.csv", "studentAssessment.csv", "studentVle.csv", "OULAD.names"
  )
  required_paths <- file.path(extract_dir, required_files)
  dir.create(raw_root, recursive = TRUE, showWarnings = FALSE)

  if (!all(file.exists(required_paths))) {
    if (!file.exists(archive_path)) {
      message("[Phase 1] Downloading the verified official OULAD archive from UCI...")
      utils::download.file(archive_url, archive_path, mode = "wb", method = "libcurl", quiet = FALSE)
    }
    observed_sha256 <- tolower(unname(tools::sha256sum(archive_path)))
    assert_true(
      identical(observed_sha256, expected_sha256),
      sprintf("OULAD archive SHA-256 mismatch. Expected %s; found %s.", expected_sha256, observed_sha256)
    )
    dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)
    utils::unzip(archive_path, exdir = extract_dir, overwrite = FALSE)
  }

  assert_true(all(file.exists(required_paths)), "OULAD extraction is incomplete.")
  if (file.exists(archive_path)) {
    observed_sha256 <- tolower(unname(tools::sha256sum(archive_path)))
    assert_true(identical(observed_sha256, expected_sha256), "Existing OULAD archive failed SHA-256 verification.")
  }
  invisible(required_paths)
}

