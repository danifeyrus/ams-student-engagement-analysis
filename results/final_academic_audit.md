# Internal review of the analysis

This review compares the completed analysis with the six assessment criteria in the AMS project guidelines and checks whether the conclusions follow from the numerical results.

## Assessment criteria

| Criterion | Assessment | Evidence and scope |
|---|---|---|
| Data, problem, and EDA | Meets the criterion | OULAD provenance and SHA-256 are recorded; all seven tables and joins are checked; cohort construction, zeros, original distributions, and transformations are documented |
| Research questions | Meets the criterion | The three questions separately address profile structure, recorded outcomes, and robustness |
| Analytical pipeline | Meets the criterion | Cohort and model selection are outcome-blind; seeds, package versions, warnings, generated outputs, and numerical checks are recorded |
| Choice of AMS methods | Meets the criterion | Gaussian mixtures, covariance models, BIC, ICL, posterior probabilities, PCA, silhouette, TCLUST, ARI, and sensitivity analyses are used for questions they can answer |
| Visual communication | Meets the criterion | The 20-figure set covers cohort construction, EDA, model selection, profiles, outcomes, uncertainty, and robustness |
| Results and conclusions | Meets the criterion with limitations | Estimates are consistent across code and documentation; conclusions remain descriptive and explicitly acknowledge instability |

All 19 required checks in `results/verification_summary.csv` pass. Five diagnostic checks remain marked REVIEW because they describe substantive limitations rather than execution failures.

## Research design

The cohort is selected without reference to course outcomes. Requiring a complete 28-day observation period makes exposure comparable and preserves zero activity through left joins. It also excludes 260 early unregistrations, so the primary results apply to students observed through day 27 rather than to every registered student. The opportunity-adjusted sensitivity analysis addresses this choice and produces overlap ARI 0.082.

Total clicks, active days, and distinct resources have clear behavioral interpretations. Applying `log1p` to nonnegative counts and then standardizing is appropriate for covariance-based clustering. The measures are nevertheless strongly related: PC1 explains 89.6% of their transformed variance, and the largest transformed correlation is 0.872. The dominant empirical structure is therefore an engagement-intensity gradient.

## Gaussian mixture

The model search evaluates seven initializations for each candidate combination of component count and covariance structure. BIC selects G=4 VVE. The retained fit has BIC -10,420.719, log-likelihood -5,096.264, minimum component size 91, and minimum covariance eigenvalue 0.0177. These values do not indicate a tiny or degenerate selected component.

Classification is much less certain than density fit. Mean posterior uncertainty is 0.217, 988 assignments exceed 0.20, normalized posterior entropy is 0.363, mean silhouette is 0.221, and 22.8% of silhouettes are negative. ICL prefers G=2 EVE. In 25 case subsamples, the exact G=4 VVE specification is selected in 24%, with median model-reselected partition ARI 0.256. Four of 21 selected-specification restarts return `NULL`.

The four components are therefore interpretable density regions, but the evidence does not support four sharply separated or invariant learner types.

## TCLUST and ARI

The primary TCLUST fit trims 101 observations. ARI is calculated on the remaining 1,910 enrollment keys, each of which has both a nonzero TCLUST label and a Gaussian-mixture label. A manual calculation from the same contingency table matches the package value: 0.238981437.

TCLUST label 0 is treated as trimming status, not as an additional cluster. The low ARI is therefore not a consequence of mismatched keys or an incorrect denominator. TCLUST forms one 1,717-case middle group with small zero, very-low, and very-high groups, while the Gaussian mixture divides the continuous intensity distribution into overlapping density components. Across the prespecified TCLUST settings, retained-case ARI remains between 0.117 and 0.283.

## Outcomes

Course outcomes are joined after clustering. The profile-by-outcome table contains all 2,011 observations, and no expected count is below five. The association is χ²(9)=189.830, p=4.47×10^-36, with Cramér's V=0.177.

The pattern is consistent with more favorable outcomes at higher early-engagement levels, but the effect size is modest and the design is observational. The analysis neither identifies a causal effect nor evaluates predictive performance.

## Corrections made during review

- The original single-initialization mixture search was replaced by a multi-initialization search. This changed the selected model from G=3 VVV to G=4 VVE.
- ARI was recalculated independently on the exact set of TCLUST-retained enrollment keys.
- Local runtimes, raw data, course materials, machine-specific settings, logs, and private study notes were excluded from version control.
- A clean clone restored the recorded packages, downloaded OULAD independently, completed the full pipeline, and reproduced the key numerical outputs.
- Line endings are controlled through `.gitattributes` so text files behave consistently across Windows checkouts.

No covariance structure, trimming level, observation window, or alternative specification was selected to improve ARI.

## Remaining limitations

The analysis covers one module-presentation and three correlated activity proxies. The primary cohort excludes early unregistrations. The transformed data retain a zero point mass and are only approximately Gaussian within components. Many posterior assignments are ambiguous, BIC and ICL prefer different partitions, and the selected model is sensitive to the sample and specification.

These limitations affect the interpretation of the clusters, not the reproducibility of the calculations. The analysis meets the technical and methodological requirements of the project provided that the report and presentation describe the profiles as model-dependent summaries and keep the outcome comparison noncausal.
