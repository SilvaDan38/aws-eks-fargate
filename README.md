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

## Providers

| Provider | Versão |
|---|---|
| `hashicorp/aws` | `~> 5.0` |
| `hashicorp/kubernetes` | `~> 2.0` |
| `hashicorp/tls` | `~> 4.0` |
