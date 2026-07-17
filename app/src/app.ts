import express, { type Express, type Request, type Response, type NextFunction } from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import * as promClient from 'prom-client';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { monitorEventLoopDelay } from 'node:perf_hooks';

const startedAt = Date.now();
let requestsServed = 0;

// Event-loop delay is the truest single-process saturation signal: it rises
// before CPU or memory look alarming.
const loopDelay = monitorEventLoopDelay({ resolution: 20 });
loopDelay.enable();

// Ring buffer of recent requests: the raw material for live SLIs and the
// on-page access log. Capped so memory stays flat.
interface AccessRecord {
  t: number;
  method: string;
  path: string;
  status: number;
  ms: number;
}
const recentRequests: AccessRecord[] = [];
const RECENT_CAP = 500;

// Targets mirror docs/slo.md. If you change one, change both.
const SLO_TARGETS = {
  availabilityPct: 99.5,
  latencyP99Ms: 300,
  errorRatePct: 1,
};

function percentile(sortedMs: number[], p: number): number {
  if (sortedMs.length === 0) return 0;
  const idx = Math.min(sortedMs.length - 1, Math.ceil((p / 100) * sortedMs.length) - 1);
  return sortedMs[Math.max(0, idx)];
}

// Tracing (X-Ray) is opt-in via ENABLE_XRAY=true so local dev and tests
// need no daemon. Segments are sent over UDP to the X-Ray daemon on the
// instance; a missing daemon degrades to log lines, never to failures.
const xrayEnabled = process.env.ENABLE_XRAY === 'true';
type XrayExpress = {
  openSegment: (name: string) => express.RequestHandler;
  closeSegment: () => express.ErrorRequestHandler | express.RequestHandler;
};
let xray: XrayExpress | null = null;
if (xrayEnabled) {
  process.env.AWS_XRAY_CONTEXT_MISSING = process.env.AWS_XRAY_CONTEXT_MISSING || 'LOG_ERROR';
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  xray = require('aws-xray-sdk-express') as XrayExpress;
}

const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });
const httpDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency by method, route, and status',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1],
  registers: [register],
});

export interface BuildInfo {
  commit: string;
  buildId: string;
  builtAt: string | null;
}

const publicDir = path.join(__dirname, '..', 'public');

export function readBuildInfo(): BuildInfo {
  try {
    const raw = fs.readFileSync(path.join(publicDir, 'build-info.json'), 'utf8');
    return JSON.parse(raw) as BuildInfo;
  } catch {
    return { commit: 'local', buildId: 'local', builtAt: null };
  }
}

export function healthPayload() {
  return {
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  };
}

export function telemetryPayload() {
  const mem = process.memoryUsage();
  return {
    startedAt,
    uptimeSeconds: process.uptime(),
    hostname: os.hostname(),
    platform: `${os.platform()}/${os.arch()}`,
    nodeVersion: process.version,
    pid: process.pid,
    rssBytes: mem.rss,
    heapUsedBytes: mem.heapUsed,
    loadAverage: os.loadavg().map((n) => Number(n.toFixed(2))),
    cpuCount: os.cpus().length,
    requestsServed,
  };
}

