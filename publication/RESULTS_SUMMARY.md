# Verified Results Reference

This is a compact handoff of verified findings for collaborators. It is not a report and does not replace the executable analysis.

## Scope and cohort

The outcome-blind eligibility rule selected OULAD module-presentation `CCC-2014J`. The primary analytical sample contains 2,011 enrollments registered by day 0 and observed through day 27, including 38 zero-click enrollments. It excludes 260 enrollments that unregister during the observation window.

Clustering uses standardized `log1p` total clicks, active days, and distinct resources over days 0–27. Outcomes are added only after clustering.

## RQ1 — What early engagement profiles are supported?

**Method.** Gaussian model-based clustering over G=1–9 and all available `mclust` covariance structures, with seven outcome-blind BIC initializations and repeated selected-model fits.

**Verified finding.** BIC selects G=4 VVE (BIC -10,420.719; log-likelihood -5,096.264). Ordered profile medians for clicks/active days/resources are:

- P1, n=91: 1 / 1 / 1;
- P2, n=493: 86 / 4 / 9;
- P3, n=1,145: 229 / 10 / 19;
- P4, n=282: 651.5 / 19 / 24.

**Interpretation.** The components provide a readable segmentation from very low to very high early activity. PC1 explains 89.6% of transformed-feature variance, so the primary empirical structure is a mostly continuous engagement-intensity gradient.

**Limitations.** Mean posterior uncertainty is 0.217; 988 assignments exceed 0.20. Mean silhouette is 0.221 and 22.8% of silhouettes are negative. ICL prefers G=2 EVE. The four labels are useful density regions, not proven natural learner types.

**Legitimate conclusion.** Four VVE components are defensible as the best candidate density approximation under BIC, but individual hard labels and the exact number of groups are uncertain.

## RQ2 — How do recorded outcomes differ across profiles?

**Method.** Post-clustering cross-tabulation of Distinction, Pass, Fail, and Withdrawn, followed by a chi-squared test and Cramér's V.

**Verified finding.** χ²(9)=189.830, p=4.47×10^-36, Cramér's V=0.177; minimum expected count=13.80. Withdrawal proportions are 50.5%, 41.6%, 25.9%, and 18.4% from P1 to P4. Pass and Distinction proportions rise across the same ordering.

**Interpretation.** Recorded outcomes differ systematically across the descriptive engagement regions, but the association is modest in magnitude.

**Limitations.** This is observational, limited to one restricted cohort, and does not control confounding. The primary cohort excludes early unregistrations. Clicks are behavioral traces, not a treatment.

**Legitimate conclusion.** Higher early-engagement profiles are associated with more favorable recorded outcomes in this cohort; no causal or predictive claim is warranted.

## RQ3 — Are the profiles robust?

**Method.** TCLUST with fixed G=4, prespecified trimming/restriction settings, 1,000 starts for the primary configuration, exact retained-case ARI verification, alternative windows and cohort rules, alternative feature specifications, ICL, silhouette, entropy, and 25 case-subsample repetitions.

**Verified finding.** Primary TCLUST (`alpha=0.05`, `c=20`) trims 101 observations and has ARI 0.238981 on exactly 1,910 retained enrollments. Across reasonable TCLUST settings, ARI ranges 0.117–0.283. Fourteen-day and opportunity-adjusted overlap ARIs are 0.175 and 0.082. The exact G=4 VVE specification is reselected in 24% of 80% subsamples; median model-reselected partition ARI is 0.256.

**Interpretation.** Different defensible algorithms cut the dominant intensity gradient at different points. Broad low/middle/high ordering is present, but hard boundaries are method-dependent.

**Limitations.** TCLUST solutions can be initialization-sensitive and unbalanced. Four of 21 selected-mixture restart fits returned `NULL`. Sensitivity results do not identify a unique alternative partition.

**Legitimate conclusion.** Robustness evidence does not support stable natural learner types. Instability is a result, not a technical failure, and must remain central to the interpretation.

## Readiness statement

Technical correctness is strong: all 19 required validation checks pass, raw data and joins are verified, ARI is independently reproduced, and the full output set is auditable. Statistical validity is adequate for an exploratory AMS project if conclusions remain conditional, descriptive, and explicit about instability. The principal unresolved weakness is substantive rather than computational: profile count and membership depend materially on model, sample, observation rule, and classification criterion.
