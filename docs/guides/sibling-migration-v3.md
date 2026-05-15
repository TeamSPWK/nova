# 형제 프로젝트 v3 work-item registry 마이그레이션 가이드

> v5.42.0+ — Sprint 6 산출물.
> 대상: Nova 플러그인을 사용하는 ~/develop/* 사용자 프로젝트
> 본 가이드는 **사용자가 직접 실행**한다. Nova 자동화 없음 (외부 레포라 PR 분리).

## TL;DR

각 프로젝트에서 순차 실행 (병렬 X — Architect #11 worktree race 회피):

```bash
cd ~/develop/<project>
# 1. dry-run으로 변환 결과 미리보기
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/migrate-state-v3.sh --dry-run

# 2. 보존율 + 변환 미리보기 확인 후 실제 적용
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/migrate-state-v3.sh --apply

# 3. drift-check로 변환 결과 검증
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/registry-drift-check.sh

# 4. git status / diff 확인 후 commit + PR
git status
git diff NOVA-STATE.md
git add .nova/ NOVA-STATE.md
git commit -m "feat: Nova v3 work-item registry 도입 (v2→v3 자동 마이그레이션)"
```

## 마이그레이션 절차 (전체)

### 단계 1: 환경 확인

```bash
cd ~/develop/<project>

# Nova plugin path 확인
ls -d ~/develop/nova/scripts/migrate-state-v3.sh  # 존재해야

# 현재 STATE 확인
head -10 NOVA-STATE.md  # v2 frontmatter 또는 v1

# 의존성
jq --version       # 1.6+
python3 --version  # 3.8+
git --version
```

### 단계 2: 사전 백업 (선택, migrate-v3가 자동 백업하지만 안전망)

```bash
git stash push -u -m "before-nova-v3-migration"  # 또는
cp NOVA-STATE.md NOVA-STATE.md.manual-bak
```

### 단계 3: dry-run으로 변환 미리보기

```bash
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/migrate-state-v3.sh --dry-run
```

**확인 사항**:
- v2 STATE 파싱 항목 수 (Tasks/Recently Done/Known Gaps/Active Tree)
- 변환 대상 work-item 총 개수 = **항목 수 보존율 (a)**
- `done w/ sha` vs `proposed 강등`: commit_sha 추출 가능했던 건수 = **상태 보존율 (b)**

> **두 보존율의 의미**:
> - (a) **항목 수 보존율 ≥ 0.8 필수**: 어떤 v2 항목이 work-item으로 변환됐는가
> - (b) **상태 보존율은 참고지표**: DORA 표준(commit_sha) 부재 프로젝트는 (b) 낮음 → 정상. 후속 evidence 채우면 됨.

### 단계 4: 실제 적용

```bash
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/migrate-state-v3.sh --apply
```

**자동 수행**:
1. `NOVA-STATE.md.v2.bak` 백업 생성
2. `.nova/{schema,work-items,README.md}` 부트스트랩
3. 각 항목 → `.nova/work-items/WI-NNNN-slug.json` 생성
4. `index.json` 갱신
5. `NOVA-STATE.md`에 `<!-- nova:registry-rendered:start/end -->` marker 추가
6. `registry-render-state.sh` 자동 호출 → marker 영역 자동 렌더

### 단계 5: 검증

```bash
# drift-check로 H1~H9 + W1~W9 룰 통과 확인
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/registry-drift-check.sh

# exit code:
#   0 = PASS
#   1 = Warn only (수용 가능, post-migration 후속 작업)
#   2 = Hard error → 수동 수정 필수
```

**예상 Warn (정상)**:
- W5: `index.json` git 커밋 이력 부재 → 다음 git add로 해소
- W7: `source_docs` 비어있음 → 사용자가 plan 경로 수동 입력 (post-migration)

**예상 Hard 0건**: 마이그레이션 자체는 invariant 보호하므로 0이어야 정상.

### 단계 6: 사용자 검수

```bash
# 변환된 work-item 확인
ls .nova/work-items/WI-*.json

# 특정 항목 상세 보기
cat .nova/work-items/WI-0001-*.json | jq

# status 분포
jq -r '.work_items[] | .status' .nova/work-items/index.json | sort | uniq -c

# NOVA-STATE.md marker 영역 확인
awk '/nova:registry-rendered:start/,/nova:registry-rendered:end/' NOVA-STATE.md
```

**점검 포인트**:
- [ ] Tasks 표 항목이 모두 work-item으로 변환됐는가?
- [ ] Recently Done의 commit_sha 추출 정확한가?
- [ ] Active Tree의 🚫 항목이 `blocked` + `blocked_reason`으로 변환됐는가?
- [ ] marker 외 영역(사람 손편집) 보존됐는가?
- [ ] 백업 파일(`NOVA-STATE.md.v2.bak`) 존재?

### 단계 7: post-migration 후속 입력 (선택)

migrate-v3는 다음을 **자동 추가하지 않는다** (PoC 5 규칙 #3·#4):
- `source_docs`: plan/design 경로
- `depends_on`: WI 간 의존성

```bash
# 예: WI-0001에 source_docs 추가
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/registry-write.sh update WI-0001-... \
  source_docs="docs/plans/feature.md,docs/designs/feature.md"

# WI-0001이 WI-0003에 의존 (post-migration)
NOVA_PLUGIN_PATH=~/develop/nova bash ~/develop/nova/scripts/registry-write.sh update WI-0001-... \
  depends_on="WI-0003-prereq"
```

### 단계 8: commit + push

```bash
git status

# 예상 변경:
#  new file:   .nova/README.md
#  new file:   .nova/schema/index.schema.json
#  new file:   .nova/schema/work-item.schema.json
#  new file:   .nova/work-items/WI-0001-*.json
#  ...
#  new file:   .nova/work-items/index.json
#  new file:   NOVA-STATE.md.v2.bak
#  modified:   .gitignore (Nova marker 블록 추가)
#  modified:   NOVA-STATE.md (marker 영역 추가)

git add .nova/ NOVA-STATE.md .gitignore NOVA-STATE.md.v2.bak
git commit -m "feat: Nova v3 work-item registry 도입 (v2→v3 자동 마이그레이션)

- N개 work-item으로 변환 (보존율 100%)
- .nova/{schema,work-items}/ git-tracked
- NOVA-STATE.md marker 영역 자동 렌더 (registry-render-state.sh)
"

# 형제 프로젝트 PR (해당 시)
git push -u origin feature/nova-v3-migration
gh pr create --title "Nova v3 work-item registry 도입" \
  --body "v2 STATE → v3 work-item registry 자동 마이그레이션. 보존율 100%. drift-check 통과."
```

## FAIL 시나리오

### Hard error (H1~H9) 발화

| 룰 | 의미 | 해소 |
|----|------|------|
| H1 | schema 위반 | `.nova/work-items/<id>.json` 직접 편집 — invariant 충족하도록 수정. JSON Schema: `docs/templates/schema/work-item.schema.json` 참조 |
| H6 | status=done인데 commit_sha 비어있음 | `registry-write.sh evaluator-pass <wi> --commit-sha=...` 또는 `update` |
| H8 | `.pending-transition-*` 마커 잔류 | 1) WI 파일 + index.json 동기화 후 마커 삭제, 또는 2) `transition` 재실행 |
| H9 | blocked인데 reason 빈 | `registry-write.sh update <wi> blocked_reason="..."` |

### 보존율 (a) < 0.8

원인:
- v2 STATE 형식 비표준 (표 헤더 다름, 들여쓰기 다름)
- Active Tree 형식이 `- ✅` 외 다른 emoji 사용

해소: Nova 본 레포에 issue 등록 (`v2 STATE format mismatch — <project>`) + 수동 변환 보조.

### 백업 복구

마이그레이션 결과가 만족스럽지 않으면:

```bash
mv NOVA-STATE.md NOVA-STATE.md.v3.failed
mv NOVA-STATE.md.v2.bak NOVA-STATE.md
rm -rf .nova/work-items .nova/schema .nova/README.md
# .gitignore의 Nova marker 블록도 제거
```

## Cheatsheet

| 작업 | 명령 |
|------|------|
| dry-run | `bash ~/develop/nova/scripts/migrate-state-v3.sh --dry-run` |
| 실제 적용 | `bash ~/develop/nova/scripts/migrate-state-v3.sh --apply` |
| 검증 | `bash ~/develop/nova/scripts/registry-drift-check.sh` |
| Hard 룰만 | `bash ~/develop/nova/scripts/registry-drift-check.sh --severity=critical` |
| JSONL 진단 | `bash ~/develop/nova/scripts/registry-drift-check.sh --jsonl` |
| WI 1건 생성 | `bash ~/develop/nova/scripts/registry-write.sh create "title" --priority=high` |
| status 분포 | `jq -r '.work_items[].status' .nova/work-items/index.json \| sort \| uniq -c` |
| STATE 재렌더 | `bash ~/develop/nova/scripts/registry-render-state.sh` |

## 7 형제 프로젝트 권장 순서 (Architect #11 순차 확정)

1. **nova-landing** (가장 단순, plan 0개, v1 STATE — PoC 검증됨)
2. **markbrief**
3. **md-template-compiler**
4. **agent-work-memory**
5. **swk-cloud-manage**
6. **swk-data-pipeline**
7. **spwk-product** (가장 복잡 — planreview는 별도 대형 마이그레이션)

각 0.5~1일 = 총 3.5~7일.

## 참고

- 설계: <https://github.com/jay-swk/nova/blob/main/docs/designs/work-item-registry-v3.md>
- Plan: <https://github.com/jay-swk/nova/blob/main/docs/plans/work-item-registry-v3.md>
- Sprint 0 specs: `docs/specs/{work-item-scope,state-call-graph,registry-write-authority}-v3.md`
- 본 가이드: `docs/guides/sibling-migration-v3.md`
