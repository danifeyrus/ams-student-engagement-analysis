# Results summary

The analysis considers three related questions: whether early VLE activity can be represented by interpretable engagement profiles, whether recorded outcomes differ across those profiles, and how sensitive the profiles are to reasonable changes in method and design.

The primary sample is the `CCC-2014J` module-presentation. It contains 2,011 enrollments registered by day 0 and observed through day 27, including 38 students with no recorded clicks in that period. Clustering is based on standardized `log1p` total clicks, active days, and distinct resources. Course outcomes are introduced only after the clustering solution has been estimated.

## Engagement profiles

The Gaussian-mixture search covers one to nine components and the covariance structures available in `mclust`. Seven outcome-blind initializations are used for each candidate. BIC selects a four-component VVE model with BIC -10,420.719 and log-likelihood -5,096.264.

The components form an ordered activity gradient:

| Profile | n | Median clicks | Median active days | Median resources |
|---|---:|---:|---:|---:|
| P1 | 91 | 1 | 1 | 1 |
| P2 | 493 | 86 | 4 | 9 |
| P3 | 1,145 | 229 | 10 | 19 |
| P4 | 282 | 651.5 | 19 | 24 |

This four-component solution is useful for describing the fitted density, but its boundaries are not sharp. Mean posterior uncertainty is 0.217, 988 assignments exceed 0.20 uncertainty, and the mean silhouette is 0.221. PC1 explains 89.6% of the transformed-feature variance, indicating that the three measures largely follow one engagement-intensity direction. ICL, which penalizes classification uncertainty more strongly than BIC, prefers two components.

## Recorded outcomes

Outcome distributions differ across the four profiles: χ²(9)=189.830, p=4.47×10^-36, with Cramér's V=0.177. The minimum expected cell count is 13.80, so the chi-squared approximation is adequate.

Withdrawal decreases from 50.5% in P1 to 18.4% in P4. Pass and Distinction become more common as early engagement increases. The effect size is modest, and the comparison is observational. It does not establish that additional clicks cause better outcomes and is not intended as a prediction model.

## Robustness and sensitivity

The primary TCLUST specification fixes four groups, trims 5% of observations, uses an eigenvalue-ratio restriction of 20, and searches 1,000 starts. It trims 101 observations. On the remaining 1,910 enrollments, its agreement with the Gaussian-mixture partition is ARI 0.238981.

The low agreement is not caused by a key-matching error. ARI was also calculated manually from the retained-case contingency table and matches the package value. TCLUST places most students in one broad middle group, whereas the Gaussian mixture divides the same continuous intensity distribution into several overlapping density components.

The conclusion is similar across the additional checks:

- retained-case TCLUST ARI ranges from 0.117 to 0.283 across the prespecified trimming and restriction settings;
- a 14-day observation window gives overlap ARI 0.175;
- including early withdrawals with opportunity adjustment gives overlap ARI 0.082;
- the exact G=4 VVE specification is selected in 24% of the 80% case subsamples;
- median partition ARI after repeating model selection is 0.256.

Taken together, the results support an interpretable description of early engagement intensity, but not a claim that the cohort contains four fixed or naturally separated student types.
