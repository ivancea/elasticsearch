# Converts a CIDR string into start/end IPs with existing ES|QL functions, to filter with MV_IN_RANGE (any IP value,
# multivalue-safe) instead of CIDR_MATCH. Start: IP_PREFIX (IPv4 and IPv6). End: octet arithmetic (IPv4 only).
$es = 'http://localhost:9200'
function raw([string]$query, [object[]]$params = @(), [switch]$Profile) {
  $body = @{ query = $query; params = $params; profile = [bool]$Profile } | ConvertTo-Json -Depth 10 -Compress
  try { (Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing).Content | ConvertFrom-Json }
  catch { [pscustomobject]@{ values = @(, @("ERROR: " + $(if ($_.ErrorDetails) { ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason } else { $_.Exception.Message }))) } }
}

# Start and end IP of the CIDR string expression $x, as ES|QL expressions.
function len([string]$x) { "TO_INTEGER(MV_LAST(SPLIT($x, `"/`")))" }
function startIp([string]$x) { "IP_PREFIX(TO_IP(MV_FIRST(SPLIT($x, `"/`"))), LEAST($(len $x), 32), $(len $x))" }
function endIp4([string]$x) {
  $o = "TO_LONG(SPLIT(MV_FIRST(SPLIT($x, `"/`")), `".`"))"
  $n = "(MV_SLICE($o, 0, 0) * 16777216 + MV_SLICE($o, 1, 1) * 65536 + MV_SLICE($o, 2, 2) * 256 + MV_SLICE($o, 3, 3))"
  $size = "TO_LONG(POW(2, 32 - $(len $x)))"
  $e = "($n - $n % $size + $size - 1)"
  "TO_IP(CONCAT(TO_STRING($e / 16777216), `".`", TO_STRING($e / 65536 % 256), `".`", TO_STRING($e / 256 % 256), `".`", TO_STRING($e % 256)))"
}

"=== Conversion (ROW)"
foreach ($c in '1.1.1.0/8', '192.168.0.0/16', '172.16.0.0/12', '203.0.113.0/24', '10.1.2.3/32', 'fd00::/8') {
  $j = raw "ROW c = ?c | EVAL start = $(startIp 'c'), end = $(endIp4 'c') | KEEP start, end" @(@{ c = $c })
  "{0,-16} -> {1}" -f $c, ($j.values[0] -join ' .. ')
}

"=== Single select: MV_IN_RANGE(client_ip, start(?c), end(?c))"
$single = "?c IS NULL OR MV_IN_RANGE(client_ip, $(startIp '?c'), $(endIp4 '?c'))"
foreach ($p in @($null, '192.168.0.0/16', @('192.168.0.0/16'), '172.16.0.0/12')) {
  $j = raw "FROM any_demo | WHERE $single | STATS c = COUNT(*)" @(@{ c = $p })
  "c={0,-18} count={1,-6} is_partial={2}" -f ($(if ($null -eq $p) { 'null' } else { "$p" + $(if ($p -is [array]) { ' (array)' } else { '' }) })), $j.values[0][0], $j.is_partial
}
$j = raw "FROM any_demo | WHERE $single | STATS c = COUNT(*)" @(@{ c = '192.168.0.0/16' }) -Profile
"profile: " + ((($j.profile.drivers | ForEach-Object { $_.operators | ForEach-Object { $_.operator } }) | Where-Object { $_ -match 'Lucene|Filter|Eval' } | Select-Object -Unique) -join ' || ')

