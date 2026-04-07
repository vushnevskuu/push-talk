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
    <div className="wrap">
      <header style={{ paddingBlock: "3rem 2rem" }}>
        <p className="eyebrow">VoiceInsert</p>
        <h1>Almost there</h1>
        <p className="lede">
          If Airwallex did not append the checkout id to this page URL, paste it from your browser history or Airwallex
          confirmation. Then generate your app access token once and store it in VoiceInsert → Settings.
        </p>

        <div className="card">
          <h2 style={{ fontFamily: "Fraunces, Georgia, serif", fontSize: "1.35rem", marginTop: 0 }}>Claim access</h2>
          <label htmlFor="cid">Billing checkout id</label>
          <input
            id="cid"
            type="text"
            name="checkoutId"
            autoComplete="off"
            placeholder="e.g. bc_…"
            value={checkoutId}
            onChange={(e) => setCheckoutId(e.target.value)}
            style={{ maxWidth: "100%" }}
          />
          {error ? <p className="err">{error}</p> : null}
          <div style={{ marginTop: "1rem" }}>
            <button
              type="button"
              className="btn-primary"
              disabled={loading || checkoutId.trim().length < 8}
              onClick={() => void claim()}
            >
              {loading ? "Working…" : "Generate access token"}
            </button>
          </div>

          {token ? (
            <div style={{ marginTop: "1.5rem" }}>
              <p style={{ color: "var(--color-muted)", fontSize: "0.9rem" }}>
                Your token (shown once). Paste into the macOS app Settings → Subscription.
                {email ? (
                  <>
                    <br />
                    Email on file: <strong style={{ color: "var(--color-text)" }}>{email}</strong>
                  </>
                ) : null}
              </p>
              <pre
                style={{
                  marginTop: "0.75rem",
                  padding: "1rem",
                  background: "rgba(0,0,0,0.35)",
                  borderRadius: 8,
                  overflow: "auto",
                  fontSize: "0.85rem",
                  wordBreak: "break-all",
                }}
              >
                {token}
              </pre>
            </div>
          ) : null}
        </div>

        <p style={{ marginTop: "2rem" }}>
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
