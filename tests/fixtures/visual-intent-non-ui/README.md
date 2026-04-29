# Fixture: visual-intent-non-ui

Non-UI work (backend only). Verifies G1 gate does NOT fire on non-UI tasks.

## User prompt

```
GET /api/users 엔드포인트에 페이지네이션 추가해줘.
```

## Expected behavior

- detect-ui-change.sh --planning → likely_ui:false
- capture-visual-intent.sh should NOT fire automatically (gated by likely_ui)
- If forced (manual call): writes intent.json with empty scope/none DS — but commands should NOT auto-call

This fixture verifies the **negative case** — false positive prevention.
