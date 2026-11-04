# azure-lab

A small, cheap, destroyable Azure lab: **Terraform → AKS + ACR + Key Vault + Log Analytics**, deploy a container image with **Helm**, read a secret from **Key Vault** inside a pod, and watch a **metric alert** fire.

Built as a learning project to complement an OpenStack/Kubernetes background with the Azure equivalents.

## Architecture

```
Terraform (state in Azure Blob Storage)
│
├── rg-azure-lab
│   ├── ACR (Basic)                 private image registry
│   ├── AKS (1 × Standard_B2s)      managed Kubernetes, system-assigned identity
│   │     └── oms_agent → Log Analytics workspace
│   │     └── key_vault_secrets_provider (Secrets Store CSI driver add-on)
│   ├── Key Vault (RBAC)            secret: app-message
│   └── Azure Monitor               action group + metric alert (node CPU)
│
└── Helm chart ./chart  →  Deployment + Service  →  image from ACR
    Pod kv-demo         →  mounts app-message from Key Vault as a file
```

## Prerequisites

- Azure for Students subscription (~$100 credit)
- `az`, `terraform >= 1.7`, `kubectl`, `helm`, `git`

## 1. Bootstrap the state storage (once)

Terraform needs somewhere shared to keep `terraform.tfstate`. Create it once, by hand:

```bash
az group create -n rg-tfstate -l westeurope
az storage account create -n stazlabmaneji01 -g rg-tfstate -l westeurope \
  --sku Standard_LRS --allow-blob-public-access false
az storage container create -n tfstate --account-name stazlabmaneji01
```

The name must be globally unique and 3–24 lowercase alphanumeric characters. If it is taken, pick another and update `backend.tf`.

## 2. Deploy

```bash
terraform init
terraform plan -out lab.tfplan
terraform apply lab.tfplan
```

## 3. Connect

```bash
az aks get-credentials -g rg-azure-lab -n aks-azure-lab --overwrite-existing
kubectl get nodes
```

## 4. Build and push the image to ACR

`az acr build` builds in Azure, so no local Docker daemon is needed:

```bash
ACR=$(terraform output -raw acr_login_server)
az acr build --registry ${ACR%%.*} --image web:v1 ./app
```

## 5. Deploy with Helm

```bash
helm upgrade --install web ./chart --set image.repository=$ACR/web --set image.tag=v1
kubectl get pods,svc
kubectl port-forward svc/web-web 8080:80
```

## 6. Read the Key Vault secret inside the cluster

```bash
terraform output -raw key_vault_name
terraform output -raw kv_client_id
terraform output -raw tenant_id
```

Put those three values in `spc.yaml`, then:

```bash
kubectl apply -f spc.yaml -f pod.yaml
kubectl logs kv-demo     # hello from Azure Key Vault
```

## 7. Trigger the alert

```bash
kubectl run stress-1 --image=busybox:1.36 --restart=Never -- sh -c "while :; do :; done"
kubectl run stress-2 --image=busybox:1.36 --restart=Never -- sh -c "while :; do :; done"
```

Two busy loops ≈ full 2-vCPU node. The alert (`node CPU > 50%` for 5 min) fires and an email arrives. Then:

```bash
kubectl delete pod stress-1 stress-2
```

## 8. Destroy

```bash
terraform destroy
az group delete -n rg-tfstate --yes   # only if you are done with the lab for good
```

## Cost notes

| Resource | Approx. cost |
|---|---|
| AKS control plane (free tier) | $0 |
| 1 × Standard_B2s node | ~$0.04/h |
| ACR Basic | ~$0.02/day |
| Key Vault, Log Analytics | cents |
| **Total for a 3 h session** | **< $2** |

Set a **budget alert** before starting (Cost Management → Budgets → $25).

## What each service is (short version)

- **Subscription** — the billing boundary; your $100 credit lives here.
- **Resource group** — a logical folder; deleting it deletes everything inside.
- **ACR** — private Docker registry inside your subscription.
- **AKS** — managed Kubernetes; Azure runs the control plane, you pay the nodes.
- **Key Vault** — managed secret store; in RBAC mode permissions come from Azure roles.
- **Managed identity** — an identity Azure creates and rotates for you; no passwords.
- **Secrets Store CSI driver** — mounts Key Vault secrets as files inside pods.
- **Log Analytics / Container Insights** — central log and metric store for the cluster.
- **Metric alert + action group** — "watch this number, notify these people".
- **Terraform state backend** — where Terraform remembers what it created.

## License

MIT
