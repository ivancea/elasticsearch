# "Greater than" (MV_GREATER) and CIDR_MATCH with "Any", on local any_demo, with the params Kibana sends:
# static numeric options arrive as JSON numbers (integer params), static CIDR options as a string array.
$es = 'http://localhost:9200'
function esql([string]$query, [object[]]$params = @(), [switch]$Profile) {
  $body = @{ query = $query; params = $params; profile = [bool]$Profile } | ConvertTo-Json -Depth 10 -Compress
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    $j = $r.Content | ConvertFrom-Json
    if ($Profile) {
      $ops = $j.profile.drivers | ForEach-Object { $_.operators | ForEach-Object { $_.operator } } | Where-Object { $_ -match 'Lucene|Filter' }
      return ($ops | Select-Object -Unique) -join ' || '
    }
    $w = $r.Headers['Warning']
    $v = "$($j.values[0][0])"
    if ($w) { $v += '  [warning: ' + (($w -split ', 299')[0] -replace '^299 Elasticsearch-\S+ ', '') + ']' }
    $v
  } catch { "ERROR: " + $(if ($_.ErrorDetails) { ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason } else { $_.Exception.Message }) }
}
function count([string]$label, [string]$where, [object[]]$params = @()) {
  "{0,-62} {1}" -f $label, (esql "FROM any_demo | WHERE $where | STATS c = COUNT(*)" $params)
}

"=== Greater than: bytes (long, single value)"
count 'reference: bytes > 5000' 'bytes > 5000'
count 'bytes > ?v  (v=5000)' 'bytes > ?v' @(@{ v = 5000 })
count 'MV_GREATER(bytes, ?v)  (integer param on long field)' 'MV_GREATER(bytes, ?v)' @(@{ v = 5000 })
count 'MV_GREATER(bytes, TO_LONG(?v))' 'MV_GREATER(bytes, TO_LONG(?v))' @(@{ v = 5000 })
count 'Any: ?v IS NULL OR MV_GREATER(bytes, TO_LONG(?v))  (v=null)' '?v IS NULL OR MV_GREATER(bytes, TO_LONG(?v))' @(@{ v = $null })
count 'IN_RANGE_SELECTION(bytes, ?v, null)  (>=)' 'IN_RANGE_SELECTION(bytes, ?v, null)' @(@{ v = 5000 })
count 'reference: bytes >= 5000' 'bytes >= 5000'

"=== Greater than: latency_ms (integer, multivalue)"
count 'reference: MV_MAX(latency_ms) > 500  (any value > 500)' 'MV_MAX(latency_ms) > 500'
count 'latency_ms > ?v  (plain operator on multivalue)' 'latency_ms > ?v' @(@{ v = 500 })
count 'MV_GREATER(latency_ms, ?v)' 'MV_GREATER(latency_ms, ?v)' @(@{ v = 500 })
count 'Any: ?v IS NULL OR MV_GREATER(latency_ms, ?v)  (v=null)' '?v IS NULL OR MV_GREATER(latency_ms, ?v)' @(@{ v = $null })
count 'MV_GREATER(latency_ms, ?v)  (v=null, no Any guard)' 'MV_GREATER(latency_ms, ?v)' @(@{ v = $null })
count 'MV_GREATER(latency_ms, ?v)  (v=500.5, double param)' 'MV_GREATER(latency_ms, ?v)' @(@{ v = 500.5 })
count 'IN_RANGE_SELECTION(latency_ms, ?v, null)  (>=)' 'IN_RANGE_SELECTION(latency_ms, ?v, null)' @(@{ v = 500 })
count 'reference: MV_MAX(latency_ms) >= 500' 'MV_MAX(latency_ms) >= 500'
count 'docs with some latency <= 500 but matching > 500' 'MV_GREATER(latency_ms, 500) AND MV_MIN(latency_ms) <= 500'

