# Creates the "1. ES|QL controls: Any - scenarios" dashboard: one section per scenario, each with its own controls and
# variables. Panels only reference their own section's variables, so sections don't affect each other.
param([string]$Kibana = 'http://localhost:5601', [string]$Id = $null)

$from = 'FROM any_demo'

# Queries are written one command per line; the control-driven part is wrapped in "// ... start" / "// ... end".
function marked([string]$name, [string]$body) { "// $name start`n$body`n// $name end" }

# --- Filters per section -------------------------------------------------------------------------------------------
$svFilter = marked 'Filter' '| WHERE ?sv_os IS NULL OR MV_INTERSECTS(?sv_os, os)'

# The flag only widens an actual selection: with Tags on "Any" it has no effect ("Any" already includes blanks).
# "Blanks only" is an explicit "(No value)" choice in section 4.
$mvFilter = marked 'Filter' (@'
| WHERE ?mv_tags IS NULL
     OR MV_INTERSECTS(?mv_tags, tags)
     OR (COALESCE(?mv_blank, "false") == "true" AND tags IS NULL)
'@.Trim())

$nlFilter = marked 'Filter' (@'
| WHERE ?nl_os IS NULL
     OR MV_INTERSECTS(?nl_os, os)
     OR (os IS NULL AND MV_CONTAINS(?nl_os, "__NULL__"))
| WHERE ?nl_tags IS NULL
     OR MV_INTERSECTS(?nl_tags, tags)
     OR (tags IS NULL AND MV_CONTAINS(?nl_tags, "__NULL__"))
'@.Trim())

# "(No value)" via the companion boolean param ?<name>__nulls, which Kibana derives from the control. Works for any
# field type: no sentinel value travels in ?<name>. "Any" (nothing selected) sends null + false, so the filter folds away.
# $cast wraps the param where the control sends strings for a non-string field (e.g. TO_BOOLEAN for booleans).
function nullsFilter([string]$param, [string]$field, [string]$cast = $null) {
  $value = if ($cast) { "$cast(?$param)" } else { "?$param" }
  @"
| WHERE (?$param IS NULL AND NOT ?${param}__nulls)
     OR MV_INTERSECTS($value, $field)
     OR (?${param}__nulls AND $field IS NULL)
"@.Trim()
}

# Breakdown: a value control holding a field name, mapped with CASE. Cleared ("Any") gives one group (option G).
$bdGroup = marked 'Breakdown' (@'
| EVAL group = CASE(
    ?bd_field == "os", os,
    ?bd_field == "region", region,
    ?bd_field == "host", host,
    "all documents")
'@.Trim())

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

$breakdown = section '3. STATS BY: breakdown with "Any" (one group) and the ??field gap' 26 @(
  (control 0 16 ([ordered]@{ title = 'Breakdown · Group by (value control + CASE)'; control_type = 'STATIC_VALUES'; available_options = @('os', 'region', 'host')
      variable_name = 'bd_field'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (control 16 20 ([ordered]@{ title = 'Breakdown · Group by (??field; clearing shows the gap)'; control_type = 'STATIC_VALUES'; available_options = @('os', 'region', 'host')
      variable_name = 'bd_ident'; variable_type = 'fields'; single_select = $true; selected_options = @('host') })),
  (bars 0 2 24 10 'Documents over time by group (Any = one group)' (lines $from, $bdGroup, '| STATS docs = COUNT(*) BY bucket = BUCKET(@timestamp, 30, ?_tstart, ?_tend), group') 'group'),
  (table 24 2 12 10 'Documents by group' (lines $from, $bdGroup, '| STATS docs = COUNT(*) BY group', '| SORT docs DESC') @('group') 'docs'),
  (table 36 2 12 10 'Documents BY ??field' (lines $from, '| STATS docs = COUNT(*) BY ??bd_ident', '| SORT docs DESC') @('??bd_ident') 'docs')
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

$nvFilter = marked 'Filter' (lines (nullsFilter 'nv_os' 'os'), (nullsFilter 'nv_priority' 'priority'), (nullsFilter 'nv_secure' 'secure' 'TO_BOOLEAN'))
function nvControl([int]$x, [string]$title, [string]$field, [string]$variable) {
  # include_no_value_option is the local Kibana patch. Stock Kibana (cloud 9.5.1) rejects the field.
  $cfg = [ordered]@{ title = $title; control_type = 'VALUES_FROM_QUERY'; esql_query = "FROM any_demo | STATS BY $field"
      variable_name = $variable; variable_type = 'multi_values'; single_select = $false; selected_options = @() }
  if ($Kibana -match 'localhost|127\.0\.0\.1') { $cfg.include_no_value_option = $true }
  control $x 16 $cfg
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

# "Greater than" with MV_GREATER: true if any value is above the bound, so it works whether the field is multivalue or
# not. Static numeric options arrive as integer params, and MV_GREATER needs the bound's exact type: TO_LONG for bytes.
$gtFilter = marked 'Filter' (@'
| WHERE ?gt_bytes IS NULL OR MV_GREATER(bytes, TO_LONG(?gt_bytes))
| WHERE ?gt_latency IS NULL OR MV_GREATER(latency_ms, ?gt_latency)
'@.Trim())
function latencyRanges([string]$fn) {
  "| EVAL latency = CASE(latency_ms IS NULL, `"(no latency)`", $fn(latency_ms) < 100, `"0-99`", $fn(latency_ms) < 500, `"100-499`", $fn(latency_ms) < 900, `"500-899`", `"900+`")"
}
$greater = section '6. Greater than: MV_GREATER on single value (bytes) and multivalue (latency_ms) fields' 68 @(
  (control 0 16 ([ordered]@{ title = 'Greater than · Bytes above'; control_type = 'STATIC_VALUES'; available_options = @('1000', '5000', '10000', '15000')
      variable_name = 'gt_bytes'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (control 16 16 ([ordered]@{ title = 'Greater than · Any latency above (ms)'; control_type = 'STATIC_VALUES'; available_options = @('100', '500', '900')
      variable_name = 'gt_latency'; variable_type = 'values'; single_select = $true; selected_options = @() })),
  (metric 0 2 12 'Matching documents' (lines $from, $gtFilter, '| STATS docs = COUNT(*), no_latency = COUNT(*) WHERE latency_ms IS NULL') 'docs' 'no_latency'),
  (table 12 2 12 10 'Documents by bytes' (lines $from, $gtFilter,
      '| EVAL bytes_range = CASE(bytes < 1000, "0-999", bytes < 5000, "1000-4999", bytes < 10000, "5000-9999", bytes < 15000, "10000-14999", "15000+")',
      '| STATS docs = COUNT(*), lowest = MIN(bytes) BY bytes_range', '| SORT lowest', '| KEEP bytes_range, docs') @('bytes_range') 'docs'),
  (table 24 2 12 10 'Documents by highest latency' (lines $from, $gtFilter, (latencyRanges 'MV_MAX'), '| STATS docs = COUNT(*) BY latency', '| SORT latency') @('latency') 'docs'),
  (table 36 2 12 10 'Documents by lowest latency' (lines $from, $gtFilter, (latencyRanges 'MV_MIN'), '| STATS docs = COUNT(*) BY latency', '| SORT latency') @('latency') 'docs')
)

# CIDR_MATCH with a multi-select control. The direct form fails: multivalue blocks aren't supported (and break the
# Lucene pushdown, giving a partial result), and multivalue IPs are dropped. The workaround uses existing functions,
# with one MV_CONTAINS + MV_IN_RANGE clause per static option.
$cidrBlocks = [ordered]@{
  '192.168.0.0/16' = @('192.168.0.0', '192.168.255.255')
  '10.0.0.0/8'     = @('10.0.0.0', '10.255.255.255')
  '172.16.0.0/12'  = @('172.16.0.0', '172.31.255.255')
  '203.0.113.0/24' = @('203.0.113.0', '203.0.113.255')
  'fd00::/8'       = @('fd00::', 'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
}
$cidrDirect = marked 'Filter' '| WHERE ?net_cidr IS NULL OR CIDR_MATCH(client_ip, ?net_cidr)'
$cidrWorkaround = marked 'Filter' ("| WHERE ?net_cidr IS NULL`n" + (($cidrBlocks.Keys | ForEach-Object {
        "     OR (MV_CONTAINS(?net_cidr, `"$_`") AND MV_IN_RANGE(client_ip, TO_IP(`"$($cidrBlocks[$_][0])`"), TO_IP(`"$($cidrBlocks[$_][1])`")))" }) -join "`n"))
$byNetwork = lines '| MV_EXPAND client_ip', ('| EVAL network = CASE(client_ip IS NULL, "(no ip)", ' + (($cidrBlocks.Keys | ForEach-Object { "CIDR_MATCH(client_ip, `"$_`"), `"$_`"" }) -join ', ') + ', "(other)")'),
  '| STATS ip_values = COUNT(*) BY network', '| SORT ip_values DESC'
$cidr = section '7. CIDR_MATCH: multi-select CIDR blocks on a multivalue IP field (client_ip)' 82 @(
  (control 0 24 ([ordered]@{ title = 'CIDR · Client network'; control_type = 'STATIC_VALUES'; available_options = @($cidrBlocks.Keys)
      variable_name = 'net_cidr'; variable_type = 'multi_values'; single_select = $false; selected_options = @() })),
  (metric 0 2 12 'Direct CIDR_MATCH (fails on selection)' (lines $from, $cidrDirect, '| STATS docs = COUNT(*), multi_ip = COUNT(*) WHERE MV_COUNT(client_ip) > 1') 'docs' 'multi_ip'),
  (metric 12 2 12 'Workaround: MV_CONTAINS + MV_IN_RANGE' (lines $from, $cidrWorkaround, '| STATS docs = COUNT(*), multi_ip = COUNT(*) WHERE MV_COUNT(client_ip) > 1') 'docs' 'multi_ip'),
  (table 24 2 24 10 'IP values by network (workaround)' (lines $from, $cidrWorkaround, $byNetwork) @('network') 'ip_values')
)

$dashboard = [ordered]@{
  title       = '1. ES|QL controls: Any - scenarios'
  description = 'One section per scenario (elasticsearch#136735). Each section has its own controls; panels only use their own section''s variables.'
  time_range  = [ordered]@{ from = 'now-7d'; to = 'now' }
  panels      = @($single, $multi, $breakdown, $nullLabel, $companion, $greater, $cidr)
}

$body = $dashboard | ConvertTo-Json -Depth 40
$headers = @{ 'kbn-xsrf' = 'true'; 'elastic-api-version' = '2023-10-31' }
if ($env:ES_CLOUD_API_KEY -and $Kibana -notmatch 'localhost|127\.0\.0\.1') {
  $headers['Authorization'] = "ApiKey $($env:ES_CLOUD_API_KEY)"
}
try {
  if ($Id) {
    Invoke-WebRequest -Method PUT -Uri "$Kibana/api/dashboards/$Id" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing | Out-Null
    "Updated dashboard id=$Id"
  } else {
    $r = Invoke-WebRequest -Method POST -Uri "$Kibana/api/dashboards" -Headers $headers -ContentType 'application/json' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    $newId = ($r.Content | ConvertFrom-Json).id
    "Created dashboard id=$newId"
  }
} catch {
  "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message })
}
