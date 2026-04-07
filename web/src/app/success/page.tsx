"use client";

import { useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";

function SuccessInner() {
  const sp = useSearchParams();
  const [checkoutId, setCheckoutId] = useState("");
  const [token, setToken] = useState<string | null>(null);
  const [email, setEmail] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const q =
      sp.get("checkout_id") ??
      sp.get("checkoutId") ??
      sp.get("id") ??
      sp.get("checkout") ??
      "";
    if (q) {
      setCheckoutId(q);
      return;
    }
    try {
      const stored = window.sessionStorage.getItem("vi_checkout_id");
      if (stored) {
        setCheckoutId(stored);
      }
    } catch {
      /* ignore */
    }
  }, [sp]);

  async function claim() {
    setError(null);
    setLoading(true);
    setToken(null);
    try {
      const res = await fetch("/api/claim", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ checkoutId: checkoutId.trim() }),
      });
      const data = (await res.json()) as { accessToken?: string; email?: string; error?: string; status?: unknown };
      if (!res.ok) {
        throw new Error(data.error ?? "Claim failed");
      }
      if (!data.accessToken) {
        throw new Error("No token returned");
      }
      setToken(data.accessToken);
      setEmail(data.email ?? null);
      try {
        window.sessionStorage.removeItem("vi_checkout_id");
      } catch {
        /* ignore */
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="wrap page-simple">
      <header className="page-simple-header">
        <p className="eyebrow">VoiceInsert</p>
        <h1>Almost there</h1>
        <p className="lede page-simple-lede">
          If the checkout id is missing from this URL, copy it from your payment confirmation or browser history. Then
          generate your token once and paste it in the app.
        </p>

        <ol className="success-steps" aria-label="Steps after checkout">
          <li>Paste or confirm the billing checkout id below.</li>
          <li>Click <strong>Generate access token</strong>.</li>
          <li>Open VoiceInsert → Settings → Subscription and paste the token.</li>
        </ol>

        <div className="card">
          <h2 className="claim-card-title">Claim access</h2>
          <label htmlFor="cid">Billing checkout id</label>
          <input
            id="cid"
            className="input-field"
            type="text"
            name="checkoutId"
            autoComplete="off"
            placeholder="e.g. bc_…"
            value={checkoutId}
            onChange={(e) => setCheckoutId(e.target.value)}
          />
          {error ? <p className="err">{error}</p> : null}
          <div className="trial-actions">
            <button
              type="button"
              className="btn-primary"
              disabled={loading || checkoutId.trim().length < 8}
              aria-busy={loading}
              aria-label={loading ? "Generating token" : "Generate access token"}
              onClick={() => void claim()}
            >
              {loading ? "Working…" : "Generate access token"}
            </button>
          </div>

          {token ? (
            <div className="token-result">
              <p className="token-result-copy">
                Your token (shown once). Paste into the macOS app Settings → Subscription.
                {email ? (
                  <>
                    <br />
                    Email on file: <strong className="token-result-email">{email}</strong>
                  </>
                ) : null}
              </p>
              <pre className="token-block">{token}</pre>
            </div>
          ) : null}
        </div>

        <p className="page-simple-footer-link">
          <a href="/">← Back to home</a>
        </p>
      </header>
    </div>
  );
}

export default function SuccessPage() {
  return (
    <Suspense fallback={<div className="wrap">Loading…</div>}>
      <SuccessInner />
    </Suspense>
  );
}
