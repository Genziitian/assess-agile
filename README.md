# assess-agile

ISWE406P Agile Development Process and DevOps assessment implementation for SRIRAM, 24MIS0468.

| Question | Application | Replicas | Host address | Jenkins script |
| --- | --- | --- | --- | --- |
| 1 | University Learning Management Portal | 2 | http://localhost:30017 | question1/Jenkinsfile |
| 2 | Online Food Ordering Portal | 3 active | http://localhost:30018 | question2/Jenkinsfile |
| 3 | Hospital Appointment Portal | 3 | http://localhost:30019 | question3/Jenkinsfile |

Each question directory contains `index.html`, `index.v2.html`, `Dockerfile`, `Dockerfile.faulty`, `deployment.yaml`, and `Jenkinsfile`. The manifests use the dedicated `assess-agile` namespace. Existing workloads are preserved.

## Release behavior

The pipelines clone main, build a unique image tagged with release, Jenkins build number and commit, run an HTTP/content test against a temporary container, authenticate to Docker Hub, push the image, deploy, and verify service content. Production stages execute shell commands. SCM polling checks GitHub every minute, so commits trigger the jobs without exposing the local Jenkins server to the Internet. The first build initializes polling. Credentials are `docker-hub-creds` (username/password) and `k8s-config-file` (secret file). Jenkins needs Docker, kubectl, curl and Git on its agent; this installation runs directly on the Mac with access to Docker Desktop.

The RELEASE parameter selects `v1`, `v2`, or `faulty`. A normal image must pass container health/content testing before publishing. The explicit `faulty` demonstration confirms a missing health endpoint, then intentionally permits that known defect to reach Kubernetes so automatic recovery can be observed. The job remains failed after successful recovery; a failed release is never reported as a successful release.

University and hospital use RollingUpdate with zero unavailable replicas. Readiness/liveness probes check `/healthz`, rollout deadlines detect failure, and the deploy script runs `kubectl rollout undo`, waits for recovery, and checks the restored page through the Service.

Food uses blue/green Deployments. The inactive slot is scaled to three replicas, checked for readiness and tested through `food-preview` before the NodePort selector changes. A failed candidate is scaled down and reset to the previous stable image while the active slot keeps serving. After promotion the former active slot scales to zero but retains its stable image.

## Reproduce manually

```sh
kubectl create namespace assess-agile
# Repeat for question2/food and question3/hospital.
docker build -t sriram24mis/assess-university:v1 question1
sh scripts/test-container.sh sriram24mis/assess-university:v1 university
docker push sriram24mis/assess-university:v1
kubectl apply -f question1/deployment.yaml
kubectl -n assess-agile rollout status deployment/university
# Build and push a new version, then release it.
docker build --build-arg HTML_FILE=index.v2.html -t sriram24mis/assess-university:v2 question1
docker push sriram24mis/assess-university:v2
sh scripts/deploy.sh question1 sriram24mis/assess-university:v2 v2
# Expected nonzero exit after verified rollback.
docker build -f question1/Dockerfile.faulty -t sriram24mis/assess-university:faulty question1
docker push sriram24mis/assess-university:faulty
sh scripts/deploy.sh question1 sriram24mis/assess-university:faulty faulty
curl -fsS http://localhost:30017/healthz
kubectl -n assess-agile get deployment,pods,svc
```

Run each Jenkins job with v1, v2, then faulty to capture full CI/CD release and recovery evidence. Docker Desktop Kubernetes must be enabled and Ready. NodePort addresses refer to the host Mac. Unique pipeline tags are preferred over mutable demonstration tags.

The assessment PDF is named AST09 but labels itself Assessment VIII. This repository follows its three portal questions. The Question 3 placement/company sentence is inconsistent with its hospital heading; the v2 hospital page adds a doctor and consultation opportunity. All displayed portal data are demonstration data.

Execution evidence is in `evidence/`; the completed report is in `report/`. Credentials and kubeconfig are excluded from Git.
