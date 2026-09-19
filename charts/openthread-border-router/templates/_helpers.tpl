{{/* Expand the chart name. */}}
{{- define "openthread-border-router.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a fully qualified application name. */}}
{{- define "openthread-border-router.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Chart label. */}}
{{- define "openthread-border-router.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels. */}}
{{- define "openthread-border-router.labels" -}}
helm.sh/chart: {{ include "openthread-border-router.chart" . }}
{{ include "openthread-border-router.selectorLabels" . }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Stable selector labels. */}}
{{- define "openthread-border-router.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openthread-border-router.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Service account name. */}}
{{- define "openthread-border-router.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "openthread-border-router.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Container image reference. */}}
{{- define "openthread-border-router.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/* PVC name. */}}
{{- define "openthread-border-router.pvcName" -}}
{{- default (include "openthread-border-router.fullname" .) .Values.persistence.existingClaim }}
{{- end }}

{{/* Radio URL, generated from the mounted serial path unless explicitly set. */}}
{{- define "openthread-border-router.rcpUrl" -}}
{{- if .Values.config.rcp.url }}
{{- .Values.config.rcp.url }}
{{- else }}
{{- printf "spinel+hdlc+uart://%s?uart-baudrate=%d" .Values.config.rcp.device.containerPath (int64 .Values.config.rcp.baudrate) }}
{{- end }}
{{- end }}
