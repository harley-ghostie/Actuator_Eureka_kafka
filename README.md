# Spring Boot Actuator & Eureka PoC Scripts

Este repositório reúne scripts de apoio para validação controlada de exposição de endpoints Spring Boot Actuator, uso indevido de credenciais do Eureka e validação de impacto envolvendo credenciais Kafka/Confluent Cloud expostas.

Os scripts estão relacionados ao mesmo cenário de risco: exposição de configurações sensíveis por endpoints administrativos, principalmente em aplicações Spring Boot.

Em resumo:

- `eureka.sh`: realiza enumeração ampla de endpoints Spring Boot Actuator expostos e busca possíveis vazamentos de variáveis sensíveis.
- `eureka_poc.sh`: realiza validação específica a partir da URL do Eureka encontrada no `/env`, testando se as credenciais expostas permitem acesso ao inventário de aplicações registradas.
- `kafka_metadata_probe.py`: valida se credenciais Kafka/Confluent Cloud expostas conseguem autenticar no cluster e consultar metadados, sem consumir mensagens ou alterar dados.

---

## Visão geral dos scripts

| Script | Objetivo | Quando usar |
|---|---|---|
| `eureka.sh` | Enumerar endpoints Spring Boot Actuator e coletar evidências de exposição | Usar no início da análise para identificar endpoints administrativos expostos e possíveis variáveis sensíveis. |
| `eureka_poc.sh` | Validar acesso ao Eureka a partir de credenciais expostas no `/env` | Usar quando a configuração do Eureka for encontrada em endpoint Actuator exposto. |
| `kafka_metadata_probe.py` | Validar impacto de credenciais Kafka/Confluent Cloud expostas | Usar quando forem identificadas credenciais Kafka em `/env`, `/configprops` ou outro endpoint exposto. |

---

# Fluxo recomendado de uso

A ordem mais lógica para utilização dos scripts é:

```text
1. eureka.sh
   ↓
2. eureka_poc.sh
   ↓
3. kafka_metadata_probe.py
```

## Explicação rápida do fluxo

Primeiro, use o `eureka.sh` para identificar endpoints Spring Boot Actuator expostos e possíveis variáveis sensíveis. Caso o `/env` exponha configurações relacionadas ao Eureka, use o `eureka_poc.sh` para validar se as credenciais permitem acesso ao inventário de aplicações registradas. Caso sejam encontradas credenciais Kafka ou Confluent Cloud, use o `kafka_metadata_probe.py` para validar se essas credenciais ainda estão ativas e permitem consulta aos metadados do cluster.

---

# Scripts

## eureka.sh

### Descrição

O `eureka.sh` realiza uma enumeração de endpoints comuns do Spring Boot Actuator, como `/env`, `/health`, `/info`, `/metrics`, `/prometheus`, `/configprops`, `/beans`, `/mappings`, `/conditions`, `/threaddump` e `/scheduledtasks`.

O objetivo é identificar endpoints administrativos expostos publicamente e coletar evidências de possíveis vazamentos de informações sensíveis, como configurações de Eureka, banco de dados, Kafka, FTP, tokens de APM e outras variáveis internas da aplicação.

### O que o script faz

- Testa uma lista de endpoints comuns do Spring Boot Actuator usando requisições GET;
- Salva os cabeçalhos HTTP dos endpoints testados;
- Baixa o corpo da resposta quando o endpoint retorna HTTP 200 ou 206;
- Procura automaticamente por variáveis sensíveis no endpoint `/env`;
- Extrai informações relacionadas a Eureka, datasource, APM, Kafka, FTP e configurações internas;
- Gera uma versão sanitizada do arquivo de ambiente;
- Coleta configurações extras quando endpoints como `configprops`, `mappings`, `beans`, `metrics` ou `prometheus` estão acessíveis;
- Gera um arquivo `SUMMARY.txt` com o resumo das evidências encontradas.

### Cenário de uso

Use este script no início da análise, quando o objetivo for verificar se a aplicação expõe endpoints administrativos do Spring Boot Actuator.

Ele é indicado para mapear rapidamente quais endpoints estão acessíveis e quais informações sensíveis podem estar sendo divulgadas.

### Campos que devem ser alterados

Antes de executar, ajuste a variável `BASE` no início do script conforme o ambiente autorizado:

```bash
BASE="https://exemplo.com.br"
```

### Explicação dos campos

| Campo | Descrição |
|---|---|
| `BASE` | URL base da aplicação Spring Boot que será testada. |

### Exemplo de configuração

```bash
BASE="https://api.exemplo.com.br"
```

### Como usar

Dê permissão de execução:

```bash
chmod +x eureka.sh
```

Execute:

```bash
./eureka.sh
```

### Evidências geradas

O script cria o diretório `poc_external_actuator/` e salva os arquivos de evidência dentro dele.

Entre os principais artefatos gerados estão:

- cabeçalhos HTTP dos endpoints testados;
- corpos de resposta dos endpoints acessíveis;
- arquivo bruto do `/env`, quando disponível;
- versão sanitizada do `/env`;
- arquivos individuais com variáveis sensíveis identificadas;
- resumo final da execução em `SUMMARY.txt`.

