{{- /*
Opt-in profile for a test deployment of the beamline (issue #3).

When testBeamline.enabled is true and uid and gid are set,
t11.testBeamline.apply adds these values to the valuesObject of every
service:
  - securityContextPaths: runAsUser and runAsGroup
  - podSecurityContextPaths: runAsUser, runAsGroup and fsGroup

fsGroup is only valid at Pod level. It makes shared volumes writable by the
test gid when a storage driver has already given them another group, e.g.
the production account.

The root app cannot read the service values, so the lists name the paths
where the service charts pin the production account. A chart ignores a path
for a subchart it does not have. A valuesObject that the user sets for a
service wins over these values.
*/ -}}
{{- define "t11.testBeamline.apply" -}}
{{- $tb := default dict .Values.testBeamline -}}
{{- if and $tb.enabled (or $tb.uid $tb.gid) -}}
{{- if not (and $tb.uid $tb.gid) -}}
{{- fail "testBeamline.uid and testBeamline.gid must be set together" -}}
{{- end -}}
{{- $container := dict "runAsUser" (int64 $tb.uid) "runAsGroup" (int64 $tb.gid) -}}
{{- $pod := merge (dict "fsGroup" (int64 $tb.gid)) $container -}}

{{- /* turn each dotted path into nested values, e.g. a.b -> {a: {b: context}} */ -}}
{{- $overrides := dict -}}
{{- range $entry := list (list $tb.securityContextPaths $container) (list $tb.podSecurityContextPaths $pod) -}}
{{- $context := index $entry 1 -}}
{{- range $path := index $entry 0 -}}
{{- $node := deepCopy $context -}}
{{- range $key := splitList "." $path | reverse -}}
{{- $node = dict $key $node -}}
{{- end -}}
{{- $overrides = mergeOverwrite $overrides $node -}}
{{- end -}}
{{- end -}}

{{- $services := default dict .Values.services -}}
{{- range $service, $settings := $services -}}
{{- $settings = default dict $settings -}}
{{- $valuesObject := merge (deepCopy (default dict $settings.valuesObject)) (deepCopy $overrides) -}}
{{- $_ := set $settings "valuesObject" $valuesObject -}}
{{- $_ := set $services $service $settings -}}
{{- end -}}
{{- end -}}
{{- end -}}
