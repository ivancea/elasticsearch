# Creates the "2. ES|QL controls: Any - functions" dashboard: the same sections as the scenarios dashboard, but every
# control-driven part uses the prototype functions IN_SELECTION, FIELD_OR and OPTIONAL (ES built from this workspace)
# instead of the hand-written templates. Each function lowers to the corresponding template.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null)

$from = 'FROM any_demo'

# Queries are written one command per line; the control-driven part is wrapped in "// ... start" / "// ... end".
function marked([string]$name, [string]$body) { "// $name start`n$body`n// $name end" }

# --- Filters per section -------------------------------------------------------------------------------------------
$svFilter = marked 'Filter' '| WHERE IN_SELECTION(os, ?sv_os)'

# include_nulls only widens an actual selection: with Tags on "Any" it has no effect.
$mvFilter = marked 'Filter' '| WHERE IN_SELECTION(tags, ?mv_tags, {"include_nulls": ?mv_blank})'

$nlFilter = marked 'Filter' (@'
| WHERE IN_SELECTION(os, ?nl_os, {"null_value": "__NULL__"})
| WHERE IN_SELECTION(tags, ?nl_tags, {"null_value": "__NULL__"})
'@.Trim())

# "(No value)" via the companion param ?<name>__nulls; the function casts the selection to the field type.
function nullsFilter([string]$param, [string]$field) {
  "| WHERE IN_SELECTION($field, ?$param, {`"nulls`": ?${param}__nulls})"
}

# Breakdown: a ??field control. Cleared, FIELD_OR gives one "all documents" group and OPTIONAL drops the key.
$bdGroup = 'group = FIELD_OR(??fn_bd, "all documents")'

# --- Builders ---------------------------------------------------------------------------------------------------
function control([int]$x, [int]$w, [hashtable]$config) {
  [ordered]@{ grid = @{ x = $x; y = 0; w = $w; h = 2 }; type = 'esql_control'; config = $config }
}
function metric([int]$x, [int]$y, [int]$w, [string]$title, [string]$query, [string]$primary, [string]$secondary = $null) {
  $metrics = @(@{ type = 'primary'; column = $primary })
  if ($secondary) { $metrics += @{ type = 'secondary'; column = $secondary } }
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = 6 }; type = 'vis'; config = [ordered]@{
      type = 'metric'; title = $title; data_source = @{ type = 'esql'; query = $query }; metrics = $metrics } }
}
function table([int]$x, [int]$y, [int]$w, [int]$h, [string]$title, [string]$query, [string[]]$rows, [string]$metricColumn) {
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = $h }; type = 'vis'; config = [ordered]@{
      type = 'data_table'; title = $title; data_source = @{ type = 'esql'; query = $query }
      metrics = @(@{ column = $metricColumn }); rows = @($rows | ForEach-Object { @{ column = $_ } }) } }
}
function bars([int]$x, [int]$y, [int]$w, [int]$h, [string]$title, [string]$query, [string]$breakdown) {
  [ordered]@{ grid = @{ x = $x; y = $y; w = $w; h = $h }; type = 'vis'; config = [ordered]@{
      type = 'xy'; title = $title
      layers = @([ordered]@{ type = 'bar_stacked'; data_source = @{ type = 'esql'; query = $query }
          x = @{ column = 'bucket' }; y = @(@{ column = 'docs' }); breakdown_by = @{ column = $breakdown } }) } }
}
function section([string]$title, [int]$y, [object[]]$panels) {
  [ordered]@{ title = $title; collapsed = $false; grid = @{ y = $y }; panels = $panels }
}
function lines([string[]]$parts) { ($parts | Where-Object { $_ }) -join "`n" }

$tagSets = lines '| EVAL tag_set = COALESCE(MV_CONCAT(MV_SORT(tags), ", "), "(no tags)")', '| STATS docs = COUNT(*) BY tag_set', '| SORT docs DESC'
$byOs = lines '| EVAL os = COALESCE(os, "(no os)")', '| STATS docs = COUNT(*) BY os', '| SORT docs DESC'

# --- Sections ---------------------------------------------------------------------------------------------------
$single = section '1. Single value field (os)' 0 @(
  (control 0 16 ([ordered]@{ title = 'Single value · OS'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | STATS BY os'
      variable_name = 'sv_os'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (metric 0 2 12 'Matching documents' (lines $from, $svFilter, '| STATS docs = COUNT(*), no_os = COUNT(*) WHERE os IS NULL') 'docs' 'no_os'),
  (table 12 2 36 8 'Documents by OS' (lines $from, $svFilter, $byOs) @('os') 'docs')
)

$multi = section '2. Multivalue field (tags): Any and blank flag' 12 @(
  (control 0 16 ([ordered]@{ title = 'Multivalue · Tags'; control_type = 'VALUES_FROM_QUERY'; esql_query = 'FROM any_demo | MV_EXPAND tags | STATS BY tags'
      variable_name = 'mv_tags'; variable_type = 'multi_values'; single_select = $false; selected_options = @() })),
  (control 16 16 ([ordered]@{ title = 'Multivalue · Include docs without tags'; control_type = 'STATIC_VALUES'; available_options = @('false', 'true')
      variable_name = 'mv_blank'; variable_type = 'values'; single_select = $true; selected_options = @('false') })),
  (metric 0 2 12 'Matching documents' (lines $from, $mvFilter, '| STATS docs = COUNT(*), no_tags = COUNT(*) WHERE tags IS NULL') 'docs' 'no_tags'),
  (table 12 2 36 10 'Documents by tag combination' (lines $from, $mvFilter, $tagSets) @('tag_set') 'docs')
)

$breakdown = section '3. STATS BY: FIELD_OR (Any = one group) and OPTIONAL (Any = no breakdown key)' 26 @(
  (control 0 20 ([ordered]@{ title = 'Breakdown · Group by (??field)'; control_type = 'STATIC_VALUES'; available_options = @('os', 'region', 'host')
      variable_name = 'fn_bd'; variable_type = 'fields'; single_select = $true; selected_options = @() })),
  (bars 0 2 24 10 'Documents over time by FIELD_OR group' (lines $from, '| STATS docs = COUNT(*)',
      "    BY bucket = BUCKET(@timestamp, 30, ?_tstart, ?_tend), $bdGroup") 'group'),
  (table 24 2 12 10 'Documents by FIELD_OR group' (lines $from, "| STATS docs = COUNT(*) BY $bdGroup", '| SORT docs DESC') @('group') 'docs'),
  (table 36 2 12 10 'Documents BY OPTIONAL(??fn_bd)' (lines $from, '| STATS docs = COUNT(*) BY OPTIONAL(??fn_bd)', '| SORT docs DESC') @('??fn_bd') 'docs')
)

$nullLabel = section '4. "(No value)" option via the __NULL__ sentinel: single value and multivalue' 40 @(
  (control 0 16 ([ordered]@{ title = 'Null label · OS (single value)'; control_type = 'VALUES_FROM_QUERY'
      esql_query = 'FROM any_demo | STATS BY os | EVAL os = COALESCE(os, "__NULL__")'
      variable_name = 'nl_os'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (control 16 16 ([ordered]@{ title = 'Null label · Tags (multivalue)'; control_type = 'VALUES_FROM_QUERY'
      esql_query = 'FROM any_demo | MV_EXPAND tags | STATS BY tags | EVAL tags = COALESCE(tags, "__NULL__")'
      variable_name = 'nl_tags'; variable_type = 'multi_values'; single_select = $false; selected_options = @() })),
  (metric 0 2 12 'Matching documents' (lines $from, $nlFilter, '| STATS docs = COUNT(*), no_tags = COUNT(*) WHERE tags IS NULL') 'docs' 'no_tags'),
  (table 12 2 18 10 'Documents by OS' (lines $from, $nlFilter, $byOs) @('os') 'docs'),
  (table 30 2 18 10 'Documents by tag combination' (lines $from, $nlFilter, $tagSets) @('tag_set') 'docs')
)

$nvFilter = marked 'Filter' (lines (nullsFilter 'nv_os' 'os'), (nullsFilter 'nv_priority' 'priority'), (nullsFilter 'nv_secure' 'secure'))
function nvControl([int]$x, [string]$title, [string]$field, [string]$variable) {
  control $x 16 ([ordered]@{ title = $title; control_type = 'VALUES_FROM_QUERY'; esql_query = "FROM any_demo | STATS BY $field"
      variable_name = $variable; variable_type = 'multi_values'; single_select = $false; selected_options = @()
      include_no_value_option = $true })
}
function nvTable([int]$x, [string]$field) {
  table $x 2 12 10 "Documents by $field" (lines $from, $nvFilter, "| EVAL $field = COALESCE(TO_STRING($field), `"(no $field)`")",
      "| STATS docs = COUNT(*) BY $field", '| SORT docs DESC') @($field) 'docs'
}
$companion = section '5. "(No value)" option via the ?x__nulls companion param: keyword, integer and boolean' 54 @(
  (nvControl 0 'Companion · OS (keyword)' 'os' 'nv_os'),
  (nvControl 16 'Companion · Priority (integer)' 'priority' 'nv_priority'),
  (nvControl 32 'Companion · Secure (boolean)' 'secure' 'nv_secure'),
  (metric 0 2 12 'Matching documents' (lines $from, $nvFilter,
      '| STATS docs = COUNT(*), blank_fields = COUNT(*) WHERE os IS NULL OR priority IS NULL OR secure IS NULL') 'docs' 'blank_fields'),
  (nvTable 12 'os'),
  (nvTable 24 'priority'),
  (nvTable 36 'secure')
)

$dashboard = [ordered]@{
  title       = '2. ES|QL controls: Any - functions'
  description = 'Same sections as "1. ES|QL controls: Any - scenarios", written with the prototype functions IN_SELECTION, FIELD_OR and OPTIONAL (elasticsearch#136735).'
  time_range  = [ordered]@{ from = 'now-7d'; to = 'now' }
  panels      = @($single, $multi, $breakdown, $nullLabel, $companion)
}

$body = $dashboard | ConvertTo-Json -Depth 40
$headers = @{ 'kbn-xsrf' = 'true'; 'elastic-api-version' = '2023-10-31' }
try {
  if ($Id) {
    Invoke-WebRequest -Method PUT -Uri "$Kibana/api/dashboards/$Id" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing | Out-Null
    "Updated dashboard: $Kibana/app/dashboards#/view/$Id"
  } else {
    $r = Invoke-WebRequest -Method POST -Uri "$Kibana/api/dashboards" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    $newId = ($r.Content | ConvertFrom-Json).id
    "Created dashboard: $Kibana/app/dashboards#/view/$newId"
  }
} catch {
  "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message })
}
