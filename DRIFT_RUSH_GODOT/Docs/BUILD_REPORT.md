# BUILD REPORT — 2026-11-16

## 환경
| 항목 | 값 |
|---|---|
| OS | Linux 6.18 x86_64 (클라우드 컨테이너, GPU 없음) |
| Godot | 4.7.2.stable.official.ed1daf0bf (GitHub 공식 릴리스 `Godot_v4.7.2-stable_linux.x86_64.zip`) |
| Export templates | 4.7.2.stable (공식 `.tpz`) |
| Android SDK | cmdline-tools 11076708, build-tools 35.0.1, platform android-35, platform-tools |
| Java | OpenJDK 21.0.12 |
| Node | 22.23 (Functions 테스트용, 런타임 목표는 Node 20) |
| 렌더링 검증 | Xvfb + Mesa llvmpipe, `--rendering-method gl_compatibility` |
| Blender / Xcode / 실기기 | 없음 |

## 명령과 결과
| 명령 | 결과 |
|---|---|
| `godot --headless --path . --import` | 성공 |
| `godot --headless --path . res://Tools/CheckAll.tscn` | 80개 파일, 실패 0 |
| `godot --headless --fixed-fps 60 --path . res://Tests/TestRunner.tscn` | 43개 테스트, 248개 검사, 실패 0 (약 19초) |
| `Tools/run_net_test.sh 150 0.03` | host exit 0 / client exit 0 |
| `Tools/run_net_test.sh 0 0 12` | host exit 0 / client exit 0 (이탈자 DNF) |
| `cd Backend/functions && npm test` | pass 6 / fail 0 |
| `node --check Backend/functions/index.js` | 문법 OK (의존성 미설치, 배포 안 함) |
| `godot --headless --path . --export-debug "Android" Build/android/DriftRush-debug.apk` | **성공**, 35.4MB |
| `apksigner verify --verbose` | Verifies (v2, v3) |
| `aapt2 dump badging` | package `com.driftrush.kartracing`, versionName 0.3.0, arm64-v8a, 권한 INTERNET/VIBRATE/ACCESS_NETWORK_STATE/ACCESS_WIFI_STATE |
| `godot --headless --path . --export-debug "iOS" ...` (임시 Team ID) | Xcode 프로젝트 생성 성공. 경고: ".ipa can only be built on macOS". 저장소의 Team ID는 비워 둠 |
| `godot --headless --path . --export-release "Linux" Build/linux/DriftRush.x86_64` | 성공 (데스크톱 실행 파일) |
| Movie Maker `--write-movie` (30fps, 900프레임) | `Docs/demo/drift_rush_demo.mp4` |

## 산출물
- `Build/android/DriftRush-debug.apk`: 디버그 키스토어로 서명한 테스트용 빌드(스토어 배포용 아님). SHA-256 `0f9aaa09a5c33d202029c2366ffc801c96ab91b0c40f35eb40f5922d09cfd0fe`
- iOS Xcode 프로젝트: 크기 때문에(436MB) 저장소와 ZIP에 넣지 않았습니다. macOS에서 다시 생성하세요.
- `Build/`는 `.gitignore`에 포함되어 있습니다. APK는 별도 ZIP으로 전달합니다.

## 한계
- AAB(Gradle 빌드)는 시도하지 않았습니다. Gradle 빌드 템플릿 설치와 Google Maven 접근이 필요합니다.
- 실기기에 설치·실행해 보지 않았습니다.
- 네트워크 정책 변경: Android SDK를 받기 위해 이 환경에 `dl.google.com`을 허용 호스트로 추가했습니다(사용자 승인).
