# drift-cases — Sprint 4 인위적 위반 fixture

각 sub-fixture는 `bash scripts/registry-drift-check.sh`가 명시 룰을 정확히 검출하는지 검증용.

## 디렉토리 구조

각 fixture는 `.nova/work-items/`와 (필요 시) `.nova/events.jsonl`을 포함한 *완성된* registry 스냅샷이다. 테스트가 이를 임시 디렉토리로 복사 후 drift-check 실행, 예상 룰만 발화하는지 확인.

| fixture | 발화 예상 |
|---------|----------|
| `h1-schema-invalid/` | H1 (status enum / review_required bool 위반) |
| `h6-done-no-evidence/` | H6 (status=done인데 commit_sha 비어있음) |
| `h8-pending-marker/` | H8 (`.pending-transition-*` 마커 잔류) |
| `h9-blocked-no-reason/` | H9 (status=blocked인데 blocked_reason null) |
| `w6-uuid-fallback/` | W6 (UUID fallback id 잔존) |

## 사용

```bash
# 단일 fixture 검증
cp -r tests/fixtures/drift-cases/h6-done-no-evidence/. /tmp/test/
cd /tmp/test
bash scripts/registry-drift-check.sh
# 예상: exit 2, H6 발화
```
