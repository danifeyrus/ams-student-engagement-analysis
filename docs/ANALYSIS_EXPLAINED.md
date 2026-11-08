# Analysis Explained

This document explains the project in plain language while preserving the statistical boundaries of the verified analysis. It is a methodological guide for collaborators, not a course report.

## 1. What the project asks

The project studies whether students show distinguishable patterns of early online engagement, whether recorded course outcomes differ across those patterns, and whether the patterns survive reasonable changes in method and design. The analysis is exploratory: it describes structure in the data and does not predict outcomes or estimate causal effects.

## 2. What OULAD contains

The Open University Learning Analytics Dataset links course presentations, students, registrations, assessments, and virtual-learning-environment events. The pipeline uses all seven official CSV tables and validates their real row counts, keys, dates, and joins. A student can appear in more than one presentation, so the unit used here is an enrollment in one selected module-presentation.

Raw VLE events are not deduplicated away. Repeated enrollment-resource-day rows represent additional recorded clicks and are summed. The official archive, checksum, attribution, and table validation are recorded in `results/`.

## 3. How the analytical cohort was chosen

The cohort was chosen without looking at `final_result`. Among presentations with complete days 0–27 VLE coverage and valid resource links, the largest eligible presentation was `CCC-2014J`.

The flow is:

- 2,498 recorded enrollments;
- 2,495 with an observed registration date;
- 2,482 registered by day 0;
- 2,271 still registered at day 0;
- 2,011 still observable through day 27.

The primary rule excludes 260 enrollments that unregister during days 0–27. This makes observation time comparable, but it also removes an educationally important group. Therefore an alternative 2,271-enrollment cohort includes those students with opportunity adjustment. Zero activity is not treated as missing: all 38 eligible zero-click enrollments remain in the primary cohort.

## 4. What the three variables mean

`total_clicks` is the sum of recorded VLE clicks during course days 0–27. `active_days` counts distinct days with at least one interaction. `distinct_resources` counts different VLE resources accessed.

These variables represent intensity, regularity, and breadth. They are interpretable but correlated; they are not three independent dimensions of learning. A click is a platform interaction, not proof of attention, comprehension, or learning.

## 5. Why transform and standardize

The original counts are right-skewed, especially total clicks: its mean is 289.4, median 203, maximum 3,247, and sample skewness 3.63. The pipeline applies `log1p(x) = log(1 + x)`, which is defined at zero and reduces the leverage of very large counts.

Each transformed variable is then z-standardized. Standardization prevents a high-variance variable from dominating merely because of its scale. Original counts are retained for profile summaries so the results remain understandable.

The transformation helps but does not create exact normality. It also leaves a shared point mass for the 38 zero-activity enrollments. This is one reason Gaussian components must be viewed as approximations.

## 6. What the EDA shows

In the primary cohort:

- total clicks: median 203, IQR 110–357.5;
- active days: median 9, IQR 6–14;
- distinct resources: median 17, IQR 11–24.

The transformed variables remain strongly related; their maximum pairwise correlation is 0.872. Principal component 1 explains 89.6% of transformed-feature variance. Most of the visible structure is therefore one broad low-to-high engagement gradient, not three orthogonal behavioral axes.

## 7. How Gaussian mixture clustering works

A Gaussian mixture represents the observed distribution as a weighted sum of multivariate normal components. Each component has a mean vector and a covariance shape. The EM algorithm estimates the component parameters and posterior membership probabilities.

Every enrollment receives both a hard label—the component with the largest posterior probability—and a probability vector. The probability vector is essential: two students can receive different labels even when both lie near a fuzzy boundary.

The project searches 1–9 components and the covariance families implemented by `mclust`. To reduce dependence on one hierarchical initialization, the BIC search uses seven outcome-blind initializations. The selected specification is then refitted repeatedly, retaining the best recorded log-likelihood.

## 8. Why BIC selected G=4 VVE

BIC balances maximized likelihood against model complexity; in `mclust`, the larger BIC is preferred. The best search specification was four components with VVE covariance. VVE allows component volumes and shapes to vary while constraining orientation to be equal.

The selected fit has BIC -10,420.719 and log-likelihood -5,096.264. The BIC gap to the second-ranked specification is 12.328. Component sizes are 91, 493, 1,145, and 282; there is no tiny component or near-singular fitted covariance.

BIC answers “which candidate density model is best by this penalized likelihood criterion?” It does not prove that four natural student types exist. Entropy-penalized ICL, which rewards clearer classification, instead prefers G=2 EVE.

## 9. What the four profiles describe

Profiles are ordered by original-scale engagement medians:

