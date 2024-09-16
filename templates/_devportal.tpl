{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "devportal.fullname" -}}
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
Create the name of the service account to use
*/}}

{{- define "devportal.serviceAccountName" -}}
{{ .Values.serviceAccount.name | default "devportal" }}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}

{{- define "devportal.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
Common labels
*/}}

{{- define "devportal.labels" -}}
helm.sh/chart: {{ include "devportal.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{*
   ------ Devportal configs and secrets ------
*}

{{/* Helper to return devportal.conf name */}}
{{- define "devportal.config.name" -}}
{{ template "devportal.fullname" . }}-conf
{{- end -}}

{*
   ------ APIGW ------
*}

{{/* ENV variables */}}
{{- define "apigw.env" -}}
- name: CONTROL_PLANE_IP
  value: {{ .Values.apigw.controlPlane.host | default "127.0.0.1" }}
- name: INSTANCE_GROUP
  value: {{ .Values.apigw.controlPlane.instanceGroup | default "test" }}
{{- end }}

{{/* ENV variables */}}
{{- define "apigw.name" -}}
{{ .Values.apigw.name | default "apigw" }}
{{- end }}

{{/* Helper to return apigw http port */}}
{{- define "apigw.containerHttpPort" -}}
{{ .Values.apigw.container.port }}
{{- end -}}

{{/* Helper to return apigw http port */}}
{{- define "apigw.serviceHttpPort" -}}
{{ .Values.apigw.service.port }}
{{- end -}}

{{- define "apigw.selectorLabels" -}}
app.kubernetes.io/name: {{ template "apigw.name" . }}
{{- end }}

{*
   ------ API ------
*}

{{- define "api.name" -}}
{{ .Values.api.name | default "api" }}
{{- end }}

{{/* Helper function to return api db certs mount path */}}
{{- define "devportal.api.certs.mountPath" -}}
/etc/nginx-devportal/ssl
{{- end -}}

{{/* Helper function to return postgresql certs mount path */}}
{{- define "devportal.postgres.certs.mountPath" -}}
/etc/ssl/postgresql
{{- end -}}

{{/*
Generates self signed CA and client/server certificates for postgres
*/}}
{{- define "devportal.gen-postgres-certs" -}}
{{- $ca := . }}
{{- $subjectName := "postgres" }}
{{- $ca = genCA (include "devportal.fullname" .) 36600 -}}
{{- $altNames := (list $subjectName (printf "%s.%s.svc" $subjectName .Release.Namespace ) (printf "%s.%s.svc.cluster.local" $subjectName .Release.Namespace )) -}}
{{- $ips := (list "0.0.0.0" "127.0.0.1") -}}
{{- $serverCert := genSignedCert ( printf "%s.%s" $subjectName .Release.Namespace ) $ips $altNames 36600 $ca -}}
{{- $clientCert := genSignedCert .Values.api.db.user nil nil 36600 $ca -}}
ca.crt: {{ $ca.Cert | b64enc }}
server.crt: {{ $serverCert.Cert | b64enc }}
server.key: {{ $serverCert.Key | b64enc }}
tls.crt: {{ $clientCert.Cert | b64enc }}
tls.key: {{ $clientCert.Key | b64enc }}
{{- end -}}

{{- define "api.db.tlsSecretName" -}}
{{- if eq .Values.api.db.type "psql" }}
{{- if .Values.api.db.external }}
{{- if .Values.api.db.tls.secretName }}
{{- .Values.api.db.tls.secretName }}
{{- end -}}
{{- else -}}
db-certs
{{- end -}}
{{- end -}}
{{- end -}}

{{/* ENV variables */}}
{{- define "api.env" -}}
- name: LOG_LEVEL
  value: {{ .Values.api.logLevel | default "info" }}
- name: DB_TYPE
  value: {{ template "api.dbType" . }}
- name: DB_NAME
  value: {{ template "api.dbName" . }}
{{- if eq .Values.api.db.type "psql" }}
- name: DB_HOST
  value: {{ template "api.dbHost" . }}
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: username
      optional: false
- name: DB_PASS
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: password
      optional: false
{{- if not .Values.api.db.external }}
- name: DB_TLS_CA_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/db/ca.crt
- name: DB_TLS_MODE
  value: {{ .Values.api.db.tls.verifyMode }}
- name: DB_TLS_CERT_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/db/tls.crt
- name: DB_TLS_KEY_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/db/tls.key
{{- else if (include "api.db.tlsSecretName" .) }}
{{- $dbCertSecret := (lookup "v1" "Secret" .Release.Namespace (include "api.db.tlsSecretName" .)) -}}
{{- if and (hasKey $dbCertSecret "data") (hasKey $dbCertSecret.data "ca.crt") }}
- name: DB_TLS_CA_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/db/ca.crt
{{- else }}
{{- fail "A valid .Values.api.db.tls.secretName Secret must contain a ca.crt!" -}}
{{- end }}
- name: DB_TLS_MODE
  value: {{ .Values.api.db.tls.verifyMode }}
{{- if and (hasKey $dbCertSecret "data") (hasKey $dbCertSecret.data "tls.crt") (hasKey $dbCertSecret.data "tls.key") }}
- name: DB_TLS_CERT_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/db/tls.crt
- name: DB_TLS_KEY_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/db/tls.key
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.api.tls.secretName }}
- name: CA_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/ca.crt
- name: CERT_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/tls.crt
- name: INSECURE_MODE
  value: {{ "false" | quote }}
