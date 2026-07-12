import { describe, it, expect, vi, beforeEach } from 'vitest';
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import worker from './worker';

const VALID_TOKEN = 'test-bff-token';
const VALID_PROVIDER = 'deepseek';

function createChatRequest(token = VALID_TOKEN, provider = VALID_PROVIDER) {
  return new Request('http://example.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'X-BFF-Token': token,
      'X-Provider': provider,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: 'test-model', messages: [] }),
  });
}

describe('BFF Token Validation', () => {
  beforeEach(async () => {
    await env.bff_tokens.put(VALID_TOKEN, JSON.stringify({ user: 'test-user' }));
  });

  it('returns 401 when X-BFF-Token is missing', async () => {
    const request = new Request('http://example.com/v1/chat/completions', { method: 'POST' });
    const response = await worker.fetch(request, env, createExecutionContext());
    expect(response.status).toBe(401);
  });

  it('returns 401 when the token is not in KV', async () => {
    const request = createChatRequest('unknown-token');
    const response = await worker.fetch(request, env, createExecutionContext());
    expect(response.status).toBe(401);
  });

  it('returns 400 for unknown provider', async () => {
    const request = createChatRequest(VALID_TOKEN, 'unknown-provider');
    const response = await worker.fetch(request, env, createExecutionContext());
    expect(response.status).toBe(400);
  });
});

describe('BFF Global Rate Limit', () => {
  beforeEach(async () => {
    await env.bff_tokens.put(VALID_TOKEN, JSON.stringify({ user: 'test-user' }));
  });

  it('allows the first request within the rate limit window', async () => {
    const mockFetch = vi.fn().mockResolvedValue(new Response('ok', { status: 200 }));
    vi.stubGlobal('fetch', mockFetch);

    const request = createChatRequest();
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(200);
    expect(mockFetch).toHaveBeenCalledTimes(1);
  });

  it('allows up to 60 requests per token per minute', async () => {
    const mockFetch = vi.fn().mockResolvedValue(new Response('ok', { status: 200 }));
    vi.stubGlobal('fetch', mockFetch);

    for (let i = 0; i < 60; i++) {
      const request = createChatRequest();
      const ctx = createExecutionContext();
      const response = await worker.fetch(request, env, ctx);
      await waitOnExecutionContext(ctx);
      expect(response.status).toBe(200);
    }

    expect(mockFetch).toHaveBeenCalledTimes(60);
  });

  it('returns 429 when the token exceeds 60 requests in the same window', async () => {
    const mockFetch = vi.fn().mockResolvedValue(new Response('ok', { status: 200 }));
    vi.stubGlobal('fetch', mockFetch);

    for (let i = 0; i < 60; i++) {
      const request = createChatRequest();
      const ctx = createExecutionContext();
      await worker.fetch(request, env, ctx);
      await waitOnExecutionContext(ctx);
    }

    const request = createChatRequest();
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('60');
    const body = await response.json();
    expect(body.error).toContain('rate limited');
  });

  it('persists rate limit counters in KV for cross-instance enforcement', async () => {
    const mockFetch = vi.fn().mockResolvedValue(new Response('ok', { status: 200 }));
    vi.stubGlobal('fetch', mockFetch);

    const request = createChatRequest();
    const ctx = createExecutionContext();
    await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    const list = await env.rate_limits.list();
    expect(list.keys.length).toBeGreaterThan(0);
    expect(list.keys.some((k) => k.name.includes(VALID_TOKEN))).toBe(true);
  });

  it('allows a different token to make requests independently', async () => {
    const otherToken = 'other-bff-token';
    await env.bff_tokens.put(otherToken, JSON.stringify({ user: 'other-user' }));

    const mockFetch = vi.fn().mockResolvedValue(new Response('ok', { status: 200 }));
    vi.stubGlobal('fetch', mockFetch);

    for (let i = 0; i < 60; i++) {
      const request = createChatRequest(VALID_TOKEN);
      const ctx = createExecutionContext();
      await worker.fetch(request, env, ctx);
      await waitOnExecutionContext(ctx);
    }

    const request = createChatRequest(otherToken);
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(response.status).toBe(200);
  });
});
