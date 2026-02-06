# Claude Ping

Claude Code의 권한 요청 및 AskUserQuestion을 macOS 팝업으로 알려주는 메뉴바 앱입니다.

## 기능

- Claude Code 권한 요청 시 팝업 알림
- AskUserQuestion 선택지를 팝업으로 표시
- 팝업에서 선택 시 터미널에 자동 입력
- "Other..." 버튼으로 커스텀 응답 입력 가능
- 터미널 전환 시 팝업 자동 닫힘
- 부팅 시 자동 시작

## 요구사항

- macOS 12.0+
- Swift 5.5+
- Node.js (hook 스크립트용)

## 설치

```bash
chmod +x install.sh
./install.sh
```

## Claude Code Hook 설정

`~/.claude/settings.json`에 추가:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion|Bash|Edit|Write|Read",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude-notifier/bin/claude-permission-prompt"
          }
        ]
      }
    ]
  }
}
```

## 접근성 권한

첫 실행 시 **시스템 환경설정 > 개인정보 보호 및 보안 > 접근성**에서 ClaudeNotifier를 허용해야 합니다.

## 제거

```bash
./uninstall.sh
```

## 라이선스

MIT License
