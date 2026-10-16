# CIDR with a multi-select control using only existing functions: one MV_CONTAINS + MV_IN_RANGE clause per static option.
# Also shows that the CIDR_MATCH pushdown failure is reported as a partial result.
$es = 'http://localhost:9200'
function raw([string]$query, [object[]]$params = @()) {
  $body = @{ query = $query; params = $params } | ConvertTo-Json -Depth 10 -Compress
  try { (Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing).Content | ConvertFrom-Json }
  catch { [pscustomobject]@{ values = @(, @("ERROR: " + $(if ($_.ErrorDetails) { ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason } else { $_.Exception.Message }))) } }
}
function p([string]$label, [string]$where, [object[]]$params = @()) {
  $j = raw "FROM any_demo | WHERE $where | STATS c = COUNT(*)" $params
  "{0,-48} {1,-6} is_partial={2}" -f $label, $j.values[0][0], $j.is_partial
}

p 'CIDR_MATCH(client_ip, ?c), c=[192.168/16]' 'CIDR_MATCH(client_ip, ?c)' @(@{ c = @('192.168.0.0/16') })

$ranges = [ordered]@{
  '192.168.0.0/16' = @('192.168.0.0', '192.168.255.255')
  '10.0.0.0/8'     = @('10.0.0.0', '10.255.255.255')
  '172.16.0.0/12'  = @('172.16.0.0', '172.31.255.255')
  '203.0.113.0/24' = @('203.0.113.0', '203.0.113.255')
  'fd00::/8'       = @('fd00::', 'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
}
$clauses = $ranges.Keys | ForEach-Object { "(MV_CONTAINS(?c, `"$_`") AND MV_IN_RANGE(client_ip, TO_IP(`"$($ranges[$_][0])`"), TO_IP(`"$($ranges[$_][1])`")))" }
$wa = '?c IS NULL OR ' + ($clauses -join ' OR ')
p 'workaround, c=null (Any)' $wa @(@{ c = $null })
p 'workaround, c=[192.168/16]' $wa @(@{ c = @('192.168.0.0/16') })
p 'workaround, c=[192.168/16, 10/8]' $wa @(@{ c = @('192.168.0.0/16', '10.0.0.0/8') })
p 'workaround, c=[fd00::/8]' $wa @(@{ c = @('fd00::/8') })
"reference (MV_EXPAND) 192.168/16 + 10/8: " + (raw 'FROM any_demo METADATA _id | MV_EXPAND client_ip | WHERE CIDR_MATCH(client_ip, "192.168.0.0/16", "10.0.0.0/8") | STATS c = COUNT_DISTINCT(_id)').values[0][0]
