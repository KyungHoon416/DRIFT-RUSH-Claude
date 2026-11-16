# QA REPORT — 2026-11-16

실행 환경: Linux x86_64 클라우드 컨테이너, Godot 4.7.2.stable.official.ed1daf0bf.
**실기기(Android/iOS)는 없었습니다.** 아래 표의 "미검증"은 실제로 확인하지 못했다는 뜻입니다.

## 1. 요약
| 구분 | 결과 |
|---|---|
| 스크립트·씬 로드 검사 (`Tools/CheckAll.tscn`) | **80개 파일, 실패 0** |
| GDScript 단위·통합 테스트 (`Tests/TestRunner.tscn`) | **43개 테스트, 248개 검사, 실패 0** |
| 2프로세스 LAN 레이스 (지연 150ms, 손실 3%) | **통과**: 양쪽 결과 일치, 원격 카트 약 970m 보간 |
| 경기 중 클라이언트 이탈 | **통과**: 호스트가 경기를 끝내고 이탈자를 DNF 처리 |
| Cloud Functions 방 규칙 (`npm test`) | **6/6 통과** |
| Android 디버그 APK 내보내기 | **통과**: apksigner v2/v3 서명 검증, arm64-v8a, VIBRATE·INTERNET 권한 확인 |
| iOS Xcode 프로젝트 내보내기 | **부분**: Linux에서 Xcode 프로젝트까지만 생성, .ipa 빌드·서명은 macOS 필요 |
| 실제 렌더링 스크린샷·데모 영상 | **통과**: Xvfb + OpenGL(Compatibility)에서 촬영 |
| 실기기 기울기·진동·FPS | **미검증** |

## 2. 상세 (통과 / 실패 / 미검증)
### 물리·레이스 (실제 SakuraValley 트랙과 충돌 메쉬 사용)
| 항목 | 테스트 | 결과 |
|---|---|---|
| 카운트다운 중 정지, 이후 자동 가속, 최고속 근접, 최고속 초과 없음 | test_auto_acceleration_reaches_top_speed | 통과 |
| 좌우 조향 방향, 차체 회전 = 충돌체 회전 | test_steering_left_right | 통과 |
| 브레이크 감속, 떼면 자동 가속 재개 | test_brake_and_release_resumes | 통과 |
| 벽 충돌: 감속, `impact` 신호, 진동 요청, 벽 관통 없음 | test_wall_collision_slows_and_emits_impact | 통과 |
| 부스터: 게이지 소모, 속도 상승, 지속시간 후 종료, 빈 게이지면 미발동 | test_boost_increases_speed_then_expires | 통과 |
| 드리프트 시작·미끄러짐·게이지 충전·미니부스트 | test_drift_engages_charges_and_rewards | 통과 |
| 맵 밖 추락 시 안전 지점 복구 | test_respawn_after_falling | 통과 |
| 체크포인트 순서, 랩, 완주, 짧은 랩 거부, 출발선 진행도 처리 | test_lap_manager.* | 통과 |
| 역주행 경고 | test_wrong_way_detection | 통과 |
| **3랩 완주 (연습, 오토파일럿)**: 100.85초, 베스트랩 32.95초, 체크포인트 24회 통과, 복구 0회 | test_practice_three_laps_sakura | 통과 |
| 8인 스피드전 순위 1~8, 완주 시간순 정렬 | test_speed_race_vs_7_bots_ranking | 통과 |
| 아이템전 (Neon City, 봇 3): 상자 생성, 완주 | test_item_race_neon_city_runs | 통과 |
| 트랙: 길이, 체크포인트 8개(6개 이상), 곡률 반경, 그리드가 도로 위인지, 모든 측면 레이가 벽에 막히는지 | test_track.* | 통과 |

### 입력·피드백
| 항목 | 결과 |
|---|---|
| 기울기 수학(롤 계산, 데드존, 감도 0.5~2.0, 반전, 중립 보정, 스무딩, 복귀 후 억제) | 통과 (시뮬레이션한 중력 벡터 사용) |
| 센서 없음(PC) → 조향 0, 키보드 대체 | 통과 |
| 진동: 약한 충돌 무시, 300ms 쿨다운, 강도 비례, 사용자 강도 반영, OFF 시 비활성 | 통과 (로직만. 실제 진동은 미검증) |
| 터치 DRIFT 누름/뗌 → 액션 전달 | 통과 (가짜 터치 이벤트) |
| **실기기 기울기 축·부호** | **미검증**: 기기와 방향마다 다를 수 있어 축(x/y)·반전 옵션을 제공 |
| **실기기 진동 (Android VIBRATE / iOS)** | **미검증** |

### UI
| 항목 | 결과 |
|---|---|
| 11개 화면 로드·구성 (Bootstrap, Login, Lobby, ModeSelect, RoomLobby, MapSelect, Garage, TiltTutorial, Settings, Profile, RaceResult) | 통과 |
| 버튼 연결: PLAY→모드 선택, FRIENDS→방, GARAGE, SETTINGS, 연습 시작→레이스 | 통과 |
| 존재하지 않는 방 코드 오류 문구 | 통과 |
| 맵 선택 저장 | 통과 |
| HUD 배치(DRIFT 우하단, BRAKE 좌하단, 미니맵 우상단), 싱글 일시정지/재개 | 통과 |
| 방 가득 참 / 이미 시작 / 중복 참가 / 방장 이탈 시 이전(Mock·Functions 로직) | 통과 |
| 다양한 화면비·노치 Safe Area | 부분: 1280×720에서만 렌더링 확인. Safe Area 코드는 있으나 실기기 미검증 |

### 성능
| 항목 | 결과 |
|---|---|
| 모바일 FPS | **미측정** (실기기 없음) |
| 품질 프리셋(낮음/중간/높음: 그림자, 파티클, 나무 밀도, 글로우, MSAA, 렌더 스케일), FPS 30/60 | 구현됨, 효과는 미측정 |
| 드로우콜 절감: 나무·덤불·건물에 MultiMesh 사용 | 구현됨 |

## 3. 알려진 경고
- 테스트 종료 시 "ObjectDB instances leaked" 경고가 뜹니다. 테스트 직후 바로 종료하면서 해제 대기 중인 노드가 남아 생기는 것이고, 게임 실행 중에는 문제가 없습니다.
- `test_corrupt_settings` 실행 중 ConfigFile 파싱 오류 로그가 찍힙니다. 손상 파일을 일부러 만든 테스트라서 정상입니다.

## 4. 실기기 테스트 체크리스트 (다음 단계)
1. `adb install -r Build/android/DriftRush-debug.apk` 후 가로 모드 확인
2. TUTORIAL에서 오른쪽으로 기울였을 때 조향 값이 +인지 확인. 반대면 "좌우 반전", 반응이 없으면 "센서 축 y"
3. 벽 충돌 시 진동, 설정에서 진동 OFF 시 미발생, 진동 테스트 버튼
4. 낮음/중간/높음 품질별 FPS 기록 (`Engine.get_frames_per_second()`)
5. 백그라운드 전환 후 복귀: 일시정지 메뉴 표시, 조향 튐 없음
6. 같은 Wi-Fi에서 기기 2대로 LAN 방 대전
