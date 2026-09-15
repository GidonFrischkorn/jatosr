# Extract scalar fields from result files without parsing them

Reads one or more JSON keys (for example `participant_id`) out of every
downloaded `data.txt` by regular expression, which is several times
faster than parsing each file and works on files that are not valid JSON
as a whole. The pattern is anchored on the key position (`"field":`), so
the same text inside a value, say a URL query string, is not matched.
All key-position occurrences are collected, at any depth of the JSON:
when they agree the value is returned; when they disagree the value is
`NA` and the row is flagged.

## Usage

``` r
jatos_extract_fields(metadata, fields, warn = TRUE, file_col = "file")
```

## Arguments

- metadata:

  A metadata tibble with the local file column (from
  [`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
  or
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)).

- fields:

  Character vector of key names to extract.

- warn:

  If `FALSE`, the closing warnings (`conflict` and `unparseable` files,
  disagreements with the parser) are not raised; the status columns
  still say it all. Files without the key (`absent`) are reported in a
  message either way, since a key that only some components carry is not
  a fault.

- file_col:

  Name of the column holding the local file paths.

## Value

`metadata` with two columns per field: `<field>` and `<field>_status`,
and the attribute `jatosr_extracted` naming every extracted field. The
value column is numeric when every value is a JSON number, logical when
every value is `true` or `false`, character otherwise; JSON `null` is
`NA`. The status is `unique` (all occurrences agree), `absent` (no
occurrence), `conflict` (occurrences disagree, or an occurrence holds an
array or object), or `unparseable` (the file has no unique value and the
parser could not read it). Rows without a local file get `NA` in both
columns.

## Details

Every file where the regular expression found disagreeing values (status
`conflict`) is then parsed in full with the same parser
[`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md)
uses, every value stored under the key at any depth is collected from
the parsed objects, and the two readings are compared; so is every file
without the key (status `absent`) as long as the key was found in some
other file, since a key present in one file and missing in the next may
be an escaped spelling the regular expression does not see. On a file
with one agreeing value the regular expression cannot be wrong, so those
files are not parsed, and a key found in no file at all is reported
`absent` everywhere without parsing (read one file with
[`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md)
when that is a surprise). A disagreement means the regular expression
read a file differently from the parser (an escaped key, an unusual
encoding) and is a warning naming the files; a message reports the
tally. A file the parser refuses gets status `unparseable`, which means
exactly that
[`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
would stop on it.

A field whose name is already a column of `metadata` (`batch_id`,
`worker_id`, `file`, ...) is refused before any file is read, since the
extracted values would silently replace the server's. The two columns of
a previous extraction of the same field are replaced; which columns came
from an extraction is recorded in the attribute `jatosr_extracted` of
the returned tibble, so a column pair of your own that happens to end in
`_status` is never mistaken for one.

## See also

[`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md),
which carries the value columns to the study-result level and flags
component results that disagree.

## Examples

``` r
cache <- system.file("extdata", "JATOS_data", package = "jatosr")
meta <- jatos_read_metadata(cache)
meta <- jatos_extract_fields(meta, c("participant_id", "age"))
meta[, c("study_result_id", "participant_id", "participant_id_status", "age")]
#> # A tibble: 4 × 4
#>   study_result_id participant_id participant_id_status age  
#>             <int> <chr>          <chr>                 <chr>
#> 1            9001 P501           unique                24   
#> 2            9002 NA             NA                    NA   
#> 3            9002 P502           unique                31   
#> 4            9003 NA             NA                    NA   
```
