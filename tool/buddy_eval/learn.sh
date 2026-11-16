#!/usr/bin/env bash
# The learning loop: fetch the feedback from the server, turn every new
# thumbs-down into a test case and show what people disliked most.
#
#   tool/buddy_eval/learn.sh root@SERVER
#
# Then review tool/buddy_eval/cases_feedback.dart and run the catalog
# (see test/buddy_eval_run_test.dart). Run it once a week.
set -euo pipefail
cd "$(dirname "$0")/../.."
server="${1:?Server angeben, z. B. root@1.2.3.4}"
mkdir -p build/buddy_eval
ssh "$server" "cd /opt/ahead/deploy && docker compose exec -T server cat /app/.data/feedback.jsonl 2>/dev/null || true" \
  > build/buddy_eval/feedback.jsonl
dart run tool/buddy_eval/feedback_to_cases.dart build/buddy_eval/feedback.jsonl --write
git --no-pager diff --stat tool/buddy_eval/cases_feedback.dart || true
