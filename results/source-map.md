# AMS source map

Audit date: 2026-11-08. All supplied PDFs were text-extracted and inspected; the official project guidelines were also rendered and visually checked page by page. All supplied `.R`/`.r` scripts were inspected. Original files remain unchanged.

## Authority and project criteria

- `AMS project guidelines 2526.pdf` (10 pages): real-data team project; expected structure is problem and relevance, precise research questions, numerical analysis with reliability/robustness, conclusions and real-world implications. Dataset choice must address context, sample size, quality, missingness, methodological suitability, dissemination, and confidentiality. Evaluation has six criteria: data/problem presentation including EDA; research-question clarity; analytical pipeline; appropriateness of AMS methods; compelling visual communication; clear results/conclusions. Official course deliverables include a 15-minute presentation, slides, an approximately 20-page report, and code. Per `PROJECT_SPEC.md`, this Codex task intentionally produces code/results and the defense study guide, not the report or presentation.

## Lecture-to-method map

| Lecture PDF | Main material inspected | Project use |
|---|---|---|
| `00-AMS_Intro.pdf` (10 pages) | Course scope, EDA, bootstrap, multilevel models, robust inference, model-based and robust clustering, exam Q&A | Confirms clustering and robustness are core AMS methods and that method/code defense matters. |
| `01-AMS_Stats_recap.pdf` (65 pages) | Matrix algebra, covariance, eigenvalues, probability, likelihood, MLE, inference | Background for covariance matrices, likelihood, BIC, and diagnostics. |
| `02-AMS_Multivariate_Gaussian.pdf` (20 pages) | Multivariate normal density, Mahalanobis distance, covariance geometry, standardization, likelihood/MLE | Direct basis for Gaussian mixture components and component diagnostics. |
| `03-AMS_Bootstrap.pdf` (35 pages) | Parametric/nonparametric bootstrap, bias/SE, regression bootstrap, confidence intervals | Not a primary method; use only if it answers a specific stability/uncertainty question. |
| `04-AMS_EXTRA_logistic_regression.pdf` (12 pages) | Binary logistic model, odds ratios, likelihood, prediction diagnostics | Not used: outcomes have four levels and the project is exploratory clustering, not supervised prediction. |
| `04-AMS_Mixed_effects_models.pdf` (28 pages) | Grouped/repeated data, fixed/random effects, ML/REML, diagnostics, GLMMs | Not used: observational unit is one enrollment in one selected presentation, not a repeated/multilevel outcome model. |
| `05.01-AMS_Robust_inference.pdf` (35 pages) | Contamination, influence, breakdown, efficiency, M-estimation | Provides robustness vocabulary and cautions. |
| `05.02-AMS_Univ_multilv_Robust.pdf` (37 pages) | Univariate/multivariate robust location/scatter, masking/swamping, MCD, robust distances | Supports outlier diagnostics and the distinction between extreme genuine observations and errors. |
| `05.03-AMS_Robust_regression.pdf` (37 pages) | Regression influence, M/LMS/LTS estimators, trimming, reweighting | Conceptual link to impartial trimming; regression itself is not used. |
| `06-AMS_MBC.pdf` (29 pages) | Gaussian mixtures, covariance parameterizations, EM, MAP allocation, BIC/AIC/ICL | Primary method. Use `mclust`; maximize BIC; inspect covariance model, component count, uncertainty, local optima, and degeneracy. |
| `06-AMS_MBC_LM.pdf` (9 pages) | Mixtures of linear regressions as conditional Gaussian mixtures | Not used: no regression-specific latent-trend question and outcome must not drive clustering. |
| `07-AMS_robust_clustering.pdf` (20 pages) | Outliers, mixture degeneracy, trimmed k-means, TCLUST, eigenvalue-ratio constraint, ECM | Primary robustness method. Use `tclust` with explicit alpha, restriction factor, and multiple starts. |

## Professor R-script map

| Script | Relevant code pattern |
|---|---|
| `01-AMS_Stats_recap.R` | Reproducible seeds; eigen decomposition and likelihood examples. |
| `02-AMS_Multivariate_Gaussian.R` | Multivariate-normal densities, covariance ellipses, MLE covariance, outlier sensitivity. |
| `03-AMS_Bootstrap.R` | Parametric/nonparametric bootstrap and confidence-interval implementations. |
| `04-AMS_MEM.R` | `lme4` fitting and grouped-data diagnostics; not part of this analysis. |
| `05-AMS_Robust_inference.R` | Robust location/scale, MCD, robust Mahalanobis distances, LTS examples. |
| `05b-AMS_Robust_inference.R` | Regression diagnostics and robust LTS; not a project model. |
| `05b - Robust Multilevel Models in R.r` | Robust multilevel alternatives; not a project model. |
| `06-AMS_ModelBasedClustering.r` | Manual EM checks, `mclust::Mclust`, BIC, classification, density, and posterior uncertainty. This is the main implementation template. |
| `06-AMS_MBC_Reg.r` | `flexmix` mixture regression; deliberately not used. |
| `06-exercise solution.r` | Outcome/class labels inspected only after clustering; mirrors the required outcome-separation discipline. |
| `07-AMS_tclust.r` | `tclust`, trimming, restriction factors, `ctlcurves`, and the explicit warning to use multiple random initializations. This is the robust-analysis template. |
| `07_AMS_tclust_solutions.r` | Comparison of restriction factors, component counts, trimming, and post-fit external labels. |

The supplied HTML files are rendered companions to the robust-inference, model-based-clustering, and TCLUST labs; the corresponding source scripts above are the implementation authority.

## Methodological plan fixed before viewing outcomes by cluster

1. Validate all seven OULAD tables and join cardinalities.
2. Compare all 22 module-presentations using enrollment size, start-registration, full 28-day observation eligibility, and VLE linkage/coverage only. Select the largest cohort meeting data-quality requirements; do not use `final_result` in selection.
3. Primary cohort: registered on/before day 0 and not unregistered during days 0-27. Preserve zero-click enrollments by left joining aggregated activity.
4. Candidate features: total clicks, distinct active days, and distinct resources during days 0-27. Inspect redundancy, zeros, skew, and outliers before finalizing. Cluster standardized `log1p` features while retaining original scales for interpretation.
5. Fit Gaussian mixtures over defensible component counts and covariance models; higher `mclust` BIC is preferred. Audit convergence, repeated starts, component size/covariance, posterior uncertainty, and approximate within-component Gaussian adequacy.
6. Only after the partition is fixed, describe `Pass`, `Distinction`, `Fail`, and `Withdrawn` by cluster. Treat this as association, not causation or prediction.
7. Run TCLUST sensitivity analyses using the selected component count, multiple starts, small predeclared trimming levels, and conventional eigenvalue restrictions. Compare only retained common observations for ARI and match labels only for profile comparisons.
8. Include an opportunity-adjusted sensitivity cohort for early withdrawals; do not silently treat missing observation time as zero activity.

