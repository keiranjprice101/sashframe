#!/usr/bin/env bash
# Configuration-only tests: no appliance, credentials, containers or sudo needed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
ansible-playbook -i localhost, ansible/site.yml --syntax-check
ansible-playbook -i localhost, ansible/tests/calendar-config.yml \
  -e sashframe_shifter_drive_folder_id=fixture
ansible-playbook -i localhost, ansible/tests/calendar-config.yml \
  -e sashframe_calendar_provider=google -e sashframe_google_calendar_id=fixture \
  -e expected_provider=google
failure_log="$(mktemp)"
trap 'rm -f "$failure_log"' EXIT
expect_invalid() {
  if ansible-playbook -i localhost, ansible/tests/calendar-config.yml "$@" >"$failure_log" 2>&1; then
    echo "Invalid calendar configuration was accepted" >&2
    exit 1
  fi
  if ! grep -q 'Choose shifter with a Drive folder ID' "$failure_log"; then
    cat "$failure_log" >&2
    exit 1
  fi
}
expect_invalid -e sashframe_calendar_provider=invalid -e expected_provider=invalid
expect_invalid -e sashframe_calendar_provider=google -e expected_provider=google
expect_invalid -e sashframe_calendar_provider=shifter
expect_invalid -e sashframe_calendar_provider=google -e sashframe_google_calendar_id=primary -e expected_provider=google
printf 'Provider configuration tests passed (both providers and four invalid configurations).\n'
python3 ansible/tests/test_deployment.py
