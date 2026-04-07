const TOKEN_TTL_MS = 25 * 60 * 1000;

let cachedToken: { value: string; expiresAt: number } | null = null;

function baseUrl(): string {
  return process.env.AIRWALLEX_API_BASE?.replace(/\/$/, "") ?? "https://api.airwallex.com";
}

export async function airwallexBearerToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 5000) {
    return cachedToken.value;
  }

  const clientId = process.env.AIRWALLEX_CLIENT_ID;
  const apiKey = process.env.AIRWALLEX_API_KEY;
  if (!clientId || !apiKey) {
    throw new Error("AIRWALLEX_CLIENT_ID and AIRWALLEX_API_KEY must be set");
  }

  const headers: Record<string, string> = {
    Accept: "application/json",
    "Content-Type": "application/json",
    "x-client-id": clientId,
    "x-api-key": apiKey,
  };
  const loginAs = process.env.AIRWALLEX_LOGIN_AS;
  if (loginAs) {
    headers["x-login-as"] = loginAs;
  }

  const res = await fetch(`${baseUrl()}/api/v1/authentication/login`, {
    method: "POST",
    headers,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Airwallex login failed: ${res.status} ${text}`);
  }

  const data = (await res.json()) as { token?: string; expires_at?: string };
  const token = data.token;
  if (!token) {
    throw new Error("Airwallex login: missing token");
  }

  let expiresAt = now + TOKEN_TTL_MS;
  if (data.expires_at) {
    const parsed = Date.parse(data.expires_at);
    if (!Number.isNaN(parsed)) {
      expiresAt = parsed;
    }
  }

  cachedToken = { value: token, expiresAt };
  return token;
}

async function awxFetch(path: string, init: RequestInit): Promise<Response> {
  const bearer = await airwallexBearerToken();
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${bearer}`);
  if (!headers.has("Content-Type") && init.body) {
    headers.set("Content-Type", "application/json");
  }
  return fetch(`${baseUrl()}${path}`, { ...init, headers });
}

export async function createBillingCheckout(body: Record<string, unknown>): Promise<unknown> {
  const res = await awxFetch("/api/v1/billing_checkouts/create", {
    method: "POST",
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(
      `billing_checkouts/create: ${res.status} ${typeof data === "object" ? JSON.stringify(data) : String(data)}`,
    );
  }
  return data;
}

export async function retrieveBillingCheckout(checkoutId: string): Promise<Record<string, unknown>> {
  const res = await awxFetch(`/api/v1/billing_checkouts/${encodeURIComponent(checkoutId)}`, {
    method: "GET",
  });
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    throw new Error(`billing_checkouts/retrieve: ${res.status} ${JSON.stringify(data)}`);
  }
  return data;
}

export async function retrieveSubscription(subscriptionId: string): Promise<Record<string, unknown>> {
  const res = await awxFetch(`/api/v1/subscriptions/${encodeURIComponent(subscriptionId)}`, {
    method: "GET",
  });
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    throw new Error(`subscriptions/retrieve: ${res.status} ${JSON.stringify(data)}`);
  }
  return data;
}
