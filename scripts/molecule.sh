#!/usr/bin/env bash
# Run `molecule test` for an Ansible role inside a container, against the host Docker.
#   molecule.sh [role]     default: linux-hardening
# The runner image needs both Python (molecule/ansible) and the docker CLI (the docker
# connection plugin shells out to it), so it starts from docker:cli and adds Python.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLE="${1:-linux-hardening}"
host_root="$ROOT"
if command -v cygpath >/dev/null 2>&1; then host_root="$(cygpath -w "$ROOT")"; fi

PIP_PKGS='ansible-core==2.17.7 molecule==24.12.0 molecule-plugins[docker]==23.6.0 docker==7.1.0 requests<2.33'

MSYS_NO_PATHCONV=1 exec docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${host_root}:/src" -w "/src/ansible/roles/${ROLE}" \
  -e ANSIBLE_COLLECTIONS_PATH=/src/ansible/.collections \
  -e ANSIBLE_FORCE_COLOR=0 -e PY_COLORS=0 \
  docker:27-cli sh -c "apk add --no-cache -q python3 py3-pip >/dev/null && \
    pip install -q --break-system-packages --root-user-action=ignore $(printf "'%s' " $PIP_PKGS) && \
    molecule test"
