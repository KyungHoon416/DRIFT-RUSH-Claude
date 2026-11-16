# ARCHITECTURE

## 1. 클라이언트 (Godot 4.7.2, GDScript)

### 오토로드
| 이름 | 파일 | 책임 |
|---|---|---|
| SaveSettings | Scripts/Core/SaveSettings.gd | `user://settings.cfg` 저장/로드, 값 범위 보정, 손상 파일 백업 후 기본값으로 시작, FPS·오디오 버스 적용 |
| GameFlow | Scripts/Core/GameFlow.gd | 씬 라우팅, `race_config`, 입력 액션 등록, 품질 프리셋, Safe Area 계산 |
| Haptics | Scripts/Feedback/Haptics.gd | `Input.vibrate_handheld(ms, amplitude)`, 300ms 쿨다운, 약한 충돌 무시, 사용자 ON/OFF·강도 |
| AudioFeedback | Scripts/Feedback/AudioFeedback.gd | 효과음·엔진·드리프트 루프·BGM을 코드로 합성 (외부 오디오 에셋 없음) |
| Backend | Scripts/Backend/BackendService.gd | `FirebaseAdapter`(REST)와 `MockBackend` 중 하나를 고르는 파사드 |
| Net | Scripts/Net/NetworkTransport.gd | ENet LAN 로비·레이스 동기화 |

### 레이스 구성 (`Scenes/Race/RaceWorld.tscn`)
```
RaceWorld (RaceWorld.gd)
├─ SakuraValley | NeonCity (TrackBuilder 하위 클래스)  ← Curve3D → 도로/연석/벽 메쉬 + 충돌, 체크포인트, 장식
├─ RaceManager      카운트다운 · 타이머 · LapManager(카트별) · 순위 · 역주행 · 복구 · 완주/DNF
├─ KartBase × N     KartController(CharacterBody3D) + KartModel + 드라이버(PlayerInput | AIDriver | RaceSession)
├─ ChaseCamera      스무딩 추적, 벽 레이캐스트, 속도 FOV
├─ ItemManager      (아이템전만) 상자 · 미사일 · 실드 · 터보 · 함정
├─ RaceSession      (온라인만) 스냅샷 보간, 호스트 결과 브로드캐스트
└─ RaceHUD          CanvasLayer: 순위 · 랩 · 미니맵 · 속도/게이지 · TouchControls · 일시정지
```

### 카트 물리 (KartController)
CharacterBody3D 기반 아케이드 모델입니다. 물리 프레임마다 아래 순서로 계산합니다.
1. 타이머 갱신 (스핀, 실드, 무적, 아이템 쿨다운)
2. 종방향: 자동 가속 / 브레이크 / 부스트 보너스 / 노면 이탈 감속
3. `DriftSystem` (순수 로직): 시작 조건, 충전, 보상 단계
4. 조향: 속도 비례 회전 + 고속 감쇠, 드리프트 중 회전 보너스
5. 그립: 진행 방향(`travel_heading`)이 차체 방향을 그립 비율로 따라가며, 드리프트 중 그립을 낮춰 미끄러짐 표현
6. 중력 → `move_and_slide()` → 충돌 응답 (벽: 감속과 벽면 방향으로 꺾기, 카트: 감속과 밀어내기). 종류별 0.25초 쿨다운 후 `impact` 신호 발생

시각 모델(`KartModel`)은 바퀴 회전·앞바퀴 조향·드리프트 요(yaw)·기울기·경사면 피치를 표현합니다. 충돌체는 차체와 같은 heading으로 회전합니다.

### 입력
- `PlayerInput`: 키보드/터치 액션(우선) → 기울기(`TiltSteering`, `control_mode=="tilt"`이고 센서 값이 있을 때)
- `TouchControls`: 멀티터치 인덱스를 직접 추적합니다(Godot Button은 동시 터치를 지원하지 않음). InputMap 액션을 누르고 떼며, 앱이 백그라운드로 가면 눌린 액션을 모두 해제합니다.
- `TiltSteering`: `roll = atan2(g[axis], sqrt(g.other² + g.z²))`로 계산합니다. 중립 보정, 데드존, 감도, 반전, 스무딩(시간 상수), 복귀 후 0.3초 입력 억제를 지원합니다.

