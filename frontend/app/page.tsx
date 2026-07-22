"use client";

import { useState } from "react";

type Generation = {
  id: string;
  status: string;
  prompt: string;
  result_url: string | null;
};

// Defaults to the local backend (docker-compose) - override via
// NEXT_PUBLIC_API_BASE_URL (.env.local) to point at the real deployed
// API instead and prove the pipeline works against live infra.
const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";

export default function Home() {
  const [prompt, setPrompt] = useState("");
  const [generation, setGeneration] = useState<Generation | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    setGeneration(null);
    setSubmitting(true);

    try {
      const response = await fetch(`${API_BASE_URL}/generations`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt }),
      });
      if (!response.ok) {
        throw new Error(`Request failed: ${response.status}`);
      }
      const data: Generation = await response.json();
      setGeneration(data);
      poll(data.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setSubmitting(false);
    }
  }

  function poll(id: string) {
    const interval = setInterval(async () => {
      const response = await fetch(`${API_BASE_URL}/generations/${id}`);
      if (!response.ok) {
        clearInterval(interval);
        setError(`Status check failed: ${response.status}`);
        return;
      }
      const data: Generation = await response.json();
      setGeneration(data);

      if (data.status === "completed" || data.status === "failed") {
        clearInterval(interval);
        if (data.status === "completed" && data.result_url) {
          // Best-effort: this may be a different origin than this app
          // (e.g. rivetrecords.online vs localhost:3000) with no CORS
          // configured - the result_url link below always works
          // regardless, this just tries to show the text inline too.
          try {
            const resultResponse = await fetch(data.result_url);
            const resultData = await resultResponse.json();
            setMessage(resultData.message);
          } catch {
            // Silently fall back to the link - not a failure of the
            // pipeline, just a browser CORS restriction curl never hits.
          }
        }
      }
    }, 2000);
  }

  return (
    <main style={{ maxWidth: 600, margin: "4rem auto", fontFamily: "sans-serif", padding: "0 1rem" }}>
      <h1>heartstamp</h1>
      <p>Submit a prompt, watch it generate a personalized message.</p>

      <form onSubmit={handleSubmit}>
        <textarea
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          placeholder="a short congratulations message for a friend who just adopted a puppy"
          rows={3}
          style={{ width: "100%", fontFamily: "inherit", fontSize: "1rem" }}
          required
        />
        <button type="submit" disabled={submitting || !prompt} style={{ marginTop: "0.5rem" }}>
          {submitting ? "Submitting..." : "Generate"}
        </button>
      </form>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {generation && (
        <div style={{ marginTop: "2rem" }}>
          <p>
            Status: <strong>{generation.status}</strong>
          </p>

          {message && (
            <blockquote style={{ borderLeft: "3px solid #ccc", paddingLeft: "1rem", margin: "1rem 0" }}>
              {message}
            </blockquote>
          )}

          {generation.status === "completed" && generation.result_url && (
            <p>
              <a href={generation.result_url} target="_blank" rel="noreferrer">
                View raw result
              </a>
            </p>
          )}

          {generation.status === "failed" && (
            <p style={{ color: "crimson" }}>Generation failed - check the worker logs.</p>
          )}
        </div>
      )}
    </main>
  );
}
