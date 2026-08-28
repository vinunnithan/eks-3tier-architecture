{{- define "database.fullname" -}}
{{ .Release.Name }}-database
{{- end -}}

{{- define "database.labels" -}}
app.kubernetes.io/name: database
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "database.selectorLabels" -}}
app.kubernetes.io/name: database
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}