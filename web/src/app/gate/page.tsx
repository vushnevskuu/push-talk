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
    <div className="wrap">
      <header style={{ paddingBlock: "3rem 2rem" }}>
        <p className="eyebrow">Internal</p>
        <h1>Access</h1>
        <p className="lede">Не индексируется с главной. Токен вставьте в VoiceInsert → Settings → Subscription.</p>

        <div className="card">
          <label htmlFor="lg">Login</label>
          <input
            id="lg"
            type="text"
            name="login"
            autoComplete="username"
            value={login}
            onChange={(e) => setLogin(e.target.value)}
            style={{ maxWidth: "100%", marginBottom: "1rem" }}
          />
          <label htmlFor="pw">Password</label>
          <input
            id="pw"
            type="password"
            name="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            style={{ maxWidth: "100%" }}
          />
          {error ? <p className="err">{error}</p> : null}
          <div style={{ marginTop: "1rem" }}>
            <button type="button" className="btn-primary" disabled={loading} onClick={() => void submit()}>
              {loading ? "…" : "Issue token"}
            </button>
          </div>
          {token ? (
            <pre
              style={{
                marginTop: "1.25rem",
                padding: "1rem",
                background: "rgba(0,0,0,0.35)",
                borderRadius: 8,
                fontSize: "0.85rem",
                wordBreak: "break-all",
              }}
            >
              {token}
            </pre>
          ) : null}
        </div>
        <p style={{ marginTop: "2rem" }}>
          <a href="/">Home</a>
        </p>
      </header>
    </div>
  );
}
