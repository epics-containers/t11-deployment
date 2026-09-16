{{- /*
Opt-in profile for a test deployment of the beamline (issue #3).

When testBeamline.enabled is true, t11.testBeamline.applyProfiles adds
test-only values to services.<name>.valuesObject before the upstream
argocd-apps template renders the child Applications. The service charts
do not change.

testBeamline.serviceProfiles maps each service to a profile. Each profile is
a named template below that knows where its chart keeps the settings. A
valuesObject that the user sets for a service wins over the profile values.
*/ -}}

{{- define "t11.testBeamline.applyProfiles" -}}
{{- $tb := default dict .Values.testBeamline -}}
{{- if $tb.enabled -}}
{{- if and (or $tb.uid $tb.gid) (not (and $tb.uid $tb.gid)) -}}
{{- fail "testBeamline.uid and testBeamline.gid must be set together" -}}
{{- end -}}
{{- $services := default dict .Values.services -}}
{{- range $service, $profile := default dict $tb.serviceProfiles -}}
{{- if hasKey $services $service -}}
{{- $settings := default dict (get $services $service) -}}
{{- $profileValues := include (printf "t11.testBeamline.profile.%s" $profile) $tb | fromYaml -}}
{{- if hasKey $profileValues "Error" -}}
{{- fail (printf "testBeamline profile %s: %s" $profile $profileValues.Error) -}}
{{- end -}}
{{- /* a profile with nothing to set renders as "<chart>: null" */ -}}
{{- range $chart, $chartValues := $profileValues -}}
{{- if not $chartValues -}}
{{- $profileValues = omit $profileValues $chart -}}
{{- end -}}
{{- end -}}
{{- $valuesObject := merge (deepCopy (default dict $settings.valuesObject)) $profileValues -}}
{{- if $valuesObject -}}
{{- $_ := set $settings "valuesObject" $valuesObject -}}
{{- $_ := set $services $service $settings -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- /* Pod-level runAsUser, runAsGroup and fsGroup */ -}}
{{- define "t11.testBeamline.podSecurityContext" -}}
{{- if .uid }}
runAsUser: {{ int64 .uid }}
runAsGroup: {{ int64 .gid }}
fsGroup: {{ int64 .gid }}
{{- end }}
{{- end -}}

{{- /* Container-level runAsUser and runAsGroup */ -}}
{{- define "t11.testBeamline.containerSecurityContext" -}}
{{- if .uid }}
runAsUser: {{ int64 .uid }}
runAsGroup: {{ int64 .gid }}
{{- end }}
{{- end -}}

{{- /* nodeSelector expressed as a required node affinity */ -}}
{{- define "t11.testBeamline.nodeAffinity" -}}
{{- with .nodeSelector }}
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          {{- range $key, $value := . }}
          - key: {{ $key | quote }}
            operator: In
            values:
              - {{ $value | quote }}
          {{- end }}
{{- end }}
{{- end -}}

{{- /* nodeSelector and tolerations, for charts that expose both */ -}}
{{- define "t11.testBeamline.scheduling" -}}
{{- with .nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{- /* IOCs that use the ioc-instance chart */ -}}
{{- define "t11.testBeamline.profile.ioc-instance" -}}
ioc-instance:
  {{- with include "t11.testBeamline.podSecurityContext" . }}
  podSecurityContext:
    {{- . | nindent 4 }}
  {{- end }}
  {{- with include "t11.testBeamline.containerSecurityContext" . }}
  securityContext:
    {{- . | nindent 4 }}
  {{- end }}
  {{- include "t11.testBeamline.scheduling" . | nindent 2 }}
{{- end -}}

{{- /*
The epics-gateways chart sets securityContext at Pod level and has no
nodeSelector value, so the profile uses node affinity instead.
*/ -}}
{{- define "t11.testBeamline.profile.epics-gateways" -}}
epics-gateways:
  {{- with include "t11.testBeamline.podSecurityContext" . }}
  securityContext:
    {{- . | nindent 4 }}
  {{- end }}
  {{- with .tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with include "t11.testBeamline.nodeAffinity" . }}
  affinity:
    {{- . | nindent 4 }}
  {{- end }}
{{- end -}}

{{- /*
The blueapi chart runs as uid 1000. Any other runAsUser switches the chart to
a DLS debug mode with an LDAP account-sync sidecar, so the profile does not
change the uid.
*/ -}}
{{- define "t11.testBeamline.profile.blueapi" -}}
blueapi:
  {{- include "t11.testBeamline.scheduling" . | nindent 2 }}
{{- end -}}

{{- define "t11.testBeamline.profile.numtracker" -}}
numtracker:
  {{- include "t11.testBeamline.scheduling" . | nindent 2 }}
{{- end -}}
