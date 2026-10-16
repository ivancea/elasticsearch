# Isolates CIDR_MATCH with param blocks: scalar vs one-element array vs multi-element array, evaluated (ROW) and pushed down.
$es = 'http://localhost:9200'
function esql([string]$query, [object[]]$params = @(), [switch]$Profile) {
  $body = @{ query = $query; params = $params; profile = [bool]$Profile } | ConvertTo-Json -Depth 10 -Compress
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
    $j = $r.Content | ConvertFrom-Json
    if ($Profile) { return (($j.profile.drivers | ForEach-Object { $_.operators | ForEach-Object { $_.operator } }) | Select-Object -Unique) -join ' || ' }
    $w = @($r.Headers['Warning'] -split '299 Elasticsearch-\S+ ' | Where-Object { $_ -and $_ -notmatch 'No limit defined' })
    "$(($j.values | ForEach-Object { $_ -join ':' }) -join '; ')" + $(if ($w) { '  [warning: ' + ($w -join ' / ') + ']' } else { '' })
  } catch { "ERROR: " + $(if ($_.ErrorDetails) { ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason } else { $_.Exception.Message }) }
}
function p([string]$label, [string]$q, [object[]]$params = @()) { "{0,-58} {1}" -f $label, (esql $q $params) }

$row = 'ROW ip = TO_IP("192.168.1.1") | EVAL m = CIDR_MATCH(ip, ?c) | KEEP m'
p 'ROW, c="192.168.0.0/16" (scalar)' $row @(@{ c = '192.168.0.0/16' })
p 'ROW, c=["192.168.0.0/16"]' $row @(@{ c = @('192.168.0.0/16') })
p 'ROW, c=["192.168.0.0/16", "10.0.0.0/8"]' $row @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') })
p 'ROW, c=["10.0.0.0/8", "192.168.0.0/16"]' $row @(@{ c = @('10.0.0.0/8', '192.168.0.0/16') })
p 'ROW, MV_SLICE(c,1,1), c=[10/8, 192.168/16]' 'ROW ip = TO_IP("192.168.1.1") | EVAL m = CIDR_MATCH(ip, MV_SLICE(?c, 1, 1)) | KEEP m' @(@{ c = @('10.0.0.0/8', '192.168.0.0/16') })

$idx = 'FROM any_demo | WHERE MV_COUNT(client_ip) == 1 | EVAL m = CIDR_MATCH(client_ip, ?c) | STATS t = COUNT(*) WHERE m, f = COUNT(*) WHERE NOT m, n = COUNT(*) WHERE m IS NULL'
p 'index EVAL (no pushdown), c=scalar' $idx @(@{ c = '192.168.0.0/16' })
p 'index EVAL (no pushdown), c=[one]' $idx @(@{ c = @('192.168.0.0/16') })
p 'index EVAL (no pushdown), c=[two]' $idx @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') })

$w = 'FROM any_demo | WHERE CIDR_MATCH(client_ip, ?c) | STATS c = COUNT(*)'
p 'index WHERE (pushdown), c=scalar' $w @(@{ c = '192.168.0.0/16' })
p 'index WHERE (pushdown), c=[one]' $w @(@{ c = @('192.168.0.0/16') })
p 'index WHERE (pushdown), literal "192.168.0.0/16"' 'FROM any_demo | WHERE CIDR_MATCH(client_ip, "192.168.0.0/16") | STATS c = COUNT(*)'
p 'index WHERE (pushdown), literal 2 blocks' 'FROM any_demo | WHERE CIDR_MATCH(client_ip, "192.168.0.0/16", "10.0.0.0/8") | STATS c = COUNT(*)'
"profile scalar: " + (esql $w @(@{ c = '192.168.0.0/16' }) -Profile)
"profile [one]:  " + (esql $w @(@{ c = @('192.168.0.0/16') }) -Profile)
"profile [two]:  " + (esql $w @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') }) -Profile)
