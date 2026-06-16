# AWS EKS Fargate + Datadog Lab

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0-623CE4?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EKS%20Fargate-FF9900?logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.30-326CE5?logo=kubernetes&logoColor=white)
![Datadog](https://img.shields.io/badge/Datadog-APM%20%7C%20Logs%20%7C%20Metrics-632CA6?logo=datadog&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

Infraestrutura como código (IaC) para provisionar um cluster **EKS com Fargate** na AWS e implantar uma aplicação Python com o **agente Datadog como sidecar** para observabilidade completa (APM, logs e métricas).

## Arquitetura

```
VPC (10.0.0.0/16)
├── Subnets públicas  (x2 AZs) → Internet Gateway
└── Subnets privadas  (x2 AZs) → NAT Gateway
    └── EKS Cluster (v1.30)
        └── Fargate Profile (namespace: apps)
            └── Pod: python-app
                ├── container: python-tracing-app  ← aplicação
                └── container: datadog-agent       ← sidecar APM/logs/metrics
```

## Recursos provisionados

| Recurso | Descrição |
|---|---|
| VPC + Subnets | 2 subnets públicas e 2 privadas em AZs distintas |
| NAT Gateway | 1 por AZ para saída das subnets privadas |
| EKS Cluster | `eks-datadog-lab` na região `us-east-1` |
| Fargate Profile | `fp-datadog-lab` para o namespace `apps` |
| IAM Roles | `eks-cluster-role` e `fargate-execution` |
| OIDC Provider | Habilitado para IRSA (IAM Roles for Service Accounts) |
| Kubernetes RBAC | ClusterRole + ServiceAccount para o agente Datadog |
| Deployment | `python-app` com sidecar Datadog |

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configurado com o profile `danilo-profile`
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Datadog API Key

## Uso

```bash
# 1. Exportar a Datadog API Key
export TF_VAR_dd_api_key=$DD_API_KEY

# 2. Inicializar
terraform init

# 3. Revisar o plano
terraform plan

# 4. Aplicar
terraform apply
```

## Variáveis

| Variável | Padrão | Descrição |
|---|---|---|
| `aws_region` | `us-east-1` | Região AWS |
| `cluster_name` | `eks-datadog-lab` | Nome do cluster EKS |
| `dd_api_key` | — | Datadog API Key (sensível, via `TF_VAR_dd_api_key`) |

## Datadog Agent

O agente Datadog roda como **sidecar** no mesmo pod da aplicação. Em EKS Fargate não há acesso ao nó subjacente, portanto o padrão DaemonSet não é suportado — o sidecar é a abordagem oficial da Datadog para esse ambiente.

### Como funciona

Cada pod contém dois containers que compartilham o mesmo namespace de rede (`localhost`):

```
Pod: python-app
├── python-tracing-app   → envia traces para localhost:8126 e métricas para localhost:8125
└── datadog-agent        → recebe, agrega e envia dados para o backend Datadog
```

A aplicação aponta para o agente via variáveis de ambiente:

```
DD_AGENT_HOST=localhost
DD_TRACE_AGENT_PORT=8126
```

### Processo de instalação

O agente é instalado automaticamente via Terraform como parte do `kubernetes_deployment` definido em `k8s.tf`. O processo ocorre nas seguintes etapas:

#### 1. RBAC — Service Account e permissões

Antes de subir o pod, o Terraform cria os recursos RBAC necessários:

```
kubernetes_service_account  "datadog-agent"   (namespace: apps)
kubernetes_cluster_role     "datadog-agent"   (regras de leitura no cluster)
kubernetes_cluster_role_binding               (vincula SA ao ClusterRole)
```

O `ClusterRole` concede `get`, `list` e `watch` sobre:
- `nodes`, `pods`, `services`, `endpoints`, `events`, `namespaces`, `componentstatuses`
- `deployments`, `replicasets`, `statefulsets`, `daemonsets`
- `jobs`, `cronjobs`

#### 2. Deployment do sidecar

O container `datadog-agent` é declarado dentro do mesmo `spec.template` do pod da aplicação, garantindo que ambos compartilhem o mesmo namespace de rede:

```hcl
container {
  name  = "datadog-agent"
  image = "public.ecr.aws/datadog/agent:latest"

  port { container_port = 8126; protocol = "TCP" }  # APM
  port { container_port = 8125; protocol = "UDP" }  # DogStatsD
}
```

A chave de API é injetada via variável do Terraform (`var.dd_api_key`), nunca hardcoded.

#### 3. Autodiscovery via anotação

O pod recebe a anotação abaixo, que instrui o agente a coletar métricas do `kube-state-metrics`:

```json
"ad.datadoghq.com/datadog-agent.checks": {
  "kubernetes_state": {
    "init_config": {},
    "instances": [{
      "kube_state_url": "http://kube-state-metrics.kube-system.svc.cluster.local:8080/metrics",
      "telemetry": true
    }]
  }
}
```

#### 4. Configuração específica para Fargate

Por não ter acesso ao nó subjacente, as variáveis abaixo são obrigatórias para o modo Fargate:

| Variável | Valor | Por quê |
|---|---|---|
| `DD_EKS_FARGATE` | `true` | Ativa o modo sem nó (nodeless) |
| `DD_KUBERNETES_KUBELET_NODENAME` | `spec.nodeName` (fieldRef) | Identifica o nó virtual do Fargate via Downward API |
| `DD_APM_NON_LOCAL_TRAFFIC` | `true` | Necessário pois app e agente são processos distintos |
| `DD_DOGSTATSD_NON_LOCAL_TRAFFIC` | `true` | Idem para métricas StatsD |

#### 5. Unified Service Tagging

As tags `env`, `service` e `version` são aplicadas tanto no container da aplicação quanto no do agente, garantindo correlação entre traces, logs e métricas no Datadog:

```hcl
# Aplicação
env { name = "DD_ENV";     value = "production" }
env { name = "DD_SERVICE"; value = "python-app" }
env { name = "DD_VERSION"; value = "1.0.0" }

# Agente (mesmo conjunto)
env { name = "DD_ENV";     value = "production" }
env { name = "DD_SERVICE"; value = "python-app" }
env { name = "DD_VERSION"; value = "1.0.0" }
```

#### 6. Ordem de criação (dependências Terraform)

```
aws_eks_fargate_profile
        ↓
kubernetes_namespace "apps"
        ↓
kubernetes_service_account + kubernetes_cluster_role
        ↓
kubernetes_cluster_role_binding
        ↓
kubernetes_deployment "python-app" (inclui sidecar datadog-agent)
```

### Configuração do agente (variáveis de ambiente)

| Variável | Valor | Descrição |
|---|---|---|
| `DD_API_KEY` | `var.dd_api_key` | Chave de API Datadog |
| `DD_EKS_FARGATE` | `true` | Habilita modo Fargate |
| `DD_APM_ENABLED` | `true` | Habilita coleta de traces (APM) |
| `DD_APM_NON_LOCAL_TRAFFIC` | `true` | Aceita traces de outros processos no pod |
| `DD_LOGS_ENABLED` | `true` | Habilita coleta de logs |
| `DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL` | `true` | Coleta logs de todos os containers do pod |
| `DD_DOGSTATSD_NON_LOCAL_TRAFFIC` | `true` | Aceita métricas StatsD de outros processos |
| `DD_PROCESS_AGENT_ENABLED` | `true` | Habilita monitoramento de processos |
| `DD_ORCHESTRATOR_EXPLORER_ENABLED` | `true` | Habilita visibilidade de recursos Kubernetes |
| `DD_COLLECT_KUBERNETES_EVENTS` | `true` | Coleta eventos do cluster |
| `DD_LEADER_ELECTION` | `true` | Garante coleta única de eventos em múltiplas réplicas |
| `DD_KUBERNETES_COLLECT_METADATA_TAGS` | `true` | Enriquece dados com labels/anotações do pod |
| `DD_KUBERNETES_POD_LABELS_AS_TAGS` | `{"app","version","env"}` | Mapeia labels do pod como tags Datadog |
| `DD_CLUSTER_NAME` | `var.cluster_name` | Nome do cluster para identificação |
| `DD_ENV` / `DD_SERVICE` / `DD_VERSION` | `production` / `python-app` / `1.0.0` | Tags de Unified Service Tagging |

### Portas expostas pelo agente

| Porta | Protocolo | Uso |
|---|---|---|
| `8126` | TCP | APM — recebe traces da aplicação |
| `8125` | UDP | DogStatsD — recebe métricas customizadas |

### RBAC

O agente usa um `ServiceAccount` dedicado (`datadog-agent`) vinculado a um `ClusterRole` com permissão de leitura (`get`, `list`, `watch`) sobre:

- `nodes`, `pods`, `services`, `endpoints`, `events`, `namespaces`
- `deployments`, `replicasets`, `statefulsets`, `daemonsets`
- `jobs`, `cronjobs`

### Imagem utilizada

```
public.ecr.aws/datadog/agent:latest
```

> Para ambientes de produção, fixe uma versão específica (ex: `public.ecr.aws/datadog/agent:7`) para evitar atualizações não controladas.

## Providers

| Provider | Versão |
|---|---|
| `hashicorp/aws` | `~> 5.0` |
| `hashicorp/kubernetes` | `~> 2.0` |
| `hashicorp/tls` | `~> 4.0` |
