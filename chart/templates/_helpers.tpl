{{/*
Expand the name of the chart.
*/}}
{{- define "phaeton.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "phaeton.fullname" -}}
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

{{/*
Create chart label.
*/}}
{{- define "phaeton.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "phaeton.labels" -}}
helm.sh/chart: {{ include "phaeton.chart" . }}
{{ include "phaeton.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "phaeton.selectorLabels" -}}
app.kubernetes.io/name: {{ include "phaeton.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the secret holding SECRET_KEY_BASE.
*/}}
{{- define "phaeton.secretName" -}}
{{- if .Values.secret.existingSecret }}
{{- .Values.secret.existingSecret }}
{{- else }}
{{- include "phaeton.fullname" . }}
{{- end }}
{{- end }}

{{/*
Key inside the secret for SECRET_KEY_BASE.
*/}}
{{- define "phaeton.secretKey" -}}
{{- if .Values.secret.existingSecret }}
{{- .Values.secret.existingSecretKey }}
{{- else }}
secret-key-base
{{- end }}
{{- end }}

{{/*
Image reference.
*/}}
{{- define "phaeton.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}
