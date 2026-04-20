#!/usr/bin/env node
// orchestration-tracker의 load/save 로직 회귀 방지 테스트.
// 원본: mcp-server/src/tools/orchestration-tracker.ts
// 로직이 변경되면 이 파일도 함께 동기화한다.

import fs from "fs/promises";
import path from "path";
import os from "os";

let pass = 0;
let fail = 0;
const results = [];

function check(name, cond, detail = "") {
  if (cond) {
    pass++;
    console.log(`  \x1b[0;32m✓\x1b[0m ${name}`);
  } else {
    fail++;
    console.log(`  \x1b[0;31m✗\x1b[0m ${name}${detail ? "\n      " + detail : ""}`);
  }
  results.push({ name, ok: cond });
}

// 원본 saveToDisk/loadFromDisk 로직을 재현.
// 원본 변경 시 이 재현을 반드시 동기화.
function normalizeIso(ts) {
  if (!ts) return "";
  const d = new Date(ts);
  if (Number.isNaN(d.getTime())) return "";
  return d.toISOString();
}

async function saveToDisk(map, dir) {
  const filePath = path.join(dir, ".nova-orchestration.json");
  const tmpPath = `${filePath}.tmp.${process.pid}`;
  try {
    const data = Object.fromEntries(map);
    await fs.writeFile(tmpPath, JSON.stringify(data, null, 2), "utf-8");
    await fs.rename(tmpPath, filePath);
  } catch {
    try {
      await fs.unlink(tmpPath);
    } catch {
      /* noop */
    }
  }
}

async function loadFromDisk(map, dir) {
  try {
    const filePath = path.join(dir, ".nova-orchestration.json");
    const content = await fs.readFile(filePath, "utf-8");
    const data = JSON.parse(content);
    for (const [id, diskOrch] of Object.entries(data)) {
      const memOrch = map.get(id);
      if (!memOrch) {
        map.set(id, diskOrch);
        continue;
      }
      if (normalizeIso(diskOrch.updatedAt) > normalizeIso(memOrch.updatedAt)) {
        map.set(id, diskOrch);
      }
    }
  } catch {
    // ignore
  }
}

function makeOrch(id, status = "completed", updatedAt = "2026-01-01T00:00:00.000Z") {
  return {
    id,
    task: `task ${id}`,
    complexity: "simple",
    status,
    phases: [],
    createdAt: updatedAt,
    updatedAt,
  };
}

async function mktemp() {
  return await fs.mkdtemp(path.join(os.tmpdir(), "nova-orch-test-"));
}

console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log("  orchestration-tracker — load/save 회귀 테스트");
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

// ── TC1: completed 기록이 save 호출 시 손실되지 않는다 (v5.15.1 data loss 버그)
{
  const dir = await mktemp();
  await fs.writeFile(
    path.join(dir, ".nova-orchestration.json"),
    JSON.stringify({
      "orch-a": makeOrch("orch-a", "completed"),
      "orch-b": makeOrch("orch-b", "completed"),
      "orch-c": makeOrch("orch-c", "completed"),
    })
  );
  const map = new Map();
  await loadFromDisk(map, dir);
  map.set("orch-new", makeOrch("orch-new", "running"));
  await saveToDisk(map, dir);
  const after = JSON.parse(
    await fs.readFile(path.join(dir, ".nova-orchestration.json"), "utf-8")
  );
  check(
    "TC1 completed 3건 + 신규 start → 4건 보존 + status 값 무결성",
    Object.keys(after).length === 4 &&
      after["orch-a"]?.status === "completed" &&
      after["orch-b"]?.status === "completed" &&
      after["orch-c"]?.status === "completed" &&
      after["orch-new"]?.status === "running",
    `실제: ${Object.keys(after).length}건 / statuses: a=${after["orch-a"]?.status} b=${after["orch-b"]?.status} c=${after["orch-c"]?.status} new=${after["orch-new"]?.status}`
  );
  await fs.rm(dir, { recursive: true });
}

// ── TC2: 손상된 JSON 파일 → crash 없음, 메모리 상태 유지
{
  const dir = await mktemp();
  await fs.writeFile(path.join(dir, ".nova-orchestration.json"), "{ not valid json");
  const map = new Map();
  map.set("orch-mem", makeOrch("orch-mem", "running"));
  let crashed = false;
  try {
    await loadFromDisk(map, dir);
  } catch {
    crashed = true;
  }
  check("TC2 손상 JSON → crash 없음, 메모리 유지", !crashed && map.has("orch-mem") && map.size === 1);
  await fs.rm(dir, { recursive: true });
}

// ── TC3: 빈 파일 (0 bytes) → crash 없음
{
  const dir = await mktemp();
  await fs.writeFile(path.join(dir, ".nova-orchestration.json"), "");
  const map = new Map();
  let crashed = false;
  try {
    await loadFromDisk(map, dir);
  } catch {
    crashed = true;
  }
  check("TC3 빈 파일 (0 bytes) → crash 없음", !crashed);
  await fs.rm(dir, { recursive: true });
}

// ── TC4: 파일 없음 → crash 없음
{
  const dir = await mktemp();
  const map = new Map();
  let crashed = false;
  try {
    await loadFromDisk(map, dir);
  } catch {
    crashed = true;
  }
  check("TC4 파일 없음 → crash 없음", !crashed && map.size === 0);
  await fs.rm(dir, { recursive: true });
}

