#!/bin/sh
# Releases a tested image. Nonzero exit on failed release, even after recovery.
set -eu
q=$1
image=$2
expected=${3:-v1}
ns=assess-agile
app=$(sed -n 's/.*"app": "\([^"]*\)".*/\1/p' "$q/app.json")
port=$(sed -n 's/.*"nodePort": \([0-9]*\).*/\1/p' "$q/app.json")
k() { kubectl -n "$ns" "$@"; }
verify_service() {
  # Verifies real service routing from a Pod; NodePort is verified separately on host.
  k run "verify-$app-$(date +%s)" --rm -i --restart=Never --image=busybox:1.37 --quiet \
    --command -- sh -c "wget -qO- http://$app/healthz && wget -qO- http://$app/ | grep 'data-release=\"$1\"'"
}
if [ "$app" = food ]; then
  active=$(k get svc food -o jsonpath='{.spec.selector.color}')
  target=green; [ "$active" != green ] || target=blue
  oldimage=$(k get deploy "food-$active" -o jsonpath='{.spec.template.spec.containers[0].image}')
  oldversion=$(printf '%s' "$oldimage" | sed 's/.*://; s/-.*//')
  k set image "deployment/food-$target" "web=$image"
  k scale "deployment/food-$target" --replicas=3
  if ! k rollout status "deployment/food-$target" --timeout=90s; then
    k describe deployment "food-$target"
    k get pods -l "app=food,color=$target" -o wide
    echo "FAILED candidate; production selector remains $active; restoring inactive slot"
    k scale "deployment/food-$target" --replicas=0
    k set image "deployment/food-$target" "web=$oldimage"
    verify_service "$oldversion"
    exit 1
  fi
  # Validate the candidate through its own ClusterIP before changing public traffic.
  cat <<EOF | k apply -f -
apiVersion: v1
kind: Service
metadata:
  name: food-preview
spec:
  selector:
    app: food
    color: $target
  ports:
    - port: 80
      targetPort: 80
EOF
  if ! k run "preview-$(date +%s)" --rm -i --restart=Never --image=busybox:1.37 --quiet --command -- sh -c "wget -qO- http://food-preview/healthz && wget -qO- http://food-preview/ | grep 'data-release=\"$expected\"'"; then
    k scale "deployment/food-$target" --replicas=0
    k set image "deployment/food-$target" "web=$oldimage"
    verify_service "$oldversion"
    exit 1
  fi
  k patch svc food --type=merge -p "{\"spec\":{\"selector\":{\"app\":\"food\",\"color\":\"$target\"}}}"
  if ! verify_service "$expected"; then
    k patch svc food --type=merge -p "{\"spec\":{\"selector\":{\"app\":\"food\",\"color\":\"$active\"}}}"
    verify_service "$oldversion"
    exit 1
  fi
  k scale "deployment/food-$active" --replicas=0
  echo "PROMOTED $target; previous image retained in $active"
else
  previous=$(k get deploy "$app" -o jsonpath='{.spec.template.spec.containers[0].image}')
  oldversion=$(printf '%s' "$previous" | sed 's/.*://; s/-.*//')
  k set image "deployment/$app" "web=$image"
  if k rollout status "deployment/$app" --timeout=90s && verify_service "$expected"; then
    echo "RELEASE HEALTHY $app $image"
  else
    k describe deployment "$app"
    k get pods -l "app=$app" -o wide
    echo "FAILED rollout; automatically rolling back to $previous"
    k rollout undo "deployment/$app"
    k rollout status "deployment/$app" --timeout=120s
    verify_service "$oldversion"
    echo "ROLLBACK VERIFIED $previous"
    exit 1
  fi
fi
k get deployments,pods,services -l "app=$app"
echo "Host NodePort: http://localhost:$port"
