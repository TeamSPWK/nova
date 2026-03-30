# Design: User Authentication

## Context
사용자 인증 기능이 필요하다. 이메일/비밀번호로 회원가입 및 로그인을 지원한다.

## Data Contract

### API Endpoints
- `POST /api/auth/register` — 회원가입 (email, password, name)
- `POST /api/auth/login` — 로그인 (email, password) → JWT 토큰 반환
- `GET /api/auth/me` — 현재 사용자 정보 조회 (Authorization 헤더 필수)

### Data Model
```
User {
  id: UUID
  email: string (unique, indexed)
  password: string (bcrypt hashed)
  name: string
  createdAt: timestamp
}
```

### Verification Contract
1. 회원가입 시 이메일 중복 체크 → 중복이면 409 에러
2. 비밀번호는 bcrypt로 해싱 후 저장 → 평문 저장 금지
3. 로그인 성공 시 JWT 토큰 반환 → 토큰에 userId 포함
4. /api/auth/me는 유효한 토큰 없이 접근 시 401 반환
5. 비밀번호는 최소 8자 이상 → 미만이면 400 에러