- name: KEY_FILE
  value: {{ template "devportal.api.certs.mountPath" . -}}/tls.key
{{- if .Values.api.tls.clientValidation }}
- name: CLIENT_VERIFY
  value: {{ .Values.api.tls.clientValidation | quote -}}
{{- end }}
{{- if .Values.api.tls.clientNames }}
- name: CLIENT_NAMES
  value: {{ .Values.api.tls.clientNames -}}
{{- end }}
{{- end }}
- name: LOG_TIMESTAMP
  value: {{ "1" | quote -}}
{{ if and .Values.api.acm.client.caSecret.name .Values.api.acm.client.caSecret.key }}
- name: SSL_CERT_DIR
  value: "/etc/ssl/certs/"
{{- end }}
{{- end }}

{{- define "api.db.env" -}}
- name: POSTGRES_DB
  value: {{ template "api.dbName" . }}
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: username
      optional: false
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: password
      optional: false
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: password
      optional: false
{{- if and (not .Values.api.db.external) (eq .Values.api.db.type "psql") }}
- name: POSTGRES_TLS_CA
  value: {{ template "devportal.postgres.certs.mountPath" . -}}/ca.crt
- name: POSTGRES_TLS_CERT
  value: {{ template "devportal.postgres.certs.mountPath" . -}}/server.crt
- name: POSTGRES_TLS_KEY
  value: {{ template "devportal.postgres.certs.mountPath" . -}}/server.key
{{- end }}
{{- end }}

{{- define "api.db.selectorLabels" -}}
name: postgres
{{- end }}

{{/* Helper to return api http port */}}
{{- define "api.containerHttpPort" -}}
{{ .Values.api.container.port }}
{{- end -}}

{{/* Helper to return apigw http port */}}
{{- define "api.serviceHttpPort" -}}
{{ .Values.api.service.port }}
{{- end -}}

{{- define "api.selectorLabels" -}}
app.kubernetes.io/name: {{ template "api.name" . }}
{{- end }}

{{- define "api.dbType" -}}
{{ .Values.api.db.type | default "sqlite" }}
{{- end }}

{{- define "api.dbHost" -}}
{{ .Values.api.db.host | default "postgres" }}
{{- end }}

{{- define "api.dbPort" -}}
{{ .Values.api.db.port | default 5432 }}
{{- end }}

{{- define "api.dbName" -}}
{{ .Values.api.db.name | default "devportal" }}
{{- end }}

{{- define "api.dbUser" -}}
{{ .Values.api.db.user | default "nginxdm" | b64enc }}
{{- end }}

{{- define "api.dbPass" -}}
{{ .Values.api.db.pass | default "nginxdm" | b64enc }}
{{- end }}

{*
   ------ Storage ------
*}

{{/* Helper to get devportal storage class for storage provisioning */}}
{{- define "devportal.storageClass" -}}
{{- if .Values.api.persistence.storageClass }}
{{- if (eq "-" .Values.api.persistence.storageClass) }}
storageClassName: ""
{{- else }}
storageClassName: "{{ .Values.api.persistence.storageClass }}"
{{- end }}
{{- end }}
{{- end }}