## 2. 네트워크

### 현재 (동작 검증됨)
```
 클라이언트 ──(20Hz: 자기 카트 상태)──▶ 서버 ── RaceSession.validate (속도·순간이동·트랙 이탈) ─┐
      ▲                                     │  거부 시 _correct(pos, heading) 로 위치 되돌림 ◀──┘
      └──(20Hz: 모든 카트 스냅샷 + 서버 시각)──┘
 서버: RaceManager(체크포인트/랩/완주/DNF), ItemManager(상자/아이템/명중) 권한 판정
       결과·아이템 이벤트는 reliable RPC로 전파
```
- 서버 형태 두 가지: **LAN 방장 호스트**(방장도 플레이), **전용 헤드리스 서버**(`-- --server`, 플레이어 아님, 전원 READY 시 자동 시작, 경기 후 대기 상태로 복귀)
- 방 찾기: 호스트가 UDP 7779로 1초마다 비콘(`DRIFTRUSH1|코드|포트|…`)을 브로드캐스트합니다. 참가자는 6자리 코드로 IP를 찾습니다(`LanDiscovery`).
- 온라인 아이템: 클라이언트는 사용 "요청"만 보냅니다. 서버가 소지 여부·쿨다운·명중·실드를 판정하고 `box/use/missile/trap/end/hit/blocked` 이벤트를 보내면, 클라이언트는 미사일·함정을 시각용으로만 그립니다.
- 보간: 서버 시각 기준 120ms 지연 렌더링, 스냅샷 사이 선형 보간, 패킷이 늦으면 최대 0.25초 외삽
- 시뮬레이션 테스트용 조건: `Net.sim_latency_ms`, `Net.sim_loss`
- 입력 검증: 상태 값 범위 제한(속도 상한 등), 최소 랩타임 검사(`track_length/60`)
- 한계: 카트 물리는 여전히 각 클라이언트가 계산합니다. 서버는 그 결과가 물리적으로 가능한지만 검증합니다(순간이동·과속·트랙 이탈 차단). 미세한 속도 조작이나 라인 최적화 같은 정교한 치트는 막지 못합니다. LAN 방장 호스트가 나가면 경기가 끝납니다(전용 서버는 해당 없음).

### 다음 단계 (미구현)
- 서버가 **입력**을 받아 직접 시뮬레이션하고(완전 서버 권한), 클라이언트는 예측과 재조정을 합니다.
- 접속 흐름: Firebase ID 토큰 → Cloud Function `startRace`가 HMAC 서명된 단기 게임 토큰 발급 → 게임 서버가 토큰을 검증한 뒤 ENet 접속을 받음
- 결과: 게임 서버만 `reportRaceResult`(공유 비밀 헤더)로 기록합니다. 클라이언트가 보낸 rank/coins/finish_time은 저장하지 않습니다.
- 배포: UDP가 필요하므로 Cloud Run/Functions가 아니라 VM(GCE e2-small 등)이나 게임 서버 호스팅이 필요합니다. 비용이 발생하므로 승인 전에는 생성하지 않습니다.

## 3. 백엔드 (Firebase)
| 서비스 | 용도 | 상태 |
|---|---|---|
| Auth (Identity Toolkit REST) | 익명 로그인, 토큰 갱신 | 코드 작성, 실 프로젝트 미검증 |
| Firestore | users/{uid} 프로필, rooms/{code}, results, records | 규칙 작성, 미배포 |
| RTDB | presence `/status/{uid}` | 규칙 작성, 클라이언트 연동 미구현 |
| Cloud Functions | createRoom/joinRoom/leaveRoom/setReady/startRace/reportRaceResult/listFriends | 코드와 순수 로직 테스트 작성, 미배포 |
| Crashlytics/Analytics | Godot 공식 SDK 없음 | 미적용 (네이티브 플러그인 필요) |

Firebase에는 프레임 단위 위치를 절대 기록하지 않습니다.