| Profile | n | Median clicks | Median active days | Median resources |
|---|---:|---:|---:|---:|
| P1 | 91 | 1 | 1 | 1 |
| P2 | 493 | 86 | 4 | 9 |
| P3 | 1,145 | 229 | 10 | 19 |
| P4 | 282 | 651.5 | 19 | 24 |

These are useful descriptive regions along the engagement gradient. P1 contains all 38 zero-click enrollments, but also some very-low nonzero activity. P3 is broad and contains 56.9% of the cohort.

## 10. Why classification uncertainty matters

Mean posterior uncertainty is 0.217, and 988 of 2,011 hard assignments have uncertainty above 0.20. Mean silhouette width is only 0.221, while 22.8% of cases have a negative silhouette.

These diagnostics say that many students lie near overlapping component boundaries. A hard profile label is therefore a summary, not an observed trait. Posterior probabilities should be retained whenever individual classification matters. This is also why the project does not assign personality-style names to the profiles.

## 11. How outcomes were compared

`final_result` was excluded from cohort selection, features, BIC selection, and clustering. It was joined only after the four-component partition was fixed.

The outcome-by-profile chi-squared statistic is 189.830 with 9 degrees of freedom, p = 4.47 × 10^-36, and Cramér's V = 0.177. Expected counts are adequate. Withdrawal falls from 50.5% in P1 to 18.4% in P4, while Pass and Distinction proportions rise.

This is a modest descriptive association in a restricted observational cohort. It does not establish that increasing clicks would cause success, because prior ability, course circumstances, motivation, and other confounders are not controlled.

## 12. What TCLUST and ARI contribute

TCLUST is a robust clustering method that trims a prespecified fraction of observations and restricts covariance eigenvalue ratios. The primary configuration uses four groups, `alpha=0.05`, restriction factor `c=20`, and 1,000 starts. It trims 101 observations and compares the remaining 1,910 with the Gaussian labels.

The adjusted Rand index (ARI) is 0.238981. It was independently recomputed from the exact enrollment cross-tab. TCLUST label 0 means “trimmed,” so those observations are excluded rather than treated as an extra cluster.

The low ARI is scientifically informative. TCLUST creates a very large middle group and small boundary/extreme groups, whereas the likelihood-based Gaussian mixture subdivides the continuous intensity distribution differently. Across reasonable TCLUST settings, retained-case ARI ranges from 0.117 to 0.283. The methods agree on a broad intensity ordering but not on stable hard boundaries.

## 13. What the sensitivity analyses say

The analyses were defined to challenge the primary result, not to maximize agreement:

- a 14-day window fixes G=4, selects EEV, and has ARI 0.175 versus the primary partition;
- the opportunity-adjusted 2,271-enrollment cohort fixes G=4, selects VEV, and has overlap ARI 0.082;
- ICL prefers two components rather than four;
- leave-one-feature-out, alternative transformation, PC1-only, and covariance checks show specification dependence;
- in 25 outcome-blind 80% subsamples, the exact G=4 VVE specification is reselected only 24% of the time;
- conditional on a successful fixed G=4 VVE fit, median subsample ARI is 0.772, but joint model-reselection median ARI is 0.256.

The distinction between conditional and unconditional stability matters. The four-component geometry can recur when imposed, but data-driven selection of the entire model is unstable.

## 14. Main weaknesses and defensible claims

A demanding reviewer can reasonably criticize the one-presentation scope, observational design, selection created by excluding early unregistrations, correlated intensity proxies, zero point mass, approximate Gaussian assumptions, initialization failures, posterior ambiguity, weak hard separation, ICL disagreement, low cross-method ARI, and low model-selection stability.

Those weaknesses are recorded rather than hidden. The defensible claims are:

1. Early engagement in this cohort is strongly ordered along a continuous intensity gradient.
2. A four-component VVE mixture is the best density approximation in the prespecified BIC search and provides readable low-to-high descriptive profiles.
3. Recorded outcomes differ across those profiles, with a modest association.
4. Exact boundaries and the number of hard groups are not robust enough to support fixed natural learner types.

## 15. Reproducing and reusing the work

Restore packages with `renv::restore()`, then run `Rscript main.R` or the Windows launcher in `scripts/run-r.ps1`. The pipeline verifies the archive, schemas, joins, model invariants, numerical agreement, figures, package versions, and MD5 manifest.

For a fast inspection without refitting, run `EXAM_DEMO.R` or `main.R --demo`. For writing, use only assets indexed in `publication/ASSETS_INDEX.md`; source tables remain in `results/`. Do not copy cached numbers into code or hand-edit generated tables. If a method changes, rerun the full pipeline and update the interpretation at the same time.