---

## eureka_poc.sh

### Descrição

O `eureka_poc.sh` realiza uma validação controlada de exposição de informações sensíveis em ambientes Spring Boot Actuator integrados ao Eureka.

O script acessa o endpoint `/api/management/env`, identifica automaticamente a variável `EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE`, extrai a URL do Eureka e valida se as credenciais expostas permitem acesso ao inventário de aplicações registradas no serviço.

A proposta é demonstrar, de forma segura e controlada, que a exposição de variáveis sensíveis pode permitir acesso a informações internas da arquitetura da aplicação, como serviços registrados, hosts, IPs e URLs operacionais.

### O que o script faz

- Consulta o endpoint `/api/management/env`;
- Localiza automaticamente a URL de configuração do Eureka;
- Extrai usuário, senha e host da URL encontrada;
- Testa autenticação no endpoint `/eureka/apps`;
- Coleta o inventário de aplicações registradas no Eureka;
- Extrai hosts, IPs, URLs de status e URLs de health check;
- Gera arquivos de evidência em uma pasta local;
- Sanitiza credenciais sensíveis nos artefatos gerados.

### Cenário de uso

Use este script quando uma exposição no Spring Boot Actuator revelar configurações relacionadas ao Eureka.

Ele é indicado para validar se as credenciais expostas ainda estão funcionais e se permitem acesso ao inventário de serviços registrados.

### Campos que devem ser alterados

Antes de executar, ajuste as variáveis no início do script conforme o ambiente autorizado:

```bash
BASE_URL="https://exemplo.com.br"
ENV_PATH="/api/management/env"
```

### Explicação dos campos

| Campo | Descrição |
|---|---|
| `BASE_URL` | URL base da aplicação Spring Boot. |
| `ENV_PATH` | Caminho do endpoint Actuator que expõe as variáveis de ambiente. |

### Exemplo de configuração

```bash
BASE_URL="https://api.exemplo.com.br"
ENV_PATH="/api/management/env"
```

### Como usar

Dê permissão de execução:

```bash
chmod +x eureka_poc.sh
```

Execute:

```bash
./eureka_poc.sh
```

### Evidências geradas

O script cria o diretório `poc_eureka/` e salva os arquivos de evidência dentro dele.

Entre os principais artefatos gerados estão:

- `01_apps_headers.txt`;
- `02_apps.json`;
- `02_apps.xml`;
- `03_inventory_from_json.tsv`;
- `03_ips_from_xml.txt`;
- `03_hosts_from_xml.txt`;
- `03_health_urls_from_xml.txt`;
- `03_status_urls_from_xml.txt`;
- `05_health_urls.txt`;
- `05_health_checks_samples.txt`;
- `06_summary.txt`.

---

## kafka_metadata_probe.py

### Descrição

O `kafka_metadata_probe.py` é um script de validação controlada para verificar se credenciais Kafka ou Confluent Cloud identificadas em uma exposição de configuração conseguem autenticar no cluster e consultar metadados.

Ele não consome mensagens, não produz mensagens e não altera dados. A validação é limitada à listagem de brokers e nomes de tópicos, servindo como evidência de impacto quando segredos Kafka são expostos por endpoints como Spring Boot Actuator `/env` ou `/configprops`.

### O que o script faz

- Conecta em um cluster Kafka ou Confluent Cloud usando `SASL_SSL`;
- Autentica com usuário e senha/API key informados;
- Consulta metadados do cluster;
- Lista brokers disponíveis;
- Lista nomes de tópicos, com limite de exibição;
- Encerra a conexão após a coleta.

### Cenário de uso

Use este script quando uma exposição de configuração revelar credenciais Kafka ou Confluent Cloud e for necessário validar, de forma controlada, se essas credenciais ainda estão ativas.

Ele é útil para demonstrar que o vazamento não é apenas informativo, mas pode permitir acesso real ao cluster e visibilidade sobre componentes internos da mensageria.

### Campos que devem ser alterados

Antes de executar, ajuste os campos de conexão com valores autorizados:

```python
conf = {
  "bootstrap.servers": "KAFKA_BOOTSTRAP_SERVER:9092",
  "security.protocol": "SASL_SSL",
  "sasl.mechanisms": "PLAIN",
  "sasl.username": "KAFKA_API_KEY",
  "sasl.password": "KAFKA_API_SECRET",
  "group.id": "pentest-metadata-only",
  "enable.auto.commit": False,
  "session.timeout.ms": 6000,
}
```

### Explicação dos campos

| Campo | Descrição |
|---|---|
| `bootstrap.servers` | Endereço do broker Kafka ou Confluent Cloud. |
| `security.protocol` | Protocolo de segurança usado na conexão. Para Confluent Cloud, normalmente `SASL_SSL`. |
| `sasl.mechanisms` | Mecanismo de autenticação SASL. Normalmente `PLAIN` em Confluent Cloud. |
| `sasl.username` | API key ou usuário utilizado na autenticação. |
| `sasl.password` | API secret ou senha utilizada na autenticação. |
| `group.id` | Identificador do grupo usado apenas para a conexão de validação. |
| `enable.auto.commit` | Mantido como `False` para evitar commit automático de offset. |
| `session.timeout.ms` | Tempo limite de sessão da conexão. |


