---
version: 1.0.0
nova_compat: ">=5.22.0"
last_review_commit: f9fa5bca21ce
---

# Nova Self-Audit Rules

`/nova:audit-self` 가 사용하는 정적 보안 룰셋. 5 카테고리 × 6~10 룰 = 33 룰 (v1.0.0 기준).

## 룰 스키마

각 룰은 다음 7 필수 필드를 갖는다 (`tests/test-audit-self.sh` 가 자동 검증):

| 필드 | 타입 | 형식 | 설명 |
|------|------|------|------|
| `id` | string | `R-{CATEGORY}-{NNN}` | 룰 고유 ID. 정규식 `^R-(PLUGIN\|HOOKS\|AGENTS\|SKILLS\|COMMANDS)-\d{3}$` |
| `category` | enum | 5종 중 1 | `plugin` / `hooks` / `agents` / `skills` / `commands` |
| `severity` | enum | 3단 | `Critical` / `Warning` / `Info` |
| `condition` | bash 1-liner | grep/awk/find ERE | 종료 코드 0 = 위반 발견 |
| `normal_example` | string | 코드 스니펫 | 룰을 통과하는 정상 케이스 |
| `risk_example` | string | 코드 스니펫 | 룰에 걸리는 위험 케이스 |
| `mitigation` | string | 자유 텍스트 1~3 문장 | 권장 수정 방향 |

## Source Mapping (ECC AgentShield 영감 카테고리 매핑)

Nova v5.22.0은 ECC AgentShield 102룰 모두를 일대일 흡수하지 않는다. **응집형 정체성 보호** 원칙에 따라 ECC 룰을 **카테고리 그룹으로 압축**하여 Nova 적용 가능 여부만 매핑한다. 102룰 전체 분류는 v5.23.0에서 검토.

| ECC 그룹 | 룰 추정 수 | Nova 분류 | Nova 룰 ID 매핑 |
|---------|-----------|-----------|-----------------|
| Settings Drift (settings.json 키 누출, 권한 과다) | ~12 | (a) Static OK | R-PLUGIN-001~003 |
| Hooks Injection (eval/sed `$VAR`/curl pipe-bash) | ~15 | (a) Static OK | R-HOOKS-001~007 |
| Hooks Privilege Escalation (sudo/chmod 777) | ~8 | (b) Dynamic Required | Known Gap |
| Agent Permission Overscope (Edit/Write/Bash 과다) | ~10 | (a) Static OK | R-AGENTS-001~004 |
| Secrets in Config (api_key/token/password 인라인) | ~10 | (a) Static OK | R-PLUGIN-004~006, R-SKILLS-001 |
| MCP Tool Overflow (>80 tools/server) | ~6 | (b) Dynamic Required | Known Gap (런타임 카운트 필요) |
| Skill External Call (외부 네트워크) | ~8 | (a) Static OK | R-SKILLS-002~004 |
| Command Bash Injection (`$ARGUMENTS` 직접 실행) | ~12 | (a) Static OK | R-COMMANDS-001~005 |
| Command Frontmatter Drift (description 누락) | ~6 | (a) Static OK | R-COMMANDS-006~007 |
| Session State Pollution (NOVA-STATE 무한 증가) | ~5 | (c) Identity Conflict | Nova 고유 트림 룰로 별도 처리 |
| Test Coverage Drift (assert 미스매치) | ~6 | (c) Identity Conflict | tests/test-scripts.sh가 별도 검증 |
| Misc (cross-harness, telemetry) | ~4 | (c) Identity Conflict | 채택 제외 |

**요약**: (a) Static OK = ~63 ECC 룰 → Nova 30+ 룰로 압축 흡수. (b) Dynamic Required = ~14 → Known Gap. (c) Identity Conflict = ~25 → 채택 제외 또는 기존 Nova 메커니즘으로 별도 처리.

총 33 Nova 룰 (a) 분류 충족 ≥ 30.

## Known Gap (v5.22.0 범위 외)

다음 영역은 정적 분석 한계 또는 Nova 정체성 충돌로 v5.22.0에서 미커버한다. v5.23.0+ 검토.

