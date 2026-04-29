# Fixture: visual-intent-side-case

Reproduces the user's actual side-project incident — the trigger that motivated this gate.

## User prompt

```
[Image attached] x 버튼 포함해서 전체적으로 디자인 구림. UI/UX도 최신 트렌드로 적용 부탁할게!
```

## Agent (without G1 gate) misbehavior

```
Sprint 7-2 잠시 중단. UI/UX 개선 우선 진행합니다. 스크린샷 보고 핵심 문제 파악:
  - × 제거 버튼이 빨간 사각형 — 거칠고 위협적
  - 카드 간격 좁음, 음영 평면적
  ...
  기존 CSS 토큰부터 확인하고 광범위 리뉴얼.
```

→ 4 gaps exposed:
1. 모호한 "최신 트렌드" → 에이전트가 자기 해석
2. "x 버튼" → "광범위 리뉴얼" 스코프 확장
3. "기존 CSS 토큰부터" 자체 판단 (사용자 미확인)
4. 검증 기준 부재

## Expected G1 capture (--from-prompt + interactive)

`prompt.txt` 내용을 `--from-prompt`로 전달 시:
- vocabulary auto-extraction → catalog has no exact "최신 트렌드" match → falls back to default `shadcn` (or Tailwind detection)
- scope auto-detection → detect-ui-change.sh 결과로 파일 후보 노출
- design_system → detect-design-system.sh 결과 노출 후 사용자 의사 확인
- reference → 사용자 첨부 스크린샷 경로 (있으면)

`expected-intent.json` shows the post-capture frozen state.