"=== Greater than: pushdown (profile operators)"
"single, set:  " + (esql 'FROM any_demo | WHERE ?v IS NULL OR MV_GREATER(bytes, TO_LONG(?v)) | STATS c = COUNT(*)' @(@{ v = 5000 }) -Profile)
"multi, set:   " + (esql 'FROM any_demo | WHERE ?v IS NULL OR MV_GREATER(latency_ms, ?v) | STATS c = COUNT(*)' @(@{ v = 500 }) -Profile)
"multi, Any:   " + (esql 'FROM any_demo | WHERE ?v IS NULL OR MV_GREATER(latency_ms, ?v) | STATS c = COUNT(*)' @(@{ v = $null }) -Profile)

"=== CIDR_MATCH: client_ip (ip, multivalue), multi-select blocks"
$ref = { param($blocks) "FROM any_demo METADATA _id | MV_EXPAND client_ip | WHERE CIDR_MATCH(client_ip, $blocks) | STATS c = COUNT_DISTINCT(_id)" }
"{0,-62} {1}" -f 'reference (MV_EXPAND): any ip in 192.168/16', (esql (& $ref '"192.168.0.0/16"'))
"{0,-62} {1}" -f 'reference (MV_EXPAND): any ip in 192.168/16 or 10/8', (esql (& $ref '"192.168.0.0/16", "10.0.0.0/8"'))
"{0,-62} {1}" -f 'reference (MV_EXPAND): any ip in fd00::/8', (esql (& $ref '"fd00::/8"'))
count 'CIDR_MATCH(client_ip, ?c)  (c=[192.168/16])' 'CIDR_MATCH(client_ip, ?c)' @(@{ c = @('192.168.0.0/16') })
count 'CIDR_MATCH(client_ip, ?c)  (c=[192.168/16, 10/8])' 'CIDR_MATCH(client_ip, ?c)' @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') })
count 'CIDR_MATCH(client_ip, ?c)  (c=[fd00::/8])' 'CIDR_MATCH(client_ip, ?c)' @(@{ c = @('fd00::/8') })
count 'Any: ?c IS NULL OR CIDR_MATCH(client_ip, ?c)  (c=null)' '?c IS NULL OR CIDR_MATCH(client_ip, ?c)' @(@{ c = $null })
count 'single-value ips only: CIDR_MATCH, c=[192.168/16]' 'MV_COUNT(client_ip) == 1 AND CIDR_MATCH(client_ip, ?c)' @(@{ c = @('192.168.0.0/16') })
"{0,-62} {1}" -f 'reference (single-value ips only): 192.168/16', (esql 'FROM any_demo | WHERE MV_COUNT(client_ip) == 1 | WHERE CIDR_MATCH(client_ip, "192.168.0.0/16") | STATS c = COUNT(*)')

$chain = '?c IS NULL OR CIDR_MATCH(client_ip, MV_SLICE(?c, 0, 0)) OR CIDR_MATCH(client_ip, MV_SLICE(?c, 1, 1)) OR CIDR_MATCH(client_ip, MV_SLICE(?c, 2, 2))'
count 'OR chain of MV_SLICE  (c=[192.168/16])' $chain @(@{ c = @('192.168.0.0/16') })
count 'OR chain of MV_SLICE  (c=[192.168/16, 10/8])' $chain @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') })
count 'OR chain of MV_SLICE  (c=null)' $chain @(@{ c = $null })
"chain, set:   " + (esql "FROM any_demo | WHERE $chain | STATS c = COUNT(*)" @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') }) -Profile)
"direct, set:  " + (esql 'FROM any_demo | WHERE ?c IS NULL OR CIDR_MATCH(client_ip, ?c) | STATS c = COUNT(*)' @(@{ c = @('192.168.0.0/16') }) -Profile)

"=== Multivalue ips via ranges (existing MV_IN_RANGE, bounds hard-coded per block)"
count 'MV_IN_RANGE(client_ip, 192.168.0.0, 192.168.255.255)' 'MV_IN_RANGE(client_ip, TO_IP("192.168.0.0"), TO_IP("192.168.255.255"))'