- **동적 분석 필요**: 런타임 권한 상승 (sudo/setuid), 세션 오염, MCP 네트워크 호출, 동적 hooks 체인 실패 — e2e CI로 별도 검증
- **공급망 무결성**: 본 룰 파일(`docs/security-rules.md`) 자체가 변조될 경우 검사 결과 조작 가능. 헤더 `last_review_commit` 필드로 마지막 검토 시점은 추적되나, 실시간 tamper detection은 v5.23.0 검토
- **Cross-harness**: cursor/codex/gemini 어댑터 보안은 Nova가 Claude Code 응집형 — Tier 4 deferred
- **--jury Red/Blue/Auditor**: 다관점 적대적 검증은 placeholder만 — v5.23.0 jury 스킬 페르소나 추가 후 활성화

---

## Category: plugin

플러그인 매니페스트(`.claude-plugin/plugin.json`) 자체의 보안 검증.

### Rule R-PLUGIN-001
- **id**: R-PLUGIN-001
- **category**: plugin
- **severity**: Critical
- **condition**: `grep -E '"(api_key|secret|token|password|access_key)"\s*:\s*"[^"]+"' .claude-plugin/plugin.json`
- **normal_example**: `"description": "Nova plugin description"`
- **risk_example**: `"api_key": "sk-abc123..."` (인라인 시크릿)
- **mitigation**: 시크릿은 환경변수 또는 별도 .env 파일로 외부화. plugin.json은 공개 매니페스트.

### Rule R-PLUGIN-002
- **id**: R-PLUGIN-002
- **category**: plugin
- **severity**: Warning
- **condition**: `jq -r '.tool_contract.per_agent[]?.tools[]?' .claude-plugin/plugin.json 2>/dev/null | grep -E '^(Bash|Write|Edit)$' | head -1`
- **normal_example**: 보수적 도구 권한 — `"tools": ["Read", "Glob", "Grep"]`
- **risk_example**: 모든 에이전트가 `["Bash", "Write", "Edit"]` 보유 — 최소 권한 위반
- **mitigation**: 에이전트별 최소 권한만 부여. Edit/Write/Bash는 senior-dev/devops처럼 명시적 필요 에이전트만.

### Rule R-PLUGIN-003
- **id**: R-PLUGIN-003
- **category**: plugin
- **severity**: Critical
- **condition**: `jq -e '.permissions.allow[]? | select(test("^Bash\\(.*\\*\\)$"))' .claude-plugin/plugin.json 2>/dev/null`
- **normal_example**: `"allow": ["Bash(git status:*)", "Bash(npm test:*)"]` (구체 패턴)
- **risk_example**: `"allow": ["Bash(*)"]` (모든 셸 명령 허용)
- **mitigation**: `Bash(*)` 와일드카드 금지. 구체적 명령 패턴만 allow.

### Rule R-PLUGIN-004
- **id**: R-PLUGIN-004
- **category**: plugin
- **severity**: Critical
- **condition**: `grep -E '(AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|xox[bp]-[0-9]+)' .claude-plugin/plugin.json`
- **normal_example**: 시크릿 패턴 부재
- **risk_example**: AWS access key (`AKIA...`), OpenAI key (`sk-...`), GitHub PAT (`ghp_...`), Slack token (`xox...`) 인라인
- **mitigation**: 즉시 키 폐기 + 회전. 코드 히스토리에서 제거 (BFG/git-filter-repo).

### Rule R-PLUGIN-005
- **id**: R-PLUGIN-005
- **category**: plugin
- **severity**: Warning
- **condition**: `jq -e '.version' .claude-plugin/plugin.json 2>/dev/null | grep -vE '^"[0-9]+\.[0-9]+\.[0-9]+"$'`
- **normal_example**: `"version": "5.22.0"` (semver)
- **risk_example**: `"version": "latest"` 또는 `"version": "v5.22"` (불완전)
- **mitigation**: semver `MAJOR.MINOR.PATCH` 엄수. bump-version.sh 사용.

### Rule R-PLUGIN-006
- **id**: R-PLUGIN-006
- **category**: plugin
- **severity**: Info
- **condition**: `jq -e '.author.email // empty' .claude-plugin/plugin.json 2>/dev/null | grep -vE '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'`
- **normal_example**: `"email": "team@spacewalk.tech"`
- **risk_example**: 이메일 누락 또는 비표준 형식
- **mitigation**: author.email 명시. RFC 5321 준수.

---

## Category: hooks

훅 셸 스크립트(`hooks/*.sh`) 의 인젝션·권한 상승·외부 호출 검증.

