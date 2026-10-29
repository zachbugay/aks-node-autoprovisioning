# AKS Node Autoprovisioning Demo

## Deploy

```bash
az login
az account list --output table
az account set --subscription "<subscription-id>"

ARM_SUBSCRIPTION_ID = "<subscription-id>"

terraform init
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

Get the outputs
```bash
workloadSubnetId=(terraform output -raw workload_subnet_id)
capacityReservationGroupId=(terraform output -raw capacity_reservation_group_id)
```

Update `spec.vnetSubnetID` in both `AKSNodeClass` files with `$workloadSubnetId`. 
Update `spec.capacityReservation.groupID` in `kubernetes/capacity-reservations/aks-node-class.yaml` with `$capacityReservationGroupId`.

```bash
az aks get-credentials --resource-group rg-aks-nap-demo --name aks-nap-demo
kubectl apply -f kubernetes/general/aks-node-class.yaml
kubectl apply -f kubernetes/capacity-reservations/aks-node-class.yaml
kubectl apply -f kubernetes/general/node-pool.yaml
kubectl apply -f kubernetes/capacity-reservations/node-pool.yaml
kubectl apply -f kubernetes/nginx-deployment.yaml

# Get the nodes, make sure example-np-reserved is there
❯ kubectl get nodes -A
NAME                             STATUS   ROLES    AGE     VERSION
aks-example-np-reserved-c6ff8    Ready    <none>   4m12s   v1.36.4
aks-system-84141890-vmss000000   Ready    <none>   21m     v1.36.4

❯ kubectl get pods -l app=nginx -o wide

NAME                     READY   STATUS    RESTARTS   AGE    IP              NODE                            NOMINATED NODE   READINESS GATES
nginx-7b768bf586-g78nx   1/1     Running   0          8m1s   192.168.1.102   aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-gbcnr   1/1     Running   0          8m1s   192.168.1.190   aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-gl8k7   1/1     Running   0          8m1s   192.168.1.238   aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-k87js   1/1     Running   0          8m1s   192.168.1.23    aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-p8chv   1/1     Running   0          8m1s   192.168.1.191   aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-pnssh   1/1     Running   0          8m1s   192.168.1.101   aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-prtqg   1/1     Running   0          8m1s   192.168.1.176   aks-example-np-reserved-c6ff8   <none>           <none>g
nginx-7b768bf586-rpvlk   1/1     Running   0          8m1s   192.168.1.92    aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-xfqd9   1/1     Running   0          8m1s   192.168.1.240   aks-example-np-reserved-c6ff8   <none>           <none>
nginx-7b768bf586-zlqn6   1/1     Running   0          8m1s   192.168.1.220   aks-example-np-reserved-c6ff8   <none>           <none>
```
