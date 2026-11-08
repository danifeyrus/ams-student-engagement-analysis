# Methodology and interpretation

## Research design

The project examines early online engagement in the Open University Learning Analytics Dataset (OULAD). It asks whether the first 28 course days contain interpretable engagement profiles, whether recorded outcomes differ across those profiles, and how sensitive the profiles are to changes in method and sample definition.

The analysis is exploratory. Course outcomes are not used to select the cohort, construct features, choose the number of components, or estimate the clusters. They are introduced only after the clustering solution has been fixed.

## Data and unit of analysis

OULAD links module-presentations, student registrations, assessments, and virtual-learning-environment activity. The pipeline validates the seven official CSV tables, including their row counts, keys, dates, and join cardinalities.

The observational unit is an enrollment in a module-presentation. A student may therefore occur more than once in the complete dataset. Repeated `studentVle` rows at the same enrollment-resource-day grain are retained because they represent recorded click totals rather than accidental duplicate records.

## Cohort definition

Presentation selection is based on sample size, complete VLE coverage for days 0–27, course duration, and resource linkage. These criteria select `CCC-2014J` without reference to `final_result`.

The sample is formed in five steps:

| Stage | n |
|---|---:|
| Recorded enrollments | 2,498 |
| Registration date observed | 2,495 |
| Registered by day 0 | 2,482 |
| Still registered at day 0 | 2,271 |
| Observed through day 27 | 2,011 |

The primary cohort excludes 260 enrollments that unregister during the observation window. This gives all included enrollments the same potential exposure period, but narrows the population to students observed through day 27. A separate opportunity-adjusted analysis includes the 2,271 students who were active at day 0.

Activity is left-joined to the eligible cohort, so absence of VLE records remains a meaningful zero rather than becoming a missing row. The final sample includes 38 zero-click enrollments.

## Engagement measures

Three variables describe activity during course days 0–27:

- `total_clicks`: the sum of recorded VLE clicks;
- `active_days`: the number of distinct days with at least one recorded interaction;
- `distinct_resources`: the number of different VLE resources accessed.

They represent intensity, regularity, and breadth of platform use. These are behavioral traces rather than direct measurements of attention or learning.

The original counts are right-skewed. Total clicks, for example, have mean 289.4, median 203, and maximum 3,247. The clustering variables are therefore transformed with `log1p`, which accommodates zeros and reduces the influence of very large counts, and then standardized to mean zero and unit variance. Profile descriptions remain on the original count scale.

## Exploratory structure

In the primary cohort, median total clicks are 203, median active days are 9, and median distinct resources are 17. The respective interquartile ranges are 110–357.5, 6–14, and 11–24.

The three transformed variables remain strongly associated; the largest pairwise correlation is 0.872. The first principal component explains 89.6% of their variance. Consequently, most of the multivariate structure follows a common low-to-high engagement direction. The variables add interpretable detail, but they do not constitute three independent behavioral dimensions.

The `log1p` transformation improves the shape of the distributions without making them exactly Gaussian. In particular, the 38 zero-activity cases remain a shared point mass.

## Gaussian mixture model

A Gaussian mixture represents the observed density as a weighted combination of multivariate normal components. Each component has its own location and covariance structure. The EM algorithm estimates the component parameters and posterior membership probabilities.

The search covers one to nine components and all covariance families implemented by `mclust`. Seven outcome-blind initializations are evaluated for each candidate. BIC is used to select the density model, after which the selected specification is refitted from additional starts and the best recorded likelihood is retained.

The highest BIC is obtained by a four-component VVE model. VVE allows component volume and shape to vary while keeping their orientation equal. The selected fit has BIC -10,420.719, log-likelihood -5,096.264, and 30 free parameters. Its smallest component contains 91 observations, and the minimum covariance eigenvalue is 0.0177, so the selected fit is neither tiny nor numerically degenerate.

BIC compares candidate density models; it is not a test for the existence of four naturally separated student populations. ICL applies an additional entropy penalty and instead prefers a two-component EVE model.

## Profile interpretation