### Rule R-HOOKS-001
- **id**: R-HOOKS-001
- **category**: hooks
- **severity**: Critical
- **condition**: `grep -nE '\beval\s+["$]' hooks/*.sh`
- **normal_example**: `cmd="grep pattern file"; bash -c "$cmd"` (정적 문자열)
- **risk_example**: `eval "$USER_INPUT"` (사용자 입력 eval 실행)
- **mitigation**: eval 제거. 명시적 명령 분기 또는 case 문 사용.

### Rule R-HOOKS-002
- **id**: R-HOOKS-002
- **category**: hooks
- **severity**: Critical
- **condition**: `grep -nE 'curl\s+[^|]*\|\s*(bash|sh)' hooks/*.sh`
- **normal_example**: `curl -fsSL url -o file && verify_checksum file && bash file`
- **risk_example**: `curl url | bash` (검증 없이 원격 코드 실행)
- **mitigation**: 다운로드 → 체크섬 검증 → 실행 3단계 분리.

### Rule R-HOOKS-003
- **id**: R-HOOKS-003
- **category**: hooks
- **severity**: Critical
- **condition**: `grep -nE 'rm\s+-rf?\s+"?\$\{?[A-Z_]+\}?"?(\s|$)' hooks/*.sh`
- **normal_example**: `rm -rf "${EVENTS_DIR}/${SAFE_FILE}"` (안전 검증 후)
- **risk_example**: `rm -rf $USER_PATH` (변수 인용 없음 + 검증 없음 → empty 시 `rm -rf /`)
- **mitigation**: 변수 항상 큰따옴표. 빈 변수 검증 (`[[ -n "$VAR" ]]`). 절대경로 화이트리스트.

### Rule R-HOOKS-004
- **id**: R-HOOKS-004
- **category**: hooks
- **severity**: Warning
- **condition**: `grep -nE 'sed\s+-i?\s*"[^"]*\$[A-Z_]' hooks/*.sh`
- **normal_example**: `sed "s/PATTERN/literal/" file` (정적 치환)
- **risk_example**: `sed -i "s/.*/$USER_INPUT/" file` (사용자 입력 sed 패턴)
- **mitigation**: 치환 대상이 사용자 입력이면 awk 또는 명시적 escape 필수.

### Rule R-HOOKS-005
- **id**: R-HOOKS-005
- **category**: hooks
- **severity**: Critical
- **condition**: `grep -nE '\bsudo\s|chmod\s+(777|666)\b' hooks/*.sh`
- **normal_example**: `chmod 600 "$EVENTS_FILE"` (소유자만 RW)
- **risk_example**: `sudo chmod 777 /etc/something` (root 권한 + 모든 사용자 RW)
- **mitigation**: sudo 사용 금지. 권한은 0600/0644 까지만.

### Rule R-HOOKS-006
- **id**: R-HOOKS-006
- **category**: hooks
- **severity**: Warning
- **condition**: `grep -nE '^[^#]*\$\{?[A-Z_]+\}?[^"\047]*\$\(' hooks/*.sh | head -5`
- **normal_example**: `result=$(safe_cmd "$VAR")` (인용된 변수 + command substitution)
- **risk_example**: `eval $VAR$(cmd)` (인용 부재 + 중첩 명령)
- **mitigation**: 모든 변수 큰따옴표. command substitution은 별도 라인.

### Rule R-HOOKS-007
- **id**: R-HOOKS-007
- **category**: hooks
- **severity**: Info
- **condition**: `grep -L 'set -[eu]' hooks/*.sh`
- **normal_example**: hooks 시작부에 `set -eu` 또는 `set -u` 명시
- **risk_example**: `set` 옵션 부재 — undefined 변수 silent 통과
- **mitigation**: 모든 hooks에 `set -u` 최소. 가능하면 `set -euo pipefail`.

---

## Category: agents

에이전트 정의(`agents/*.md`) frontmatter 권한·범위 검증.

### Rule R-AGENTS-001
- **id**: R-AGENTS-001
- **category**: agents
- **severity**: Warning
- **condition**: `grep -lE '^tools:.*Bash' agents/*.md | xargs -I {} grep -L '^disallowedTools:' {} 2>/dev/null`
- **normal_example**: `tools: Read, Bash` + `disallowedTools: Edit, Write` (명시 제한)
- **risk_example**: `tools: Bash` 만 — 셸 권한이 있는데 disallowedTools 미명시
- **mitigation**: Bash 권한 가진 에이전트는 disallowedTools 명시 필수 (Edit/Write 차단 등).

