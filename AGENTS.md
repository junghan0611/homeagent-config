# HomeAgent Config - 에이전트 지침

@README.md

---

## 프로젝트 관리

### 이슈 트래킹 (beads_rust)

```bash
br list              # 이슈 목록
br show <issue-id>   # 이슈 상세
br create "제목"     # 이슈 생성
br update <id> -s in_progress  # 상태 변경
br close <id>        # 완료
br sync --flush-only # JSONL 동기화
```

### 현재 이슈

```
○ bd-21k - Yocto 빌드 환경 구축          ← 시작점
○ bd-21o - Go Core 설정
○ bd-o2i - Zig Core 템플릿화
○ bd-2a0 - Flutter eLinux 빌드 검증
○ bd-34t - Matter/Thread 통합
○ bd-2wc - Hailo-8 M.2 NPU 지원
```

---

## 에이전트 원칙

### 마음가짐

**"달에 보내는 임베디드 시스템"**

- 클라우드 없이 자립
- 프라이버시 보장
- 개인 에이전트와 협업 준비

### 핵심 규칙

1. **가설을 신뢰하지 마라** - 증거 첨부 필수
2. **추가보다 제거** - 복잡도는 버그의 온상
3. **자기 복구 가능한 상태머신** - 무한 대기/루프 금지

### 인바리언트 (절대 금지)

| 금지 | 허용 | 이유 |
|------|------|------|
| core/types에서 스레드 생성 | io/에서만 스레드 | 상태머신 결정론 |
| 콜백에서 HubState 직접 변경 | 콜백은 Event 생산만 | 단방향 흐름 |
| 클라우드 의존 로직 | 온디바이스 우선 | Data Privacy |

---

## 관련 프로젝트

| 프로젝트 | 위치 | 활용 |
|----------|------|------|
| kd-wallpad-app | `/home/junghan/repos/gh/kd-wallpad-app/` | Go Core, Flutter FFI |
| sks-hub-zig | `/home/junghan/repos/work/sks-hub-zig/` | Zig 상태머신 |
| kyungdong-rockchip | `/home/junghan/repos/work/kyungdong-rockchip/` | Matter/Thread |

---

## Landing the Plane (세션 종료)

```bash
git pull --rebase
br sync --flush-only
git add -A && git commit -m "작업 내용"
git push
git status  # "up to date with origin" 확인
```

**작업은 `git push` 성공 전까지 미완료**
