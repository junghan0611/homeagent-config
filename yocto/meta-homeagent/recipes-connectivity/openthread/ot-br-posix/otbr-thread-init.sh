#!/bin/sh
# Thread 네트워크 자동 초기화 (첫 부팅 시)
# dataset이 없으면 새로 생성하고 Thread를 시작한다.
# 이미 dataset이 있으면 Thread만 시작한다.

MAX_RETRY=15
RETRY=0

# otbr-agent 소켓 대기
while [ $RETRY -lt $MAX_RETRY ]; do
    RESULT=$(ot-ctl state 2>&1 | sed -n '1p' | tr -d '\r')
    if [ -n "$RESULT" ] && ! echo "$RESULT" | grep -q "failed"; then
        break
    fi
    RETRY=$((RETRY + 1))
    sleep 2
done

if [ $RETRY -ge $MAX_RETRY ]; then
    echo "otbr-thread-init: otbr-agent not ready after $MAX_RETRY retries" >&2
    exit 1
fi

# dataset 존재 확인
DATASET=$(ot-ctl dataset active 2>&1 | sed -n '1p' | tr -d '\r')
if echo "$DATASET" | grep -q "NotFound"; then
    echo "otbr-thread-init: creating new Thread dataset..."
    ot-ctl dataset init new
    ot-ctl dataset commit active
else
    echo "otbr-thread-init: existing dataset found"
fi

# Thread 시작
STATE=$(ot-ctl state 2>&1 | sed -n '1p' | tr -d '\r')
if [ "$STATE" = "disabled" ] || [ "$STATE" = "detached" ]; then
    ot-ctl ifconfig up
    ot-ctl thread start
    echo "otbr-thread-init: Thread started"
else
    echo "otbr-thread-init: Thread already in state: $STATE"
fi

# leader 대기
RETRY=0
while [ $RETRY -lt $MAX_RETRY ]; do
    STATE=$(ot-ctl state 2>&1 | sed -n '1p' | tr -d '\r')
    if [ "$STATE" = "leader" ] || [ "$STATE" = "router" ]; then
        echo "otbr-thread-init: Thread state: $STATE"
        exit 0
    fi
    RETRY=$((RETRY + 1))
    sleep 2
done

echo "otbr-thread-init: Thread did not reach leader/router (state: $STATE)" >&2
exit 1