### Rule R-AGENTS-002
- **id**: R-AGENTS-002
- **category**: agents
- **severity**: Critical
- **condition**: `grep -E '^tools:.*\*' agents/*.md`
- **normal_example**: `tools: Read, Glob, Grep` (명시 목록)
- **risk_example**: `tools: *` (모든 도구 허용 와일드카드)
- **mitigation**: tools 와일드카드 금지. 명시적 도구 목록만.

### Rule R-AGENTS-003
- **id**: R-AGENTS-003
- **category**: agents
- **severity**: Warning
- **condition**: `grep -L '^description:' agents/*.md 2>/dev/null`
- **normal_example**: frontmatter `description:` 1줄 명시
- **risk_example**: description 누락 — Claude Code agent picker 동작 불능
- **mitigation**: 모든 에이전트에 description 필수. 한 문장 명시.

### Rule R-AGENTS-004
- **id**: R-AGENTS-004
- **category**: agents
- **severity**: Info
- **condition**: `grep -L '^model:' agents/*.md 2>/dev/null`
- **normal_example**: `model: sonnet` (또는 opus/haiku)
- **risk_example**: model 미지정 — 부모 컨텍스트 모델 상속 (비용 예측 불가)
- **mitigation**: 비용 최적화 위해 명시적 model 지정 권장. evaluator는 sonnet, security는 sonnet, refiner는 haiku 등.

### Rule R-AGENTS-005
- **id**: R-AGENTS-005
- **category**: agents
- **severity**: Warning
- **condition**: `grep -LE '^# (Role|역할)' agents/*.md`
- **normal_example**: 에이전트 본문에 `# Role` 또는 `# 역할` 헤더 + 명확한 책임 정의
- **risk_example**: frontmatter만 있고 `# Role` 헤더 없음 — 에이전트 책임이 모호
- **mitigation**: 모든 에이전트에 `# Role` (또는 `# 역할`) 섹션 필수. Behavior, Decision Criteria, Output Format 섹션 권장.

---

## Category: skills

스킬 정의(`skills/*/SKILL.md`) 트리거·외부 호출 검증.

### Rule R-SKILLS-001
- **id**: R-SKILLS-001
- **category**: skills
- **severity**: Critical
- **condition**: `grep -lE '^[^#]*sk-[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}' skills/*/SKILL.md`
- **normal_example**: 시크릿 부재
- **risk_example**: 스킬 본문에 API 키 인라인
- **mitigation**: 즉시 키 폐기 + 회전. 스킬은 환경변수 안내만 작성.

### Rule R-SKILLS-002
- **id**: R-SKILLS-002
- **category**: skills
- **severity**: Warning
- **condition**: `grep -nE 'WebFetch|curl\s+http|wget\s+http' skills/*/SKILL.md`
- **normal_example**: 외부 네트워크 호출 없음 또는 명시적 사용자 동의 후
- **risk_example**: 스킬이 자동 외부 fetch — 사용자 인지 없이 데이터 유출 가능
- **mitigation**: 외부 호출은 의도적·명시적이어야. 스킬 본문에 "외부 호출 사유" 명시.

### Rule R-SKILLS-003
- **id**: R-SKILLS-003
- **category**: skills
- **severity**: Warning
- **condition**: `grep -L '^description:' skills/*/SKILL.md 2>/dev/null`
- **normal_example**: frontmatter description 명시
- **risk_example**: description 누락 — Claude가 스킬 트리거 판단 불능
- **mitigation**: description 1줄 + MUST TRIGGER 조건 명시.

### Rule R-SKILLS-004
- **id**: R-SKILLS-004
- **category**: skills
- **severity**: Info
- **condition**: `grep -lE 'user-invocable:\s*true' skills/*/SKILL.md | xargs -I {} grep -L 'MUST TRIGGER' {} 2>/dev/null`
- **normal_example**: user-invocable 스킬은 본문에 MUST TRIGGER 조건 명시
- **risk_example**: user-invocable이지만 트리거 조건 모호 — 사용자 혼란
- **mitigation**: user-invocable: true 시 MUST TRIGGER + MUST NOT TRIGGER 양쪽 명시.

