# Publication Assets Index

All assets below are generated or copied by `src/08_publication_assets.R`. Use them as inputs to future writing or slides; do not edit them manually. “Report” and “slides” are reuse suggestions, not deliverables created by this repository.

## Figures

| File | Recommended title | What it shows | Best use | Key message / caption guidance | Limitation to state |
|---|---|---|---|---|---|
| `figures/02_cohort_inclusion_flow.png` | Analytical cohort inclusion | Enrollment counts through each eligibility step | Report, slides | 2,011 of 2,498 recorded enrollments form the comparable 28-day cohort | 260 early unregistrations are excluded |
| `figures/04_feature_distributions_original.png` | Early engagement distributions | Original-scale clicks, active days, and resource breadth | Report | Counts are skewed and include genuine zeros, motivating `log1p` | Plots are descriptive and extreme values are not automatically errors |
| `figures/06_feature_correlation.png` | Dependence among transformed features | Pairwise relationships and correlations | Report | Three features are strongly related; PC1 later confirms one dominant intensity axis | Correlation does not make the variables identical |
| `figures/08_mclust_bic_grid.png` | Gaussian-mixture model selection | BIC over component counts and covariance structures | Report, slides | The prespecified search selects G=4 VVE; the gap to second place is 12.328 | BIC selects a density model, not necessarily natural clusters |
| `figures/09_mclust_profiles.png` | Four engagement profiles | Original-scale profile summaries | Report, slides | Medians increase monotonically from very low to very high activity | P3 is broad and boundaries are probabilistic |
| `figures/10_mclust_uncertainty.png` | Posterior classification uncertainty | Distribution and location of uncertain assignments | Report, slides | Mean uncertainty is 0.217 and 988 assignments exceed 0.20 | Hard labels conceal posterior overlap |
| `figures/12_outcomes_by_profile.png` | Recorded outcomes by profile | Outcome proportions after clustering | Report, slides | Withdrawal decreases and favorable outcomes increase across profile order | Association is descriptive, not causal or predictive |
| `figures/14_tclust_configuration_sensitivity.png` | Robust-clustering sensitivity | ARI and cluster behavior across trimming/restriction choices | Report | Retained-case ARI remains low (0.117–0.283) across defensible settings | Settings change both trimming and cluster geometry |
| `figures/17_method_disagreement_crosstab.png` | Where clustering methods disagree | Exact Gaussian-versus-TCLUST cross-tab on retained cases | Report, slides | TCLUST pools a broad middle while the mixture subdivides the gradient | TCLUST-trimmed cases are absent by design |
| `figures/19_mclust_subsample_stability.png` | Case-subsample model stability | Conditional and model-reselected stability over 25 samples | Report, slides | Fixed-model stability is stronger than full selection stability; exact model reselected 24% | Only 25 repetitions; fixed-model fits succeed in 16 |

## Tables

| File | Recommended title | Contents and use | Key result / caution |
|---|---|---|---|
| `tables/01_cohort_summary.csv` | Selected cohort | One-row handoff for dataset and methods sections | Primary n=2,011; 38 zero-click enrollments |
| `tables/02_cohort_inclusion_flow.csv` | Inclusion flow | Exact stage denominators for report methods | Do not merge early unregistrations with zero activity |
| `tables/03_variable_dictionary.csv` | Variable definitions | Source, definition, and transformation | All three variables use days 0–27 and `log1p` + z scaling |
| `tables/04_descriptive_statistics.csv` | Engagement descriptives | Original-scale summaries | Total clicks are highly right-skewed |
| `tables/05_selected_model.csv` | Selected mixture specification | Model, fit, restart, and uncertainty metadata | G=4 VVE; four failed restarts; substantial ambiguity |
| `tables/06_bic_top_models.csv` | Top BIC candidates | Ranked candidate models | Use to show selection was not a single fit |
| `tables/07_profile_summary.csv` | Profile sizes and medians | Core RQ1 numerical table | Report medians and uncertainty, not labels alone |
| `tables/08_outcomes_by_profile.csv` | Outcome proportions | Core RQ2 descriptive table | Denominators differ by profile; values are proportions |
| `tables/09_outcome_association.csv` | Outcome association statistics | χ², p, Cramér's V, expected-count audit | Effect size 0.177; avoid causal language |
| `tables/10_tclust_robustness.csv` | TCLUST sensitivity | Trimming, restriction, sizes, and retained-case ARI | Low agreement persists; clusters can be unbalanced |
| `tables/11_key_diagnostics.csv` | Independent diagnostic summary | PCA, silhouette, entropy, ICL, ARI, subsampling | Best compact table for limitations |
| `tables/12_specification_sensitivity.csv` | Window and cohort sensitivity | Fourteen-day and opportunity-adjusted comparisons | Overlap ARIs 0.175 and 0.082 |
| `tables/13_method_disagreement_crosstab.csv` | Method cross-tabulation | Exact retained-case contingency table | This is the source for manual ARI verification |

## Selection guidance

For a short oral presentation, the minimum honest set is Figures 08, 09, 10, 12, and 17 or 19. For a written analysis, add Figures 02, 04, 06, and 14 plus Tables 01, 03, 05, 07, 09, and 11. Every use of the profile or outcome figures should be paired with at least one uncertainty or stability asset.
