{{- /*
Opt-in profile for a test deployment of the beamline (issue #3).

When testBeamline.enabled is true and uid and gid are set,
t11.testBeamline.apply sets runAsUser and runAsGroup at every path in
testBeamline.securityContextPaths, in the valuesObject of every service. The
root app cannot read the service values, so the list names the paths where
the service charts pin the production account. A chart ignores a path for a
subchart it does not have. A valuesObject that the user sets for a service
wins over these values.
*/ -}}
{{- define "t11.testBeamline.apply" -}}
{{- $tb := default dict .Values.testBeamline -}}
{{- if and $tb.enabled (or $tb.uid $tb.gid) -}}
{{- if not (and $tb.uid $tb.gid) -}}
{{- fail "testBeamline.uid and testBeamline.gid must be set together" -}}
{{- end -}}
{{- $identity := dict "runAsUser" (int64 $tb.uid) "runAsGroup" (int64 $tb.gid) -}}

{{- /* turn each dotted path into nested values, e.g. a.b -> {a: {b: identity}} */ -}}
{{- $overrides := dict -}}
{{- range $path := $tb.securityContextPaths -}}
{{- $node := deepCopy $identity -}}
{{- range $key := splitList "." $path | reverse -}}
{{- $node = dict $key $node -}}
{{- end -}}
{{- $overrides = mergeOverwrite $overrides $node -}}
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
