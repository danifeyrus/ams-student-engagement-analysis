source("renv/activate.R")

# Keep VS Code integration packages separate from the reproducible analysis
# library. This path is added only to an interactive VS Code R terminal.
if (interactive() && identical(Sys.getenv("TERM_PROGRAM"), "vscode")) {
  vscode_library <- file.path(getwd(), ".vscode", "R-library")
  if (dir.exists(vscode_library)) {
    .libPaths(c(vscode_library, .libPaths()))
  }
  rm(vscode_library)
}
