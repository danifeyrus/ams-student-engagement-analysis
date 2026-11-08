# OULAD source verification

Verified on 2026-11-08.

- Authoritative UCI record: <https://archive.ics.uci.edu/dataset/349/open+university+learning+analytics+dataset>
- UCI DOI: <https://doi.org/10.24432/C5KK69>
- Open University project page: <https://research.stem.open.ac.uk/ouanalyse/dataset/>
- Data descriptor: Kuzilek, J., Hlosta, M. & Zdrahal, Z. (2017), *Scientific Data* 4, 170171, <https://doi.org/10.1038/sdata.2017.171>
- License verified at UCI and in the publication: Creative Commons Attribution 4.0 International (CC BY 4.0).
- Download URL followed from the UCI record: `https://archive.ics.uci.edu/static/public/349/open%2Buniversity%2Blearning%2Banalytics%2Bdataset.zip`
- Local archive: `data/raw/oulad_uci_349.zip`
- Size: 46,748,244 bytes.
- SHA-256: `F2ED1902616C1FE8D2824D872C0B7D2D72BE435BF0124D077044FE4BE2C6D3E4`.
- Archive contents: `courses.csv`, `assessments.csv`, `vle.csv`, `studentInfo.csv`, `studentRegistration.csv`, `studentAssessment.csv`, `studentVle.csv`, and `OULAD.names`.
- Extracted raw tables are under `data/raw/oulad/`; the archive and extracted files are preserved unchanged.

The supplied `OULAD.names` metadata reports 22 module-presentations, 6,364 VLE pages, 10,655,280 VLE rows, 206 assessments, and 173,912 assessment rows. It contains an internal inconsistency: one line says 32,953 student-course instances while its outcome table totals 32,593. The R validation pipeline must establish actual row/key counts and must not copy either figure uncritically.

