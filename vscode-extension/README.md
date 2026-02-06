# Claude Ping - VSCode Extension

VSCode용 Claude Code 알림 확장입니다.

## 기능

- Claude Code 권한 요청 시 VSCode 알림 표시
- AskUserQuestion 선택지를 알림으로 표시
- 알림에서 선택 시 터미널에 자동 입력
- "Other..." 버튼으로 터미널 포커스 (커스텀 입력)

## 설치

### 방법 1: VSIX 파일로 설치

```bash
cd vscode-extension
npm install
npm run compile
npm run package
```

생성된 `claude-ping-1.0.0.vsix` 파일을 VSCode에서 설치:
- VSCode에서 `Cmd+Shift+P` → "Install from VSIX" → 파일 선택

### 방법 2: 개발 모드로 실행

```bash
cd vscode-extension
npm install
npm run compile
```

VSCode에서 `F5`를 눌러 Extension Development Host 실행

## 사용법

1. macOS 앱 (ClaudeNotifier)과 함께 사용
2. 터미널에서 `claude` 명령어 실행
3. 권한 요청이나 질문이 오면 VSCode에 알림 표시
4. 알림에서 버튼 클릭 → 터미널에 자동 입력

## 설정

VSCode Settings에서 설정 가능:

- `claudePing.enabled`: 알림 활성화/비활성화 (기본: true)
- `claudePing.watchDirectory`: 알림 파일 감시 디렉토리 (기본: ~/.claude-notifier/queue)
