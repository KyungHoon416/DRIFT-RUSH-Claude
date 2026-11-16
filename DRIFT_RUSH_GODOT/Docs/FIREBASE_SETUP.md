# FIREBASE SETUP

현재 상태: **Mock**입니다. 실제 Firebase 프로젝트에 연결하거나 배포한 적이 없습니다.
Firebase는 Godot용 공식 SDK가 없으므로 Unity SDK나 검증되지 않은 플러그인을 쓰지 않고, 공식 REST API를 `FirebaseAdapter.gd`에서 직접 호출합니다.

## 1. 프로젝트 만들기 (무료 Spark 플랜으로 시작 가능)
1. https://console.firebase.google.com 에서 프로젝트를 만듭니다.
2. Authentication → 로그인 방법 → **익명** 사용 설정
3. Firestore Database 생성 (리전 예: `asia-northeast3` 서울)
4. Realtime Database 생성 (presence용)
5. 프로젝트 설정 → 일반 → **웹 API 키**와 **프로젝트 ID**를 확인합니다.

> Cloud Functions 배포에는 **Blaze(종량제) 플랜**이 필요합니다. 비용이 생길 수 있으니 직접 결정하세요. 이 작업에서는 활성화하지 않았습니다.

## 2. 클라이언트 설정
```bash
cp Config/firebase_config.example.json Config/firebase_config.json
```
```json
{ "apiKey": "웹 API 키", "projectId": "프로젝트 ID", "functionsRegion": "asia-northeast3" }
```
- `Config/firebase_config.json`은 `.gitignore`에 있습니다. 웹 API 키는 비밀 키는 아니지만 커밋하지 않는 것을 권장합니다.
- 기기에서만 덮어쓰려면 `user://firebase_config.json`을 둬도 됩니다(우선 적용).
- 파일이 있으면 앱의 `Backend.mode`가 `firebase`가 되고, UI에 "Firebase 연결 설정됨"이 표시됩니다.
- **절대 넣지 말 것:** 서비스 계정 JSON, Admin SDK 키, `GAME_SERVER_SECRET`

## 3. 규칙과 Functions 배포
```bash
npm i -g firebase-tools
cd Backend
firebase login
firebase use --add                       # 프로젝트 선택
(cd functions && npm install && npm test)
firebase functions:secrets:set GAME_TOKEN_SECRET     # 임의의 긴 문자열
firebase functions:secrets:set GAME_SERVER_SECRET    # 게임 서버 전용
firebase deploy --only firestore:rules,database,functions
```
로컬 검증: `firebase emulators:start` (Auth/Functions/Firestore/RTDB 에뮬레이터 포트는 `firebase.json`에 정의)

## 4. API 요약
| 함수 | 호출자 | 설명 |
|---|---|---|
| createRoom({capacity, laps, mode, map, public}) | 로그인 사용자 | 6자리 코드(0/O/1/I 제외), 중복 참가 방지 |
| joinRoom({code}) | 로그인 사용자 | INVALID_CODE / ROOM_NOT_FOUND / ALREADY_IN_ROOM / RACE_STARTED / ROOM_FULL |
| leaveRoom() | 로그인 사용자 | 방장 이탈 시 방장 이전, 빈 방은 삭제 |
| setReady({ready}) | 로그인 사용자 | |
| startRace() | 방장 | 2명 이상 + 전원 준비 확인 후 HMAC 게임 토큰(2분) 발급 |
| reportRaceResult (HTTP) | **게임 서버만** (`x-game-server-key`) | 랩타임 타당성 검증 후 결과와 기록 저장 |
| listFriends() | 로그인 사용자 | |

## 5. 출시 전 보안 단계 (미완료)
- App Check (Play Integrity / App Attest): 네이티브 플러그인 필요
- Firestore/RTDB 규칙 에뮬레이터 테스트 (`@firebase/rules-unit-testing`)
- Apple/Google 로그인: 네이티브 Sign-In 플러그인으로 ID 토큰을 받고 `accounts:signInWithIdp`로 익명 계정에 연결
- Crashlytics/Analytics: Godot용 공식 SDK가 없어 Android/iOS 네이티브 플러그인 작성이 필요
