"use client";

import { useState } from "react";

export default function GatePage() {
  const [login, setLogin] = useState("");
  const [password, setPassword] = useState("");
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    setToken(null);
    setLoading(true);
    try {
      const res = await fetch("/api/backdoor-session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ login, password }),
      });
      const data = (await res.json()) as { accessToken?: string; error?: string };
      if (!res.ok) {
        throw new Error(data.error ?? "Request failed");
      }
      if (!data.accessToken) {
        throw new Error("No token");
      }
      setToken(data.accessToken);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="wrap page-simple">
      <header className="page-simple-header">
        <p className="eyebrow">Internal</p>
        <h1>Access</h1>
        <p className="lede page-simple-lede">
          Not linked from the public site. Copy the token into VoiceInsert → Settings → Subscription.
        </p>

        <div className="card">
          <label htmlFor="lg">Login</label>
          <input
            id="lg"
            className="input-field input-stack"
            type="text"
            name="login"
            autoComplete="username"
            value={login}
            onChange={(e) => setLogin(e.target.value)}
          />
          <label htmlFor="pw">Password</label>
          <input
            id="pw"
            className="input-field"
            type="password"
            name="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          {error ? <p className="err">{error}</p> : null}
          <div className="trial-actions">
            <button
              type="button"
              className="btn-primary"
              disabled={loading}
              aria-busy={loading}
              aria-label={loading ? "Issuing token" : "Issue access token"}
              onClick={() => void submit()}
            >
              {loading ? "Working…" : "Issue token"}
            </button>
          </div>
          {token ? <pre className="token-block token-block-spaced">{token}</pre> : null}
        </div>
      </header>
    </div>
  );
}
