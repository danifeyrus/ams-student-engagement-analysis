# Final academic and statistical audit

Audit scope: official six AMS evaluation criteria, research design, executable pipeline, statistical validity, communication assets, and team handoff. The numerical evidence below comes from the verified result files rather than manual recalculation in prose.

## Overall judgement

- **Technical correctness: PASS.** Data provenance, checksums, schemas, joins, cohort denominators, feature construction, outcome separation, model-search bookkeeping, retained-case ARI, numerical invariants, and generated artifacts are explicitly checked. All 19 required validation checks pass.
- **Statistical validity: PASS WITH MATERIAL QUALIFICATIONS.** The analysis is suitable as an exploratory multivariate clustering study. It is not valid to present the four components as uniquely stable natural student types. Five diagnostic checks deliberately remain REVIEW.
- **Academic readiness: READY FOR A CAUTIOUS ORAL EXAMINATION.** The strongest answer is that model-based profiles are interpretable density summaries and their instability is a substantive result.

## Audit against the six AMS criteria

| Criterion | Status | Evidence | Remaining qualification |
|---|---|---|---|
| 1. Data/problem presentation and EDA | PASS | Official OULAD provenance and SHA-256; seven tables validated; cohort flow and zero retention documented; original and transformed distributions plotted | One presentation and three engagement proxies limit generalization |
| 2. Clear research questions | PASS | Three questions separately address profile structure, descriptive outcome association, and robustness | RQ1 must be answered conditionally because cluster boundaries are unstable |
| 3. Analytical pipeline | PASS | Outcome-blind cohort and clustering; reproducible seed; `renv`; multiple starts; full validation and output manifest | Full refit is computationally substantial |
| 4. Appropriate AMS methods | PASS | Gaussian mixtures, covariance models, BIC/ICL, posterior uncertainty, PCA/silhouette, TCLUST, ARI, and sensitivity analyses match course methods | Gaussian assumptions are approximate and features are strongly redundant |
| 5. Compelling visual communication | PASS | Twenty checked figures plus ten curated publication figures, with uncertainty and negative robustness shown alongside headline profiles | Visuals must not be selected without the limitation panels |
| 6. Clear results and conclusions | PASS WITH QUALIFICATION | Exact estimates, effect size, profile medians, uncertainty, ARI, and sensitivity findings are consistent across code and documentation | Avoid causal, predictive, and ontological language |

## Research-design audit

The cohort-selection rule does not use outcomes. A fixed 28-day window creates comparable exposure and retains zero activity through left joins. Excluding 260 early unregistrations avoids treating unavailable days as inactivity, but changes the target population. The opportunity-adjusted sensitivity explicitly tests this choice and produces low overlap ARI (0.082), so selection dependence is acknowledged rather than hidden.

The three variables are substantively interpretable measures of intensity, regularity, and breadth. `log1p` is appropriate for nonnegative skewed counts with zeros, and z-standardization is appropriate before covariance-based clustering. Nevertheless, PC1 explains 89.6% and the maximum transformed correlation is 0.872; the variables mostly encode a single intensity gradient. This is the main explanation for method-dependent cut points.

## Gaussian-mixture audit

The corrected outcome-blind search uses seven initializations for each candidate G/covariance cell and selects G=4 VVE by BIC. The best repeated fit has BIC -10,420.719, log-likelihood -5,096.264, minimum component size 91, and minimum covariance eigenvalue 0.0177. There is no evidence of a tiny or degenerate selected component.

The solution is meaningful as a density approximation but not as a sharp taxonomy. Mean posterior uncertainty is 0.217; 988 assignments exceed 0.20; normalized posterior entropy is 0.363; mean silhouette is 0.221; 22.8% of silhouettes are negative. ICL prefers G=2 EVE. In 25 case subsamples, the exact G/model is selected in 24%, with median model-reselected partition ARI 0.256. Four of 21 selected-specification restarts returned `NULL`, and successful fits are not assignment-identical.

## Robust-clustering and ARI audit

ARI was computed on comparable observations. The primary TCLUST fit labels 101 enrollments as 0 (trimmed); those rows are excluded, leaving 1,910 enrollment keys with both nonzero TCLUST labels and Gaussian labels. A manual contingency-table calculation matches the package ARI to numerical tolerance: 0.238981437. Treating label 0 as an ordinary cluster would answer a different question and is not used.

TCLUST does not merely relabel the Gaussian components. It creates one 1,717-case broad middle group plus small zero, very-low, and very-high groups, whereas the mixture partitions the continuous intensity distribution into overlapping Gaussian regions. With different defensible trimming and restriction settings, retained-case ARI remains 0.117–0.283. The disagreement is therefore explained by objective functions, trimming, covariance restrictions, and weak boundary separation—not by a coding or key-alignment error.

## Outcome audit

Outcomes are joined only after clustering. The profile-outcome table totals 2,011, all chi-squared expected counts exceed five, and χ²(9)=189.830 with p=4.47×10^-36 and Cramér's V=0.177. The outcome pattern is coherent, but the effect is modest and observational. It supports a descriptive association only.

## Issues found and disposition

1. **Initialization dependence in the earlier mixture search — corrected previously.** Multi-initialization BIC selection replaced the original G=3 VVV result with G=4 VVE.
2. **Potential ARI miscomparison — ruled out.** Keys and trimmed cases are handled correctly and independently verified.
3. **Machine-specific VS Code configuration in a public repository — corrected.** Local settings are ignored; a portable example, tasks, and Windows launcher are supplied.
4. **Repository hygiene — corrected.** Raw data, local runtimes, private course material, defense notes, logs, and machine-only evidence are excluded from publication.
5. **Unused helper code — corrected.** One unreferenced checksum helper was removed; statistical logic was not simplified away.
6. **Pressure to improve agreement — rejected.** No model or tuning value was selected to increase ARI. Low agreement and unstable specifications remain explicit findings.

## Unresolved weaknesses

- results concern a single module-presentation;
- early-unregistration exclusion changes the target population;
- engagement traces are imperfect constructs;
- features are highly collinear and mostly one-dimensional;
- transformed components are only approximately Gaussian and include a zero point mass;
- posterior overlap makes many individual labels unreliable;
- the preferred component count depends on BIC versus ICL;
- hard partitions are sensitive to algorithm, window, cohort, features, and case sampling;
- the number of subsample repetitions is adequate for diagnosis but not a high-precision stability estimate;
- no causal conclusion about engagement and achievement is identified.

## Final defensible conclusion

The project convincingly answers the three research questions only with qualified language: a four-component VVE mixture is the best audited BIC density approximation; outcomes differ descriptively across its low-to-high engagement regions; and extensive robustness checks show that exact group count and membership are unstable. The statistically honest result is the combination of interpretable density structure and weak taxonomic validity.
