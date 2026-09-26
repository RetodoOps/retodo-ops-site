# Update 060 — Excel CSV column fix

Only five complete changed files. Baseline: main fef44a3 / Update 059.

## Install

1. Extract the ZIP.
2. Upload the extracted `tms` and `docs` folders plus this instructions file to the root of **RetodoOps/retodo-ops-site**, branch **main**. Preserve their directory structure.
3. Commit, for example `Update 060: Excel CSV separator fix`.
4. Refresh Reports with Ctrl+F5. The page should display **Update 060**.
5. Export a NEW CSV and open that new file in Excel.

**No Supabase migration or audit is required. Do not rerun previous SQL.**

## What changed

The screenshot shows every comma-separated row in column A. Excel's direct-open path uses regional list-separator settings. The export now declares `sep=,` on the first line so Excel can split the comma-separated fields into columns. It retains the UTF-8 marker for names/languages.

No business calculations or database functions changed. CSV still contains metadata, details and summaries, with the same escaping, formula protection and signed decimal values. This is a text export, not a formatted Excel workbook. Other CSV readers may display the `sep=,` directive as an extra row; skip that first line when importing into those readers.

The directive selects the column delimiter, not the numeric/date locale. If Excel interprets decimal amounts as text, use a text/CSV import and specify English (United States) for dot-decimal numeric columns. A native XLSX exporter is not part of this patch.

## Open the CSV you already downloaded

In a blank Excel workbook choose **Data / Данни → From Text/CSV / От текст/CSV**, select the original CSV, set **Delimiter / Разделител = Comma / Запетая** and encoding **UTF-8**, then load. This avoids changing system-wide settings. CSV metadata appears above the detail header; do not promote the first metadata row to the detail-table header. For a decimal conversion, use Transform Data and the appropriate numeric locale.

Microsoft reference: https://support.microsoft.com/en-us/excel/get-started/import-or-export-text-txt-or-csv-files

## Validation and continuity

- Existing six CSV/escaping/warning checks passed.
- Generated CSV verified for BOM/directive/CRLF and round-tripped with Unicode, embedded commas, quotes, newlines and a negative decimal amount.
- JavaScript syntax and diff checks passed.
- Microsoft Excel desktop is not installed here; confirm direct-opening a new CSV on your machine after upload.
- CURRENT_WORK.md now records your Update 059 commit and initial functional check. Update 060 remains pending your upload.
