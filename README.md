# Claude Ping

Claude Code의 권한 요청 및 AskUserQuestion을 팝업으로 알려주는 앱입니다.

**지원 환경:**
- macOS 터미널 (메뉴바 앱)
- VSCode (확장 프로그램)

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
- Homebrew (Swift 설치용)

## 설치

### 1. 다운로드

```bash
git clone https://github.com/Kimminchae-lab/claude-ping.git
cd claude-ping
```

### 2. 설치 스크립트 실행

```bash
chmod +x install.sh
./install.sh
```

### 3. 접근성 권한 허용

설치 후 **시스템 환경설정 > 개인정보 보호 및 보안 > 접근성**에서 ClaudeNotifier를 허용해주세요.

### 4. Claude Code Hook 설정

`~/.claude/settings.json` 파일을 열고 아래 내용을 추가하세요:

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

## 제거

```bash
./uninstall.sh
```

## VSCode 확장 설치

VSCode 사용자는 `vscode-extension` 폴더의 확장을 설치하세요:

```bash
cd vscode-extension
npm install
npm run compile
npm run package
```

생성된 `.vsix` 파일을 VSCode에서 설치:
- `Cmd+Shift+P` → "Install from VSIX" → 파일 선택

자세한 내용은 [vscode-extension/README.md](vscode-extension/README.md) 참고.

## 라이선스

MIT License