### Rule R-SKILLS-005
- **id**: R-SKILLS-005
- **category**: skills
- **severity**: Warning
- **condition**: `grep -nE 'bash\s+-c\s+"[^"]*\$\{?(USER_INPUT|ARGUMENTS|input)' skills/*/SKILL.md`
- **normal_example**: 사용자 입력 변수를 case/if로 분기 후 정적 명령 실행
- **risk_example**: 스킬 본문이 `bash -c "process $USER_INPUT"` 패턴을 권장 — 명령 인젝션 가능성
- **mitigation**: 스킬은 변수 직접 셸 인터폴레이션을 권장하지 않는다. 검증 → 화이트리스트 분기 패턴만 권장.

---

## Category: commands

커맨드 정의(`commands/*.md`) frontmatter·인수 처리·외부 호출 검증.

### Rule R-COMMANDS-001
- **id**: R-COMMANDS-001
- **category**: commands
- **severity**: Critical
- **condition**: `grep -nE 'bash\s+-c\s+"[^"]*\$ARGUMENTS' commands/*.md`
- **normal_example**: `$ARGUMENTS` 를 변수에 저장 후 검증 — `slug=$(echo "$ARGUMENTS" | sanitize)`
- **risk_example**: `bash -c "process $ARGUMENTS"` (사용자 입력 직접 셸 실행)
- **mitigation**: $ARGUMENTS는 인수 파싱 → 검증 → 인용된 변수로만 사용.

### Rule R-COMMANDS-002
- **id**: R-COMMANDS-002
- **category**: commands
- **severity**: Warning
- **condition**: `grep -nE 'rm\s+-rf?\s+\$\{?ARGUMENTS' commands/*.md`
- **normal_example**: 사용자 입력으로 파일 삭제 안 함
- **risk_example**: `rm -rf $ARGUMENTS` (사용자 임의 경로 삭제 가능)
- **mitigation**: 파일 삭제 명령은 화이트리스트 경로만.

### Rule R-COMMANDS-003
- **id**: R-COMMANDS-003
- **category**: commands
- **severity**: Warning
- **condition**: `grep -nE 'curl|wget' commands/*.md | grep -v 'http(s)\?://github\.com\|http(s)\?://raw\.githubusercontent'`
- **normal_example**: 외부 호출 없음 또는 GitHub 공식 URL 한정
- **risk_example**: 임의 외부 URL fetch — 공급망 공격 표면
- **mitigation**: 외부 호출은 화이트리스트 도메인만. 또는 사용자 명시 입력.

### Rule R-COMMANDS-004
- **id**: R-COMMANDS-004
- **category**: commands
- **severity**: Info
- **condition**: `grep -nE 'git\s+(push|reset\s+--hard|checkout\s+\.)' commands/*.md | grep -v '#\|예시\|example'`
- **normal_example**: 파괴적 git 명령은 사용자 확인 후
- **risk_example**: 커맨드가 자동 `git push --force` 또는 `git reset --hard`
- **mitigation**: 파괴적 git은 사용자 confirm 단계 필수. 자동 실행 금지.

### Rule R-COMMANDS-005
- **id**: R-COMMANDS-005
- **category**: commands
- **severity**: Critical
- **condition**: `grep -nE '\$\{?[A-Z_]+\}?\s*\|\s*(bash|sh|eval)' commands/*.md`
- **normal_example**: 변수 검증 후 명시적 명령 실행
- **risk_example**: `$USER_INPUT | bash` (변수를 셸로 파이핑)
- **mitigation**: 변수 → 셸 파이프 금지. case/if 분기로 명시적 실행.

### Rule R-COMMANDS-006
- **id**: R-COMMANDS-006
- **category**: commands
- **severity**: Warning
- **condition**: `grep -L '^description:' commands/*.md 2>/dev/null`
- **normal_example**: frontmatter description 명시
- **risk_example**: description 누락 — Claude Code 슬래시커맨드 picker 동작 불능
- **mitigation**: 모든 커맨드에 description 1줄 필수.

### Rule R-COMMANDS-007
- **id**: R-COMMANDS-007
- **category**: commands
- **severity**: Info
- **condition**: `grep -L '^# Input' commands/*.md`
- **normal_example**: 본문 끝에 `# Input` 헤더 + `$ARGUMENTS` 처리 명시
- **risk_example**: `# Input` 섹션 헤더 누락 — 인수 처리 의도 불명확
- **mitigation**: 모든 커맨드에 `# Input` 섹션 명시. 인수 처리(`$ARGUMENTS`) 명확화.