"=== Multi select: one clause per position, MV_SLICE(?c, i, i) (5 options -> 5 clauses)"
$multi = '?c IS NULL OR ' + ((0..4 | ForEach-Object { $x = "MV_SLICE(?c, $_, $_)"; "MV_IN_RANGE(client_ip, $(startIp $x), $(endIp4 $x))" }) -join ' OR ')
foreach ($p in @($null, @('192.168.0.0/16'), @('192.168.0.0/16', '10.0.0.0/8'), @('172.16.0.0/12', '203.0.113.0/24', '10.0.0.0/8'))) {
  $j = raw "FROM any_demo | WHERE $multi | STATS c = COUNT(*)" @(@{ c = $p })
  "c={0,-48} count={1,-6} is_partial={2}" -f $(if ($null -eq $p) { 'null' } else { $p -join ', ' }), $j.values[0][0], $j.is_partial
}
$j = raw "FROM any_demo | WHERE $multi | STATS c = COUNT(*)" @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') }) -Profile
"profile: " + ((($j.profile.drivers | ForEach-Object { $_.operators | ForEach-Object { $_.operator } }) | Where-Object { $_ -match 'Lucene|Filter|Eval' } | Select-Object -Unique) -join ' || ')
"query length: single=$($single.Length) chars, multi=$($multi.Length) chars"

"=== Multi select, positions guarded with MV_COUNT(?c) > i (folds unused positions away)"
$guarded = '?c IS NULL OR ' + ((0..4 | ForEach-Object { $x = "MV_SLICE(?c, $_, $_)"; "(MV_COUNT(?c) > $_ AND MV_IN_RANGE(client_ip, $(startIp $x), $(endIp4 $x)))" }) -join ' OR ')
foreach ($p in @($null, @('192.168.0.0/16', '10.0.0.0/8'), @('172.16.0.0/12', '203.0.113.0/24', '10.0.0.0/8'))) {
  $j = raw "FROM any_demo | WHERE $guarded | STATS c = COUNT(*)" @(@{ c = $p })
  "c={0,-48} count={1,-6} is_partial={2}" -f $(if ($null -eq $p) { 'null' } else { $p -join ', ' }), $j.values[0][0], $j.is_partial
}
$j = raw "FROM any_demo | WHERE $guarded | STATS c = COUNT(*)" @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') }) -Profile
"profile: " + ((($j.profile.drivers | ForEach-Object { $_.operators | ForEach-Object { $_.operator } }) | Where-Object { $_ -match 'Lucene|Filter|Eval' } | Select-Object -Unique) -join ' || ') -replace '(.{120}).+', '$1...'

"=== Same, with the bounds computed in EVAL (shorter query; foldable EVALs propagate into WHERE)"
$evals = (0..4 | ForEach-Object { "| EVAL c$_ = MV_SLICE(?c, $_, $_)`n| EVAL s$_ = $(startIp "c$_"), e$_ = $(endIp4 "c$_")" }) -join "`n"
$where = '| WHERE ?c IS NULL OR ' + ((0..4 | ForEach-Object { "(MV_COUNT(?c) > $_ AND MV_IN_RANGE(client_ip, s$_, e$_))" }) -join ' OR ')
$q = "FROM any_demo`n$evals`n$where`n| STATS c = COUNT(*)"
$j = raw $q @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') })
"count=$($j.values[0][0]) is_partial=$($j.is_partial)"
$j = raw $q @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') }) -Profile
"profile: " + ((($j.profile.drivers | ForEach-Object { $_.operators | ForEach-Object { $_.operator } }) | Where-Object { $_ -match 'Lucene|Filter|Eval' } | Select-Object -Unique) -join ' || ') -replace '(.{120}).+', '$1...'
"query length: guarded=$($guarded.Length) chars, eval form=$($q.Length) chars"
"reference 172.16/12 + 203.0.113/24 + 10/8: " + (raw 'FROM any_demo METADATA _id | MV_EXPAND client_ip | WHERE CIDR_MATCH(client_ip, "172.16.0.0/12", "203.0.113.0/24", "10.0.0.0/8") | STATS c = COUNT_DISTINCT(_id)').values[0][0]
"reference 172.16/12: " + (raw 'FROM any_demo METADATA _id | MV_EXPAND client_ip | WHERE CIDR_MATCH(client_ip, "172.16.0.0/12") | STATS c = COUNT_DISTINCT(_id)').values[0][0]
