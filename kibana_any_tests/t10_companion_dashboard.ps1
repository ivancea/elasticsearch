# Runs the section 5 ("?x__nulls" companion) filter of the scenarios dashboard against local any_demo, with the params
# Kibana sends for several selections, and compares each count with a direct query.
$es = 'http://localhost:9200'
function esql([string]$query, [object[]]$params) {
  $body = @{ query = $query; params = $params } | ConvertTo-Json -Depth 10 -Compress
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    ($r.Content | ConvertFrom-Json).values[0][0]
  } catch { "ERROR: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }) }
}
function nullsFilter([string]$param, [string]$field, [string]$cast = $null) {
  $value = if ($cast) { "$cast(?$param)" } else { "?$param" }
  "| WHERE (?$param IS NULL AND NOT ?${param}__nulls) OR MV_INTERSECTS($value, $field) OR (?${param}__nulls AND $field IS NULL)"
}
$query = "FROM any_demo`n" + ((nullsFilter 'nv_os' 'os'), (nullsFilter 'nv_priority' 'priority'), (nullsFilter 'nv_secure' 'secure' 'TO_BOOLEAN') -join "`n") + "`n| STATS docs = COUNT(*)"

# Kibana: no selection -> null; numeric columns -> numbers; other columns -> strings; the companion is always a boolean.
function params($os, $osN, $pr, $prN, $se, $seN) {
  @(@{ nv_os = $os }, @{ nv_os__nulls = $osN }, @{ nv_priority = $pr }, @{ nv_priority__nulls = $prN }, @{ nv_secure = $se }, @{ nv_secure__nulls = $seN })
}
$cases = @(
  @('Any everywhere', (params $null $false $null $false $null $false), 'FROM any_demo | STATS COUNT(*)'),
  @('Priority 1, 2', (params $null $false @(1, 2) $false $null $false), 'FROM any_demo | WHERE priority IN (1, 2) | STATS COUNT(*)'),
  @('Priority (No value) only', (params $null $false $null $true $null $false), 'FROM any_demo | WHERE priority IS NULL | STATS COUNT(*)'),
  @('Priority 4 + (No value)', (params $null $false @(4) $true $null $false), 'FROM any_demo | WHERE priority == 4 OR priority IS NULL | STATS COUNT(*)'),
  @('Secure true + (No value)', (params $null $false $null $false @('true') $true), 'FROM any_demo | WHERE secure == true OR secure IS NULL | STATS COUNT(*)'),
  @('Secure false', (params $null $false $null $false @('false') $false), 'FROM any_demo | WHERE secure == false | STATS COUNT(*)'),
  @('OS linux + (No value), Priority 1', (params @('linux') $true @(1) $false $null $false), 'FROM any_demo | WHERE (os == "linux" OR os IS NULL) AND priority == 1 | STATS COUNT(*)')
)
foreach ($c in $cases) {
  $got = esql $query $c[1]
  $expected = esql $c[2] @()
  "{0,-36} filter={1,-6} direct={2,-6} {3}" -f $c[0], $got, $expected, $(if ("$got" -eq "$expected") { 'OK' } else { 'MISMATCH' })
}
