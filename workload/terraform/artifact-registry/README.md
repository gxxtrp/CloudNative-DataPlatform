# Workload Artifact Registry Terraform

This root creates one private OCI repository for the two publisher modules. Apply it before building their images and before the Cloud Run root.

After apply, publish images with your administrator identity:

```sh
gcloud builds submit workload/apps/order-service \
  --tag asia-southeast1-docker.pkg.dev/workload-508107/delivery-workload/order-service:git-sha
gcloud builds submit workload/apps/rider-service \
  --tag asia-southeast1-docker.pkg.dev/workload-508107/delivery-workload/rider-service:git-sha
```

Use immutable tags such as a Git SHA. The Cloud Run root takes the complete image references as required input and never uses `latest`.
