#!/bin/sh
# OTBR SRP server 자동 활성화
# otbr-agent 시작 후 SRP server를 enable하여
# Matter commissioning 시 SRP→mDNS 체인이 동작하도록 함

MAX_RETRY=10
RETRY=0

while [ $RETRY -lt $MAX_RETRY ]; do
    STATE=$(ot-ctl srp server state 2>/dev/null | head -1)
    if [ "$STATE" = "disabled" ]; then
        ot-ctl srp server enable
        echo "otbr-srp-enable: SRP server enabled"
        exit 0
    elif [ "$STATE" = "running" ]; then
        echo "otbr-srp-enable: SRP server already running"
        exit 0
    fi
    RETRY=$((RETRY + 1))
    sleep 2
done

echo "otbr-srp-enable: failed after $MAX_RETRY retries" >&2
exit 1