The fitted components are ordered by median total clicks:

| Profile | n | Median clicks | Median active days | Median resources |
|---|---:|---:|---:|---:|
| P1 | 91 | 1 | 1 | 1 |
| P2 | 493 | 86 | 4 | 9 |
| P3 | 1,145 | 229 | 10 | 19 |
| P4 | 282 | 651.5 | 19 | 24 |

P1 contains all 38 zero-click enrollments together with a small number of very-low-activity cases. P3 contains 56.9% of the cohort and covers a broad middle range. The profile ordering is easy to interpret, but membership is probabilistic rather than an observed student characteristic.

Mean posterior uncertainty is 0.217, and 988 of 2,011 assignments exceed 0.20. Mean silhouette width is 0.221, with 22.8% negative values. These diagnostics show substantial overlap, especially near the component boundaries.

## Outcomes

After clustering, `final_result` is cross-tabulated with profile membership. The association is statistically clear: χ²(9)=189.830, p=4.47×10^-36. Cramér's V is 0.177, and the smallest expected count is 13.80.

Withdrawal decreases from 50.5% in P1 to 18.4% in P4. Pass and Distinction become more common across the same ordering. This is a descriptive association within one restricted cohort. It does not control for prior achievement, motivation, personal circumstances, or other possible confounders, and it does not imply that increasing click counts would cause a better result.

## Robust clustering and ARI

TCLUST provides a robustness comparison by trimming a fixed proportion of observations and constraining covariance eigenvalue ratios. The primary specification uses four groups, `alpha=0.05`, restriction factor `c=20`, and 1,000 starts. It trims 101 observations and retains 1,910.

The adjusted Rand index between TCLUST and the Gaussian mixture is 0.238981 on those retained cases. The calculation was reproduced directly from the enrollment-level contingency table. TCLUST label 0 denotes a trimmed observation and is excluded rather than treated as an additional cluster.

The methods divide the data differently because they optimize different criteria. TCLUST places 1,717 observations in one broad middle group and isolates smaller zero, very-low, and very-high groups. The Gaussian mixture uses several overlapping components to approximate the density along the same engagement gradient.

## Sensitivity

The robustness checks were selected to test the primary result rather than to maximize agreement:

- across the prespecified TCLUST configurations, retained-case ARI ranges from 0.117 to 0.283;
- the 14-day specification fixes four components, selects EEV, and has ARI 0.175 against the primary partition;
- the opportunity-adjusted cohort contains 2,271 enrollments, selects VEV with four components, and has overlap ARI 0.082;
- conditional on a successful fixed G=4 VVE fit, median subsample ARI is 0.772;
- when model selection is repeated within each subsample, the exact G=4 VVE specification is selected in 24% of repetitions and median ARI falls to 0.256.

The difference between the fixed-model and reselected-model results is important. A four-component VVE geometry can often be recovered when imposed, but the data do not consistently select that exact specification.

## Scope of the conclusions

The analysis supports four findings. First, early activity in `CCC-2014J` is dominated by a continuous engagement-intensity gradient. Second, a four-component VVE mixture gives the best BIC approximation among the models considered. Third, recorded outcomes differ across the fitted low-to-high engagement regions. Fourth, the number and boundaries of hard groups change materially under alternative classification criteria, algorithms, observation windows, cohort rules, and case samples.

The model is therefore useful for description, but the profile labels should not be treated as fixed learner types. The main limitations are the single-presentation scope, exclusion of early unregistrations from the primary cohort, correlated proxy variables, approximate Gaussian assumptions, posterior overlap, initialization failures, and model-selection instability.

## Reproduction

Package versions are recorded in `renv.lock`. A complete run is started with:

```powershell
Rscript main.R
```

On Windows, `scripts/run-r.ps1` locates a suitable R installation:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-r.ps1 main.R
```

The pipeline downloads and verifies OULAD when necessary, rebuilds the cohort and models, regenerates the figures and tables, and runs the numerical checks. `EXAM_DEMO.R` and `main.R --demo` provide a faster inspection of the saved fitted objects without refitting.
