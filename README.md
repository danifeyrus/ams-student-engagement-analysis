# Early Online Engagement Profiles in OULAD

Reproducible Advanced Multivariate Statistics project examining early virtual-learning-environment engagement in the Open University Learning Analytics Dataset (OULAD). The analysis combines exploratory data analysis, Gaussian model-based clustering, descriptive outcome comparisons, robust trimmed clustering, and transparent sensitivity diagnostics.

This repository contains executable R code, verified numerical outputs, and reusable figures and tables. It does not contain the course report, slides, private teaching materials, or oral-defense notes.

## Research questions

1. What engagement profiles are supported by total clicks, active days, and distinct resources during course days 0–27?
2. How do recorded course outcomes differ descriptively across those profiles?
3. How robust are the profiles to trimmed clustering, alternative observation rules, transformations, variables, and resampling?

## Data

The pipeline uses the official [Open University Learning Analytics Dataset](https://doi.org/10.24432/C5KK69), described by [Kuzilek, Hlosta, and Zdrahal (2017)](https://doi.org/10.1038/sdata.2017.171) and released under CC BY 4.0.

`main.R` downloads the official archive when raw tables are absent, verifies SHA-256 `F2ED1902616C1FE8D2824D872C0B7D2D72BE435BF0124D077044FE4BE2C6D3E4`, validates all seven tables and joins, and preserves raw files under the Git-ignored `data/raw/` directory. Provenance is documented in `results/data-source-verification.md`.

The outcome-blind selection rule chose module-presentation `CCC-2014J`. Of 2,498 recorded enrollments, 2,011 were registered by day 0 and remained observable through day 27; 38 zero-click enrollments were retained. The primary features are:

- total VLE clicks;
- number of active course days;
- number of distinct VLE resources accessed.

The clustering inputs are `log1p` transformed and z-standardized. Original counts are retained for interpretation. `final_result` is joined only after clustering.

## Methods

- Descriptive EDA, missingness and cohort-flow validation.
- Gaussian mixtures fitted with `mclust` over component counts and covariance structures, using seven outcome-blind initializations and repeated selected-model fits.
- BIC for density-model selection; ICL, posterior entropy, silhouette widths, component diagnostics, and subsampling for classification validity.
- Post-clustering outcome cross-tabulation, chi-squared test, and Cramér's V; no causal or predictive interpretation.
- `tclust` with prespecified trimming and eigenvalue-ratio restrictions, multiple starts, and retained-observation ARI comparisons.
- Window, inclusion, transformation, feature, restriction-factor, and resampling sensitivity analyses.

## Verified results

- BIC selected a four-component VVE Gaussian mixture: BIC `-10420.719`, with component sizes 91, 493, 1,145, and 282.
- Original-scale median profiles progress along a dominant engagement-intensity gradient: `1/1/1`, `86/4/9`, `229/10/19`, and `651.5/19/24` for clicks/active days/resources.
- Outcome distributions differ descriptively: χ²(9) = `189.830`, p = `4.47e-36`, Cramér's V = `0.177`. Withdrawal decreases from 50.5% in P1 to 18.4% in P4.
- Classification is ambiguous: mean posterior uncertainty is `0.217`; 988 of 2,011 assignments exceed 0.20.
- The primary TCLUST solution (`alpha=0.05`, `c=20`, 1,000 starts) trims 101 observations and has retained-case ARI `0.239` versus the Gaussian partition.
- PC1 explains 89.6% of feature variance; mean Gaussian silhouette is `0.221`; ICL prefers two components; the exact G/model is reselected in 24% of case subsamples.

The defensible conclusion is an exploratory, model-dependent segmentation of a mostly continuous engagement gradient—not four uniquely stable natural learner types.

## Repository structure

```text
.
├── main.R                         # full pipeline and --demo entry point
├── EXAM_DEMO.R                    # interactive cached demonstration
├── src/                           # acquisition, analysis, diagnostics, audit
├── data/processed/                # three tracked caches for the quick demo
├── results/                       # verified machine-readable outputs
├── figures/                       # complete 20-figure diagnostic set
├── publication/                   # selected reusable figures/tables and index
├── docs/ANALYSIS_EXPLAINED.md     # accessible methodological walkthrough
├── scripts/run-r.ps1              # portable Windows R launcher
├── renv.lock                      # pinned R dependency versions
└── .vscode/                       # tasks, extension recommendation, example settings
```

## Setup on Windows and VS Code

1. Install R 4.6.2 or a compatible recent R release and ensure `Rscript` is on `PATH`.
2. Install Visual Studio Code and the recommended `REditorSupport.r` extension.
3. Clone the private repository and open its root folder in VS Code:

```powershell
git clone https://github.com/danifeyrus/ams-student-engagement-analysis.git
cd ams-student-engagement-analysis
```

4. In an R terminal, restore the recorded dependencies:

```r
install.packages("renv") # only if renv is not already installed
renv::restore()
```

5. If custom workspace settings are needed, copy `.vscode/settings.example.json` to `.vscode/settings.json` and adjust only machine-specific paths.

## Full execution

From PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-r.ps1 main.R
```

Or, when `Rscript` is on `PATH`:

```powershell
Rscript main.R
```

The run downloads and validates data when necessary, rebuilds every analysis artifact, executes the statistical audit, prepares `publication/`, and stops if a required invariant fails. A full model refit is computationally substantial.

## Quick cached demonstration

Three fitted-object caches are tracked so a clone can demonstrate the verified results without refitting:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-r.ps1 EXAM_DEMO.R
# or
powershell -ExecutionPolicy Bypass -File scripts/run-r.ps1 main.R --demo
```

The cached demo is for inspection only; `main.R` is the reproducibility authority.

## Reproducibility controls

- fixed random seed (`20261108`);
- archive checksum and raw-table hashes;
- validated keys, cardinalities, dates, and zero-activity retention;
- outcome-blind cohort and model selection;
- explicit multiple-start searches and warning logs;
- `renv.lock`, package versions, session information, and output MD5 manifest;
- independent manual ARI verification on exactly the 1,910 TCLUST-retained observations.

## Interpretation and limitations

The project is observational and exploratory. Clicks are interaction proxies, not learning measurements. The primary cohort excludes early unregistrations to equalize observation opportunity, so findings apply to one module-presentation and the stated eligibility rule. Correlated features largely measure one intensity axis. BIC supports a useful density approximation, but posterior ambiguity, ICL, silhouette, TCLUST, alternative specifications, and subsampling all warn against reifying hard clusters. Outcome comparisons are associations and must not be described as causal effects or predictions.

## Team workflow

Create a feature branch, keep statistical code in `src/`, and submit changes through review. Never hand-edit generated files in `results/`, `figures/`, or `publication/`; regenerate them through `main.R`. Use `publication/ASSETS_INDEX.md` to select report or slide assets, and record any new methodological decision in code and machine-readable output before interpreting it.

## References

- Kuzilek, J., Hlosta, M., & Zdrahal, Z. (2017). Open University Learning Analytics Dataset. *Scientific Data, 4*, 170171. <https://doi.org/10.1038/sdata.2017.171>
- Scrucca, L., Fop, M., Murphy, T. B., & Raftery, A. E. (2016). mclust 5: Clustering, Classification and Density Estimation Using Gaussian Finite Mixture Models. *The R Journal, 8*(1), 289–317. <https://doi.org/10.32614/RJ-2016-021>
- Fritz, H., García-Escudero, L. A., & Mayo-Iscar, A. (2012). tclust: An R Package for a Trimming Approach to Cluster Analysis. *Journal of Statistical Software, 47*(12), 1–26. <https://doi.org/10.18637/jss.v047.i12>