### Como usar

Instale a dependência:

```bash
pip install confluent-kafka
```

Execute:

```bash
python3 kafka_metadata_probe.py
```

### Saída esperada

O script exibe informações semelhantes a:

```text
Brokers: ['broker1:9092', 'broker2:9092']
Topics: ['topic-a', 'topic-b', 'topic-c']
```

### Observação de segurança

Mesmo consultando apenas metadados, a capacidade de autenticar e listar brokers/tópicos já comprova impacto relevante, pois indica que credenciais expostas podem ser utilizadas fora do ambiente esperado.

Ao confirmar o acesso, recomenda-se rotacionar imediatamente as credenciais, revisar permissões associadas, validar logs de autenticação e restringir o uso por rede, aplicação e princípio de menor privilégio.

---

# Requisitos

## Sistema operacional

Os scripts foram criados para execução em Linux, especialmente distribuições usadas em testes de segurança, como Kali Linux, Debian ou Ubuntu.

| Ambiente | Compatibilidade |
|---|---|
| Kali Linux | Alta |
| Debian/Ubuntu | Alta |
| Windows | Não recomendado diretamente |
| WSL | Pode funcionar para os scripts HTTP e Kafka, desde que as dependências estejam instaladas |
| macOS | Pode funcionar com ajustes de dependências |

---

## Dependências dos scripts Bash

Os scripts `eureka.sh` e `eureka_poc.sh` utilizam ferramentas comuns em ambientes Linux:

```text
bash
curl
grep
sed
sort
cut
tee
head
wc
jq
```

O uso do `jq` é opcional em alguns pontos, mas recomendado para melhor tratamento dos dados em JSON.

Para instalar no Debian, Ubuntu ou Kali:

```bash
sudo apt update
sudo apt install -y curl jq grep sed coreutils
```

---

## Dependências do script Kafka

O `kafka_metadata_probe.py` requer Python 3 e a biblioteca `confluent-kafka`.

Instalação:

```bash
python3 -m pip install confluent-kafka
```

Caso utilize ambiente virtual:

```bash
python3 -m venv venv
source venv/bin/activate
pip install confluent-kafka
```

---

# Ajustes necessários antes de executar

## 1. Validar o escopo autorizado

Antes de executar qualquer script, confirme:

- domínio ou endpoint autorizado;
- endpoints permitidos no teste;
- se a coleta de configurações está permitida;
- se a validação de credenciais está permitida;
- se a listagem de metadados Kafka está permitida;
- onde as evidências serão armazenadas;
- como os dados sensíveis devem ser mascarados.

Use placeholders:

```text
KAFKA_API_KEY
KAFKA_API_SECRET
KAFKA_BOOTSTRAP_SERVER
EUREKA_USER
EUREKA_PASSWORD
```

## 2. Revisar artefatos gerados

Antes de anexar ou compartilhar evidências, revise e sanitize os arquivos gerados.

Principalmente:

```text
poc_external_actuator/
poc_eureka/
```

Esses diretórios podem conter dados sensíveis extraídos dos endpoints analisados.

---

# Recomendações de mitigação

Para reduzir os riscos avaliados por estes scripts, recomenda-se restringir a exposição de endpoints Spring Boot Actuator, especialmente `/env`, `/configprops`, `/beans`, `/mappings`, `/metrics` e `/prometheus`.

Também é recomendado exigir autenticação forte para endpoints administrativos, limitar acesso por rede, remover segredos de variáveis expostas, usar secret managers, rotacionar credenciais vazadas, revisar permissões associadas a contas de serviço, aplicar princípio do menor privilégio e monitorar acessos anômalos aos serviços internos.

Em ambientes Kafka ou Confluent Cloud, recomenda-se rotacionar API keys expostas, revisar ACLs, restringir permissões por tópico, limitar acesso por origem quando possível, auditar logs de autenticação e separar credenciais por aplicação e ambiente.

---

# Observação de segurança

Estes scripts devem ser utilizados apenas em ambientes autorizados.

Os scripts `eureka.sh` e `eureka_poc.sh` executam requisições HTTP GET e não realizam alteração de estado na aplicação. Já o `kafka_metadata_probe.py` realiza autenticação no cluster Kafka e consulta metadados, sem consumir ou produzir mensagens.

Mesmo sem alteração de dados, a execução pode acessar informações sensíveis. Portanto, o uso deve estar alinhado ao escopo formal do teste e às regras de engajamento aprovadas.

Antes de compartilhar qualquer evidência, revise os arquivos gerados para garantir que credenciais, tokens, IPs internos, URLs privadas, nomes de aplicações, nomes de tópicos ou demais informações sensíveis estejam devidamente removidos ou mascarados.

---

# Aviso legal

O uso destes scripts contra sistemas sem autorização é proibido.

A finalidade deste repositório é exclusivamente apoiar atividades legítimas de segurança, como pentest autorizado, validação de vulnerabilidades, laboratório, estudo técnico e demonstração controlada de risco.
