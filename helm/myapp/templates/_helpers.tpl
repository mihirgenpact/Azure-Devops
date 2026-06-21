{{- define "myapp.fullname" -}}
myapp
{{- end -}}

{{- define "myapp.labels" -}}
app.kubernetes.io/name: myapp
app.kubernetes.io/instance: {{ .Values.env }}
{{- end -}}
