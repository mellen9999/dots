#!/bin/sh
# timer wrapper: run the suite, scream once if the setup rotted.
O=$(sh "$HOME/.claude/selfcheck/run.sh" -q 2>&1) && exit 0
notify-send -u critical -a selfcheck "claude setup broken" "$O" 2>/dev/null
logger -t claude-selfcheck "$O"
exit 1