export function sliPayload() {
  const now = Date.now();
  const total = recentRequests.length;
  const errors = recentRequests.filter((r) => r.status >= 500).length;
  const durations = recentRequests.map((r) => r.ms).sort((a, b) => a - b);
  const availabilityPct = total === 0 ? 100 : ((total - errors) / total) * 100;
  const errorRatePct = total === 0 ? 0 : (errors / total) * 100;
  const p95 = percentile(durations, 95);
  const p99 = percentile(durations, 99);
  const lastMinute = recentRequests.filter((r) => now - r.t <= 60_000).length;
  const errorsLast5m = recentRequests.filter((r) => now - r.t <= 300_000 && r.status >= 500).length;
  const budgetUsedPct = Math.min(
    100,
    (errorRatePct / 100 / (1 - SLO_TARGETS.availabilityPct / 100)) * 100
  );
  const mem = process.memoryUsage();

  return {
    window: {
      requests: total,
      seconds: total === 0 ? 0 : Math.round((now - recentRequests[0].t) / 1000),
      cap: RECENT_CAP,
    },
    slo: {
      availability: {
        currentPct: Number(availabilityPct.toFixed(2)),
        targetPct: SLO_TARGETS.availabilityPct,
        met: availabilityPct >= SLO_TARGETS.availabilityPct,
      },
      latencyP99: {
        currentMs: Number(p99.toFixed(1)),
        targetMs: SLO_TARGETS.latencyP99Ms,
        met: p99 < SLO_TARGETS.latencyP99Ms,
      },
      errorRate: {
        currentPct: Number(errorRatePct.toFixed(2)),
        targetPct: SLO_TARGETS.errorRatePct,
        met: errorRatePct < SLO_TARGETS.errorRatePct,
      },
      budgetUsedPct: Number(budgetUsedPct.toFixed(1)),
    },
    golden: {
      trafficRpm: lastMinute,
      latencyP95Ms: Number(p95.toFixed(1)),
      errorsLast5m,
      saturation: {
        loopLagP99Ms: Number((loopDelay.percentile(99) / 1e6).toFixed(1)),
        load1PerCore: Number((os.loadavg()[0] / os.cpus().length).toFixed(2)),
        heapUsedPct: Number(((mem.heapUsed / mem.heapTotal) * 100).toFixed(0)),
      },
    },
    telemetry: {
      metrics: '/metrics',
      logs: '/aws-cicd/app',
      traces: { enabled: xrayEnabled, service: 'aws-cicd-sample-app' },
    },
    recent: recentRequests.slice(-6).reverse(),
  };
}

export { SLO_TARGETS };

export function createApp(): Express {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  if (xray) app.use(xray.openSegment('aws-cicd-sample-app'));

  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
          fontSrc: ["'self'", 'https://fonts.gstatic.com'],
          scriptSrc: ["'self'", "'unsafe-inline'"],
          imgSrc: ["'self'", 'data:'],
          connectSrc: ["'self'"],
          objectSrc: ["'none'"],
          frameAncestors: ["'none'"],
        },
      },
    })
  );

  const apiLimiter = rateLimit({
    windowMs: 60 * 1000,
    limit: 120,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: { error: 'rate limit exceeded' },
  });
  app.use('/api', apiLimiter);

  app.use((req: Request, res: Response, next: NextFunction) => {
    requestsServed += 1;
    const start = process.hrtime.bigint();
    res.on('finish', () => {
      const ms = Number(process.hrtime.bigint() - start) / 1e6;
      recentRequests.push({
        t: Date.now(),
        method: req.method,
        path: req.path,
        status: res.statusCode,
        ms: Number(ms.toFixed(1)),
      });
      if (recentRequests.length > RECENT_CAP) recentRequests.shift();
      httpDuration.observe(
        { method: req.method, route: req.path, status: res.statusCode },
        ms / 1000
      );
      // Structured access log: shipped to CloudWatch Logs by the agent,
      // where a metric filter on status >= 500 drives the error-rate alarm.
      console.log(
        JSON.stringify({
          time: new Date().toISOString(),
          level: res.statusCode >= 500 ? 'error' : 'info',
          method: req.method,
          path: req.path,
          status: res.statusCode,
          ms: Number(ms.toFixed(1)),
        })
      );
    });
    next();
  });

  app.get('/metrics', async (_req: Request, res: Response) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  app.use(express.static(publicDir));

  app.get('/api/health', (_req: Request, res: Response) => {
    res.json(healthPayload());
  });

  app.get('/api/telemetry', (_req: Request, res: Response) => {
    res.json(telemetryPayload());
  });

  app.get('/api/sli', (_req: Request, res: Response) => {
    res.json(sliPayload());
  });

  app.get('/api/info', (_req: Request, res: Response) => {
    res.json({
      app: 'aws-cicd-sample-app',
      version: process.env.APP_VERSION || '2.0.0',
      hostname: os.hostname(),
      build: readBuildInfo(),
    });
  });

  app.use((_req: Request, res: Response) => {
    res.status(404).json({ error: 'not found' });
  });

  if (xray) app.use(xray.closeSegment());

  return app;
}
