# Does a one-element list behave like a single value? Compares, per predicate, a scalar, a one-element list param,
# a one-element list literal and a folded MV_SLICE, both pushed down (WHERE on the field) and evaluated (EVAL, no pushdown).
$es = 'http://localhost:9200'
function run([string]$query, [object[]]$params = @()) {
  $body = @{ query = $query; params = $params } | ConvertTo-Json -Depth 10 -Compress
  try {
    $j = (Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing).Content | ConvertFrom-Json
    "$($j.values[0][0])" + $(if ($j.is_partial) { ' PARTIAL' } else { '' })
  } catch { 'ERROR: ' + (($_.ErrorDetails.Message | ConvertFrom-Json).error.reason -split "`n")[0] }
}
function case([string]$name, [string]$template, $scalar, [string]$listLiteral) {
  $forms = [ordered]@{
    'scalar ?p'            = @("?p", @(@{ p = $scalar }))
    'list param ?p=[x]'    = @("?p", @(@{ p = @($scalar) }))
    'list literal [x]'     = @($listLiteral, @())
    'MV_SLICE([x, y], 0, 0)' = @("MV_SLICE(?p, 0, 0)", @(@{ p = @($scalar, $scalar) }))
  }
  "=== $name"
  foreach ($f in $forms.Keys) {
    $expr = $template.Replace('$v', $forms[$f][0])
    $pushed = run "FROM any_demo | WHERE $expr | STATS c = COUNT(*)" $forms[$f][1]
    $evaluated = run "FROM any_demo | EVAL m = $expr | STATS c = COUNT(*) WHERE m" $forms[$f][1]
    "  {0,-24} pushed={1,-16} evaluated={2}" -f $f, $pushed, $evaluated
  }
}
case 'CIDR_MATCH(client_ip, $v)' 'MV_COUNT(client_ip) == 1 AND CIDR_MATCH(client_ip, $v)' '192.168.0.0/16' '["192.168.0.0/16"]'
case 'os == $v' 'os == $v' 'linux' '["linux"]'
case 'status == $v' 'status == $v' 404 '[404]'
case 'host IN ($v)' 'host IN ($v)' 'web-01' '["web-01"]'
case 'STARTS_WITH(host, $v)' 'STARTS_WITH(host, $v)' 'web' '["web"]'
case 'bytes > $v' 'bytes > $v' 5000 '[5000]'
case 'MV_GREATER(latency_ms, $v)' 'MV_GREATER(latency_ms, $v)' 500 '[500]'
case 'MV_IN_RANGE(client_ip, TO_IP($v), ...)' 'MV_IN_RANGE(client_ip, TO_IP($v), TO_IP("192.168.255.255"))' '192.168.0.0' '["192.168.0.0"]'
