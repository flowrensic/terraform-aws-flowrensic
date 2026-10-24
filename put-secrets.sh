#!/usr/bin/env bash
# Puts secrets into SSM Parameter Store from a local file, outside Terraform.
#
#   put-secrets.sh [--region REGION] [--restart CLUSTER SERVICE] FILE
#
# FILE has one line per parameter, NAME=VALUE, where NAME is the SSM parameter
# name and VALUE is the rest of the line. Lines that start with # and empty
# lines are skipped. Each value is written as a SecureString, replacing the old
# one. A value is passed to the aws command in a temporary file, never on its
# command line. With --restart the ECS service is started again and the script
# waits until it is stable, so the server reads the new values.
set -euo pipefail

usage() {
  echo "usage: $0 [--region REGION] [--restart CLUSTER SERVICE] FILE" >&2
  exit 2
}

region_args=()
cluster=""
service=""
while [ $# -gt 1 ]; do
  case "$1" in
    --region) region_args=(--region "$2"); shift 2 ;;
    --restart) cluster="$2"; service="$3"; shift 3 ;;
    *) usage ;;
  esac
done
[ $# -eq 1 ] || usage
file="$1"
[ -r "$file" ] || { echo "$0: cannot read $file" >&2; exit 1; }

umask 077
value_file="$(mktemp)"
trap 'rm -f "$value_file"' EXIT

count=0
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|'#'*) continue ;;
  esac
  name="${line%%=*}"
  if [ "$name" = "$line" ] || [ -z "$name" ]; then
    echo "$0: a line of $file has no NAME=VALUE" >&2
    exit 1
  fi
  printf '%s' "${line#*=}" > "$value_file"
  aws ${region_args[@]+"${region_args[@]}"} ssm put-parameter --name "$name" --type SecureString --overwrite \
    --value "file://$value_file" --output text > /dev/null
  echo "put $name"
  count=$((count + 1))
done < "$file"
echo "put $count parameters"

if [ -n "$cluster" ]; then
  aws ${region_args[@]+"${region_args[@]}"} ecs update-service --cluster "$cluster" --service "$service" \
    --force-new-deployment --output text > /dev/null
  echo "started $service again, waiting until it is stable"
  aws ${region_args[@]+"${region_args[@]}"} ecs wait services-stable --cluster "$cluster" --services "$service"
  echo "$service is stable"
fi
