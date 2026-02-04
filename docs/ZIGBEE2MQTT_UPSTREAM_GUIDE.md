# sks-hub-zig → zigbee2mqtt Upstream 기여 가이드

## 개요

sks-hub-zig의 Zigbee 디바이스 지원을 zigbee2mqtt 오픈소스 프로젝트에 upstream으로 기여하기 위한 작업 지침입니다.

## zigbee2mqtt 아키텍처

```
zigbee2mqtt
├── lib/
│   ├── extension/          # 기능 확장
│   ├── model/              # 디바이스 모델
│   └── zigbee/             # Zigbee 프로토콜
├── node_modules/
│   └── zigbee-herdsman-converters/  # 디바이스 컨버터 (핵심!)
└── data/
    └── configuration.yaml
```

## 기여 유형별 작업

### 1. 새 디바이스 지원 추가 (가장 일반적)

**대상 리포:** [zigbee-herdsman-converters](https://github.com/Koenkk/zigbee-herdsman-converters)

**작업 단계:**

```bash
# 1. Fork & Clone
git clone https://github.com/YOUR_USERNAME/zigbee-herdsman-converters
cd zigbee-herdsman-converters

# 2. 브랜치 생성
git checkout -b add-device-YOUR_DEVICE_MODEL

# 3. 디바이스 정의 추가
# src/devices/ 디렉토리에서 제조사별 파일 편집
```

**디바이스 정의 예시 (src/devices/tuya.ts):**

```typescript
{
    zigbeeModel: ['TS0001'],  // Zigbee interview에서 얻은 모델명
    model: 'TS0001',
    vendor: 'Tuya',
    description: 'Smart switch',
    extend: [tuya.modernExtend.tuyaOnOff()],
    // 또는 직접 정의:
    fromZigbee: [fz.on_off],
    toZigbee: [tz.on_off],
    exposes: [e.switch()],
}
```

**필요한 정보 수집:**

```bash
# zigbee2mqtt 로그에서 디바이스 interview 데이터 확인
journalctl -u zigbee2mqtt | grep -A 50 "Interview"
```

필요 정보:
- `zigbeeModel`: 디바이스가 보고하는 모델 ID
- `manufacturerName`: 제조사 이름
- Cluster 목록 (input/output)
- Attribute 목록

### 2. 기존 디바이스 기능 개선

**작업 파일:** `src/devices/{vendor}.ts`

```typescript
// 기존 디바이스에 기능 추가
{
    zigbeeModel: ['existing_model'],
    model: 'existing_model',
    // ... 기존 설정
    exposes: [
        e.switch(),
        e.power(),           // 추가
        e.energy(),          // 추가
    ],
    fromZigbee: [fz.on_off, fz.metering],  // 컨버터 추가
}
```

### 3. 커스텀 컨버터 작성

복잡한 디바이스는 커스텀 컨버터 필요:

**src/converters/fromZigbee.ts:**

```typescript
export const myCustomConverter = {
    cluster: 'manuSpecificTuya',
    type: ['commandDataResponse', 'commandDataReport'],
    convert: (model, msg, publish, options, meta) => {
        const dp = msg.data.dpValues[0].dp;
        const value = msg.data.dpValues[0].data;

        switch (dp) {
            case 1:
                return {state: value[0] === 1 ? 'ON' : 'OFF'};
            case 2:
                return {brightness: value[0]};
        }
    },
};
```

### 4. PR 제출 체크리스트

- [ ] `npm run lint` 통과
- [ ] `npm run test` 통과
- [ ] 디바이스 사진 (있으면)
- [ ] 실제 테스트 완료 증빙
- [ ] README/CHANGELOG 업데이트

**PR 템플릿:**

```markdown
## Device Support: [Vendor] [Model]

### Device Info
- Vendor:
- Model:
- Description:

### Tested Features
- [x] On/Off
- [x] Brightness
- [ ] Color temperature

### Evidence
- Interview log: (gist link)
- Photo: (image)
```

## sks-hub-zig 코드 활용

### Zig → TypeScript 변환 가이드

**sks-hub-zig의 디바이스 정의:**
```zig
const TuyaSwitch = struct {
    model_id: []const u8 = "TS0001",
    clusters: []const Cluster = &[_]Cluster{
        .{ .id = 0x0006, .name = "on_off" },
    },
};
```

**zigbee-herdsman-converters 형식:**
```typescript
{
    zigbeeModel: ['TS0001'],
    model: 'TS0001',
    vendor: 'Tuya',
    extend: [tuya.modernExtend.tuyaOnOff()],
}
```

### 클러스터 매핑

| Cluster ID | Name | zigbee2mqtt |
|------------|------|-------------|
| 0x0006 | On/Off | `fz.on_off`, `tz.on_off` |
| 0x0008 | Level Control | `fz.brightness`, `tz.light_brightness` |
| 0x0300 | Color Control | `fz.color_colortemp`, `tz.light_color` |
| 0x0702 | Metering | `fz.metering` |
| 0xEF00 | Tuya Specific | `fz.tuya_data_point_dump` |

## 추천 작업 순서

1. **디바이스 목록 정리**
   - sks-hub-zig에서 지원하는 디바이스 목록
   - zigbee2mqtt 미지원 디바이스 식별

2. **Interview 데이터 수집**
   - 각 디바이스의 Zigbee interview 로그
   - Cluster/Attribute 정보

3. **컨버터 작성**
   - zigbee-herdsman-converters 포크
   - 디바이스별 PR 생성

4. **테스트 및 문서화**
   - 실제 하드웨어 테스트
   - 사용 가이드 작성

## 참고 자료

- [zigbee2mqtt 공식 문서](https://www.zigbee2mqtt.io/)
- [디바이스 지원 추가 가이드](https://www.zigbee2mqtt.io/advanced/support-new-devices/01_support_new_devices.html)
- [zigbee-herdsman-converters](https://github.com/Koenkk/zigbee-herdsman-converters)
- [Zigbee Cluster Library (ZCL)](https://zigbeealliance.org/developer_resources/)

## 연락처

zigbee2mqtt Discord: https://discord.gg/zigbee2mqtt
