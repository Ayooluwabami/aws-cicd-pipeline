import { test } from 'node:test';
import assert from 'node:assert';
import type { AddressInfo } from 'node:net';
import { createApp, healthPayload, telemetryPayload, readBuildInfo } from './app';

function listen(app: ReturnType<typeof createApp>) {
  const server = app.listen(0);
  const { port } = server.address() as AddressInfo;
  return { server, base: `http://127.0.0.1:${port}` };
}

test('healthPayload reports ok status', () => {
  const payload = healthPayload();
  assert.strictEqual(payload.status, 'ok');
  assert.ok(payload.uptime >= 0);
  assert.ok(!Number.isNaN(Date.parse(payload.timestamp)));
});

test('telemetryPayload exposes runtime metrics', () => {
  const t = telemetryPayload();
  assert.ok(t.uptimeSeconds >= 0);
  assert.ok(t.rssBytes > 0);
  assert.ok(t.heapUsedBytes > 0);
  assert.strictEqual(t.loadAverage.length, 3);
  assert.ok(t.cpuCount >= 1);
  assert.ok(typeof t.hostname === 'string' && t.hostname.length > 0);
});

test('readBuildInfo always returns commit and buildId', () => {
  const info = readBuildInfo();
  assert.ok(typeof info.commit === 'string' && info.commit.length > 0);
  assert.ok(typeof info.buildId === 'string' && info.buildId.length > 0);
});

test('GET /api/health returns 200 with ok status', async () => {
  const { server, base } = listen(createApp());
  try {
    const res = await fetch(`${base}/api/health`);
    assert.strictEqual(res.status, 200);
    const body = (await res.json()) as { status: string };
    assert.strictEqual(body.status, 'ok');
  } finally {
    server.close();
  }
});

test('GET /api/telemetry returns runtime metrics', async () => {
  const { server, base } = listen(createApp());
  try {
    const res = await fetch(`${base}/api/telemetry`);
    assert.strictEqual(res.status, 200);
    const body = (await res.json()) as { requestsServed: number; nodeVersion: string };
    assert.ok(body.requestsServed >= 1);
    assert.ok(body.nodeVersion.startsWith('v'));
  } finally {
    server.close();
  }
});

test('GET /metrics exposes Prometheus metrics with request histogram', async () => {
  const { server, base } = listen(createApp());
  try {
    await fetch(`${base}/api/health`);
    const res = await fetch(`${base}/metrics`);
    assert.strictEqual(res.status, 200);
    const body = await res.text();
    assert.ok(body.includes('process_cpu_user_seconds_total'));
    assert.ok(body.includes('http_request_duration_seconds_bucket'));
  } finally {
    server.close();
  }
});

test('GET /api/sli scores live SLIs against SLO targets', async () => {
  const { server, base } = listen(createApp());
  try {
    await fetch(`${base}/api/health`);
    await fetch(`${base}/api/health`);
    const res = await fetch(`${base}/api/sli`);
    assert.strictEqual(res.status, 200);
    const body = (await res.json()) as {
      window: { requests: number };
      slo: {
        availability: { currentPct: number; targetPct: number; met: boolean };
        latencyP99: { currentMs: number; targetMs: number };
        errorRate: { currentPct: number };
        budgetUsedPct: number;
      };
      golden: { trafficRpm: number; saturation: { loopLagP99Ms: number; heapUsedPct: number } };
      telemetry: { traces: { enabled: boolean } };
      recent: unknown[];
    };
    assert.ok(body.window.requests >= 2);
    assert.strictEqual(body.slo.availability.targetPct, 99.5);
    assert.strictEqual(body.slo.availability.currentPct, 100);
    assert.strictEqual(body.slo.availability.met, true);
    assert.ok(body.slo.latencyP99.currentMs >= 0);
    assert.strictEqual(body.slo.errorRate.currentPct, 0);
    assert.strictEqual(body.slo.budgetUsedPct, 0);
    assert.ok(body.golden.trafficRpm >= 2);
    assert.ok(body.golden.saturation.heapUsedPct > 0);
    assert.strictEqual(typeof body.telemetry.traces.enabled, 'boolean');
    assert.ok(body.recent.length >= 2);
  } finally {
    server.close();
  }
});

test('GET /api/info returns app metadata', async () => {
  const { server, base } = listen(createApp());
  try {
    const res = await fetch(`${base}/api/info`);
    assert.strictEqual(res.status, 200);
    const body = (await res.json()) as { app: string; hostname: string; build: unknown };
    assert.strictEqual(body.app, 'aws-cicd-sample-app');
    assert.ok(body.hostname);
    assert.ok(body.build);
  } finally {
    server.close();
  }
});
