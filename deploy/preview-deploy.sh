#!/usr/bin/env bash
set -euo pipefail
umask 077

registry=ghcr.io/onnisama/course-video-intelligence

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

(( $# <= 1 )) || fail 'Expected at most one deployment target.'
target=${1:-preview}
compose_overrides=()
case $target in
    preview)
        base=/opt/course-video-integration
        project=course-video-integration
        port=18080
        export INTEGRATION_PORT=$port
        compose_name=deploy/compose.yaml
        active_override="$base/preview-images.yaml"
        ;;
    integration)
        base=/opt/course-video-prod-trial
        project=course-video-prod-trial
        port=18081
        compose_name=docker-compose.prod.yml
        compose_overrides=(-f "$base/loopback.yaml")
        active_override="$base/integration-images.yaml"
        ;;
    *) fail 'Unknown deployment target.' ;;
esac
endpoint="http://127.0.0.1:$port"

IFS=' ' read -r -t 15 revision compose_hash backend_digest web_digest actor || fail 'Incomplete deployment request.'
IFS= read -r -t 5 token || fail 'Missing registry credential.'
[[ $revision =~ ^[0-9a-f]{40}$ && $compose_hash =~ ^[0-9a-f]{64}$ &&
   $backend_digest =~ ^sha256:[0-9a-f]{64}$ && $web_digest =~ ^sha256:[0-9a-f]{64}$ &&
   $actor =~ ^[A-Za-z0-9-]+(\[bot\])?$ && -n $token ]] || fail 'Invalid deployment request.'

exec 9>"$base/$target-deploy.lock"
flock -n 9 || fail 'A deployment is already running for this target.'

source_path=$(< "$base/source-path")
compose_file="$source_path/$compose_name"
read -r installed_hash _ < <(sha256sum -- "$compose_file")
[[ $installed_hash == "$compose_hash" ]] || fail 'Server Compose file differs from the approved Compose in this commit.'

compose=(docker compose --project-name "$project" --env-file "$base/.env" -f "$compose_file" "${compose_overrides[@]}")
if ! "${compose[@]}" config --format json </dev/null | python3 -c '
import json
import sys

services = json.load(sys.stdin)["services"]
ports = services["web"].get("ports", [])
allowed = (
    len(ports) == 1
    and ports[0].get("host_ip") == "127.0.0.1"
    and str(ports[0].get("published")) == sys.argv[1]
    and ports[0].get("target") == 80
    and ports[0].get("protocol", "tcp") == "tcp"
    and not any(services[name].get("ports") for name in ("backend", "db"))
)
sys.exit(0 if allowed else 1)
' "$port"; then
    fail "Expected only 127.0.0.1:$port to be published for $target."
fi

tmp=$(mktemp -d "$base/.$target-deploy.XXXXXXXX")
backend="${registry}-backend@$backend_digest"
web="${registry}-web@$web_digest"
database_check='python -m app.database && python -m alembic current --check-heads'
rollback_needed=0

write_override() {
    printf 'services:\n  backend:\n    image: "%s"\n  web:\n    image: "%s"\n' "$2" "$3" > "$1"
}

start_application() {
    # Recreate Nginx after the backend so its upstream uses the current container address.
    "${compose[@]}" -f "$active_override" up -d --no-deps --no-build --pull never --wait --wait-timeout 60 backend </dev/null &&
        "${compose[@]}" -f "$active_override" up -d --no-deps --no-build --pull never --wait --wait-timeout 60 --force-recreate web </dev/null
}

check_http() {
    local home_status health_response
    home_status=$(curl -fsS --max-time 5 -o /dev/null -w '%{http_code}' "$endpoint/") &&
        health_response=$(curl -fsS --max-time 5 -w '\n%{http_code}' "$endpoint/api/health") &&
        [[ $home_status == 200 && $health_response == $'{"status":"ok"}\n200' ]]
}

finish() {
    local status=$?
    if (( rollback_needed )); then
        printf 'Restoring target=%s backend=%s web=%s\n' "$target" "$previous_backend" "$previous_web" >&2
        if mv -f -- "$tmp/rollback.yaml" "$active_override" && start_application &&
            check_application "$previous_backend" "$previous_web"; then
            printf '%s\n' 'Previous deployment restored. Deployment failed.' >&2
        else
            printf '%s\n' 'Deployment rollback failed. Administrator action required.' >&2
        fi
    fi
    rm -rf -- "$tmp"
    exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

running_image() {
    local service=$1 container reference actual_id reference_id
    container=$("${compose[@]}" ps -q "$service") || return 1
    [[ -n $container ]] || return 1
    reference=$(docker inspect --format '{{.Config.Image}}' "$container") || return 1
    # Restrict values to image references before writing them to Compose YAML.
    [[ $reference =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]*$ ]] || return 1
    actual_id=$(docker inspect --format '{{.Image}}' "$container") || return 1
    reference_id=$(docker image inspect --format '{{.Id}}' "$reference") || return 1
    [[ $actual_id == "$reference_id" ]] || return 1
    printf '%s\n' "$reference"
}

check_application() {
    check_http && [[ $(running_image backend) == "$1" && $(running_image web) == "$2" &&
        $("${compose[@]}" ps -q db) == "$db_before" ]]
}

db_before=$("${compose[@]}" ps -q db)
[[ -n $db_before ]] || fail 'Target database is not running.'
previous_backend=$(running_image backend) || fail 'Previous backend image is not available for rollback.'
previous_web=$(running_image web) || fail 'Previous web image is not available for rollback.'
check_http || fail 'Existing deployment is unhealthy. Check it before deploying.'
printf 'Current target=%s backend=%s web=%s\n' "$target" "$previous_backend" "$previous_web"
write_override "$tmp/rollback.yaml" "$previous_backend" "$previous_web"
write_override "$tmp/candidate.yaml" "$backend" "$web"

mkdir "$tmp/docker"
# A temporary config with an auth entry keeps Docker from auto-selecting a host credential helper.
printf '{"auths":{"ghcr.io":{}}}\n' > "$tmp/docker/config.json"
printf '%s' "$token" | docker --config "$tmp/docker" login ghcr.io --username "$actor" --password-stdin >/dev/null
unset token
for image in "$backend" "$web"; do
    docker --config "$tmp/docker" pull "$image" </dev/null
    [[ $(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image") == "$revision" ]] ||
        fail "Image revision does not match $revision: $image"
done
rm -rf -- "$tmp/docker"

# Run only read-only database checks with the candidate application image.
"${compose[@]}" -f "$tmp/candidate.yaml" run --no-deps --rm -T --pull never backend \
    sh -ec "$database_check" </dev/null

rollback_needed=1
mv -f -- "$tmp/candidate.yaml" "$active_override"
start_application
check_application "$backend" "$web" || fail 'Deployment HTTP, application image or database container check failed.'
printf '%s\n' 'Checking database from the running backend.'
"${compose[@]}" -f "$active_override" exec -T backend sh -ec "$database_check" </dev/null ||
    fail 'Running backend failed the database or migration check.'

rollback_needed=0
printf 'Deployed target=%s revision=%s backend=%s web=%s\n' "$target" "$revision" "$backend" "$web"