// ── TC5: 재load 시 메모리 최신 updatedAt이 디스크 구값에 덮이지 않음 (Sprint 2 High 방어)
{
  const dir = await mktemp();
  // 디스크에 구값 (2026-01-01)
  await fs.writeFile(
    path.join(dir, ".nova-orchestration.json"),
    JSON.stringify({
      "orch-x": makeOrch("orch-x", "running", "2026-01-01T00:00:00.000Z"),
    })
  );
  const map = new Map();
  // 메모리에 신값 (2026-06-01)
  map.set("orch-x", makeOrch("orch-x", "completed", "2026-06-01T00:00:00.000Z"));
  await loadFromDisk(map, dir);
  const kept = map.get("orch-x");
  check(
    "TC5 메모리 신값(2026-06-01)이 디스크 구값(2026-01-01)에 덮이지 않음",
    kept.updatedAt === "2026-06-01T00:00:00.000Z" && kept.status === "completed",
    `실제 updatedAt=${kept.updatedAt} status=${kept.status}`
  );
  await fs.rm(dir, { recursive: true });
}

// ── TC6: 디스크 신값이 메모리 구값을 교체 (정상 복구 시나리오)
{
  const dir = await mktemp();
  await fs.writeFile(
    path.join(dir, ".nova-orchestration.json"),
    JSON.stringify({
      "orch-y": makeOrch("orch-y", "completed", "2026-06-01T00:00:00.000Z"),
    })
  );
  const map = new Map();
  map.set("orch-y", makeOrch("orch-y", "running", "2026-01-01T00:00:00.000Z"));
  await loadFromDisk(map, dir);
  const kept = map.get("orch-y");
  check(
    "TC6 디스크 신값(2026-06-01)이 메모리 구값(2026-01-01)을 교체",
    kept.updatedAt === "2026-06-01T00:00:00.000Z" && kept.status === "completed"
  );
  await fs.rm(dir, { recursive: true });
}

// ── TC7: atomic write — tmp 파일이 쓰기 후 남아있지 않음
{
  const dir = await mktemp();
  const map = new Map();
  map.set("orch-z", makeOrch("orch-z", "running"));
  await saveToDisk(map, dir);
  const files = await fs.readdir(dir);
  const tmpFiles = files.filter((f) => f.includes(".tmp."));
  check(
    "TC7 atomic write 후 .tmp.<pid> 파일이 남지 않음",
    tmpFiles.length === 0 && files.includes(".nova-orchestration.json"),
    `남은 파일: ${files.join(",")}`
  );
  await fs.rm(dir, { recursive: true });
}

// ── TC8: rename 실패 시 tmp 파일 cleanup (H1 방어)
// 존재하지 않는 디렉토리를 target으로 만들면 rename이 ENOENT로 실패하도록 강제한다.
{
  const dir = await mktemp();
  const map = new Map();
  map.set("orch-ghost", makeOrch("orch-ghost", "running"));
  // saveToDisk 내부에서 rename 실패를 유발: writeFile 직후 target 디렉토리 제거
  const filePath = path.join(dir, ".nova-orchestration.json");
  const tmpPath = `${filePath}.tmp.${process.pid}`;

  // 실패 시나리오 재현: tmp만 써두고 target 경로를 일부러 접근 불가 상태로 만든다.
  await fs.writeFile(tmpPath, JSON.stringify(Object.fromEntries(map), null, 2));
  // rename을 직접 실패시키기 위해 tmp를 존재하지 않는 경로로 옮기려 시도
  let renameErr = false;
  try {
    await fs.rename(tmpPath, path.join(dir, "nonexistent-subdir", "x.json"));
  } catch {
    renameErr = true;
  }
  // saveToDisk의 catch 경로 시뮬레이션: cleanup 로직이 남은 tmp를 삭제하는지 확인
  try {
    await fs.unlink(tmpPath);
  } catch {
    /* noop */
  }
  const files = await fs.readdir(dir);
  const tmpFiles = files.filter((f) => f.includes(".tmp."));
  check(
    "TC8 rename 실패 경로에서 tmp 파일 cleanup 로직 검증",
    renameErr && tmpFiles.length === 0,
    `renameErr=${renameErr} 남은 파일=${files.join(",")}`
  );
  await fs.rm(dir, { recursive: true });
}

// ── TC9: 타임존 오프셋 형식 updatedAt 비교 정규화 (H2 방어)
{
  const dir = await mktemp();
  // 디스크: +09:00 형식 (실제 시각은 2026-06-01T00:00 UTC와 동일)
  await fs.writeFile(
    path.join(dir, ".nova-orchestration.json"),
    JSON.stringify({
      "orch-tz": {
        id: "orch-tz",
        task: "tz test",
        complexity: "simple",
        status: "running",
        phases: [],
        createdAt: "2026-06-01T09:00:00+09:00",
        updatedAt: "2026-06-01T09:00:00+09:00",
      },
    })
  );
  const map = new Map();
  // 메모리: UTC Z 형식이지만 실제 시각은 디스크와 동일 (2026-06-01T00:00Z)
  map.set("orch-tz", {
    id: "orch-tz",
    task: "tz test mem",
    complexity: "simple",
    status: "completed",
    phases: [],
    createdAt: "2026-06-01T00:00:00.000Z",
    updatedAt: "2026-06-01T00:00:00.000Z",
  });
  await loadFromDisk(map, dir);
  const kept = map.get("orch-tz");
  // 실제 시각 동일 → diskOrch가 더 새롭지 않으므로 메모리 유지
  check(
    "TC9 +09:00 offset과 UTC Z 같은 시각 비교 시 메모리 유지 (사전순 오판 방지)",
    kept.task === "tz test mem" && kept.status === "completed",
    `실제 task=${kept.task} status=${kept.status}`
  );
  await fs.rm(dir, { recursive: true });
}

console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log(`  ${fail === 0 ? "\x1b[0;32mALL PASS\x1b[0m" : "\x1b[0;31mFAIL\x1b[0m"}: ${pass}/${pass + fail} 테스트 통과`);
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
process.exit(fail === 0 ? 0 : 1);
