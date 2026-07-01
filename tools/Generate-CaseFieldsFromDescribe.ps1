param(
  [string]$UatFields = 'reports/case-fields-uat.json',
  [string]$ScratchFields = 'reports/case-fields-scratch.json',
  [string]$OutDir = 'force-app/main/default/objects/Case/fields'
)

function Normalize-FieldName([string]$name) {
  $target = $name
  if ($target.StartsWith('SVMXC__')) { $target = $target.Substring(7) }
  elseif ($target.StartsWith('SVMX_')) { $target = $target.Substring(5) }
  elseif ($target -match '^[A-Za-z][A-Za-z0-9]*__(.+__c)$') {
    $target = ($target -replace '__', '_')
  }
  if ($target -match '^[0-9]') { $target = 'F_' + $target }
  return $target
}

function Escape-Xml([object]$value) {
  if ($null -eq $value) { return '' }
  return [System.Security.SecurityElement]::Escape([string]$value)
}

function Add-Line([System.Collections.Generic.List[string]]$lines, [int]$indent, [string]$text) {
  $lines.Add((' ' * $indent) + $text) | Out-Null
}

function Metadata-Type($field) {
  switch ($field.type) {
    'boolean' { return 'Checkbox' }
    'currency' { return 'Currency' }
    'date' { return 'Date' }
    'datetime' { return 'DateTime' }
    'double' { return 'Number' }
    'email' { return 'Email' }
    'multipicklist' { return 'MultiselectPicklist' }
    'picklist' { return 'Picklist' }
    'reference' { return 'Text' }
    'string' { return 'Text' }
    'textarea' {
      if ($field.extraTypeInfo -eq 'richtextarea' -or $field.htmlFormatted) { return 'Html' }
      if ([int]$field.length -gt 255) { return 'LongTextArea' }
      return 'TextArea'
    }
    'url' { return 'Url' }
    default { return 'Text' }
  }
}

function Make-FieldXml($field, [string]$targetName) {
  $type = Metadata-Type $field
  $lines = [System.Collections.Generic.List[string]]::new()
  Add-Line $lines 0 '<?xml version="1.0" encoding="UTF-8"?>'
  Add-Line $lines 0 '<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">'
  Add-Line $lines 4 "<fullName>$(Escape-Xml $targetName)</fullName>"
  Add-Line $lines 4 "<label>$(Escape-Xml $field.label)</label>"
  if ($field.inlineHelpText) { Add-Line $lines 4 "<inlineHelpText>$(Escape-Xml $field.inlineHelpText)</inlineHelpText>" }
  Add-Line $lines 4 "<type>$type</type>"

  switch ($type) {
    'Checkbox' {
      $default = if ($null -ne $field.defaultValue) { ([string]$field.defaultValue).ToLowerInvariant() } else { 'false' }
      Add-Line $lines 4 "<defaultValue>$default</defaultValue>"
    }
    'Currency' {
      Add-Line $lines 4 "<precision>$([int]$field.precision)</precision>"
      Add-Line $lines 4 "<scale>$([int]$field.scale)</scale>"
    }
    'Number' {
      Add-Line $lines 4 "<precision>$([int]$field.precision)</precision>"
      Add-Line $lines 4 "<scale>$([int]$field.scale)</scale>"
    }
    'Text' {
      $length = if ($field.type -eq 'reference') { 18 } elseif ([int]$field.length -gt 0) { [Math]::Min([int]$field.length, 255) } else { 255 }
      Add-Line $lines 4 "<length>$length</length>"
      if ($field.externalId) { Add-Line $lines 4 '<externalId>true</externalId>' }
      if ($field.unique) {
        Add-Line $lines 4 '<unique>true</unique>'
        Add-Line $lines 4 "<caseSensitive>$(([string]$field.caseSensitive).ToLowerInvariant())</caseSensitive>"
      }
    }
    'LongTextArea' {
      $length = if ([int]$field.length -gt 0) { [int]$field.length } else { 32768 }
      Add-Line $lines 4 "<length>$length</length>"
      Add-Line $lines 4 '<visibleLines>10</visibleLines>'
    }
    'Html' {
      $length = if ([int]$field.length -gt 0) { [int]$field.length } else { 32768 }
      Add-Line $lines 4 "<length>$length</length>"
      Add-Line $lines 4 '<visibleLines>15</visibleLines>'
    }
    'Picklist' {
      Add-Line $lines 4 '<valueSet>'
      Add-Line $lines 8 '<restricted>false</restricted>'
      Add-Line $lines 8 '<valueSetDefinition>'
      Add-Line $lines 12 '<sorted>false</sorted>'
      foreach ($pv in @($field.picklistValues | Where-Object { -not $_.active -eq $false })) {
        Add-Line $lines 12 '<value>'
        Add-Line $lines 16 ('<fullName>' + (Escape-Xml $pv.value) + '</fullName>')
        Add-Line $lines 16 ('<default>' + ([string]$pv.defaultValue).ToLowerInvariant() + '</default>')
        Add-Line $lines 16 ('<label>' + (Escape-Xml $pv.label) + '</label>')
        Add-Line $lines 12 '</value>'
      }
      Add-Line $lines 8 '</valueSetDefinition>'
      Add-Line $lines 4 '</valueSet>'
    }
    'MultiselectPicklist' {
      Add-Line $lines 4 '<visibleLines>4</visibleLines>'
      Add-Line $lines 4 '<valueSet>'
      Add-Line $lines 8 '<restricted>false</restricted>'
      Add-Line $lines 8 '<valueSetDefinition>'
      Add-Line $lines 12 '<sorted>false</sorted>'
      foreach ($pv in @($field.picklistValues | Where-Object { -not $_.active -eq $false })) {
        Add-Line $lines 12 '<value>'
        Add-Line $lines 16 ('<fullName>' + (Escape-Xml $pv.value) + '</fullName>')
        Add-Line $lines 16 ('<default>' + ([string]$pv.defaultValue).ToLowerInvariant() + '</default>')
        Add-Line $lines 16 ('<label>' + (Escape-Xml $pv.label) + '</label>')
        Add-Line $lines 12 '</value>'
      }
      Add-Line $lines 8 '</valueSetDefinition>'
      Add-Line $lines 4 '</valueSet>'
    }
  }

  Add-Line $lines 0 '</CustomField>'
  return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

$uat = Get-Content $UatFields -Raw | ConvertFrom-Json
$scratch = Get-Content $ScratchFields -Raw | ConvertFrom-Json
$scratchNames = @{}
foreach ($field in $scratch) { $scratchNames[(Normalize-FieldName $field.name)] = $true }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$written = @()
foreach ($field in $uat) {
  if (-not $field.custom) { continue }
  if ($field.name.StartsWith('logmein__') -or $field.name.StartsWith('inov8__')) { continue }
  $targetName = Normalize-FieldName $field.name
  if ($scratchNames.ContainsKey($targetName)) { continue }
  $xml = Make-FieldXml $field $targetName
  $path = Join-Path $OutDir ($targetName + '.field-meta.xml')
  Set-Content -Path $path -Value $xml -Encoding UTF8
  $written += [pscustomobject]@{ source = $field.name; target = $targetName; sourceType = $field.type; metadataType = (Metadata-Type $field); label = $field.label }
}
$written | ConvertTo-Csv -NoTypeInformation | Set-Content -Path reports/case-generated-fields.csv -Encoding UTF8
Write-Output "GENERATED=$($written.Count)"
