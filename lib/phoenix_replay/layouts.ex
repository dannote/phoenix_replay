defmodule PhoenixReplay.Layouts do
  @moduledoc false
  use Phoenix.Component

  def frame(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <link rel="stylesheet" href="/assets/css/app.css" />
        <style>
          body { margin: 0; pointer-events: none; user-select: none; }
        </style>
        <script defer type="text/javascript" src="/assets/js/app.js">
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>{assigns[:page_title] || "PhoenixReplay"}</title>
        <style>
          <%= PhoenixReplay.Layouts.css() %>
        </style>
        <script defer type="text/javascript" src="/assets/js/app.js">
        </script>
        <script>
          <%= Phoenix.HTML.raw(PhoenixReplay.Layouts.player_js()) %>
        </script>
      </head>
      <body style="margin:0; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background:#f5f5f5; color:#1a1a1a;">
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc false
  def player_js do
    ~s"""
    (function() {
      "use strict";

      /*
       * DISCRETE EVENT PLAYER
       *
       * Server is source of truth for: current_index, playing state, time display, buttons.
       * JS only drives: playback timer (when to advance to next event) and scrubber position.
       *
       * Play = schedule setTimeout chain, each tick sends next index to server.
       * Server updates current_index, re-renders time/buttons, broadcasts to iframe.
       * Scrubber has phx-update="ignore" so server can't reset its position.
       */

      var events = [];
      var playing = false;
      var speed = 1;
      var timerId = null;

      function getEl(id) { return document.getElementById(id); }

      function sendTick(index) {
        var form = getEl("rp-tick-bridge");
        if (!form) return;
        var input = form.querySelector("input[name=index]");
        if (!input) return;
        input.value = String(index);
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }

      function sendScrub(index) {
        var form = getEl("rp-scrub-bridge");
        if (!form) return;
        var input = form.querySelector("input[name=index]");
        if (!input) return;
        input.value = String(index);
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }

      function sendEnded() {
        var form = getEl("rp-ended-bridge");
        if (!form) return;
        var input = form.querySelector("input[name=ended]");
        if (!input) return;
        input.value = "1";
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }

      function stopTimer() {
        playing = false;
        if (timerId) { clearTimeout(timerId); timerId = null; }
      }

      function currentScrubberIndex() {
        var el = getEl("rp-scrubber");
        return el ? parseInt(el.value, 10) : 0;
      }

      function lastIndex() {
        return Math.max(0, events.length - 1);
      }

      function scheduleNext(fromIndex) {
        if (!playing) return;
        var nextIndex = fromIndex + 1;
        if (nextIndex > lastIndex()) {
          stopTimer();
          sendEnded();
          return;
        }

        var delayMs = (events[nextIndex].ms - events[fromIndex].ms) / speed;

        timerId = setTimeout(function() {
          if (!playing) return;

          var scrubber = getEl("rp-scrubber");
          if (scrubber) scrubber.value = nextIndex;

          sendTick(nextIndex);
          scheduleNext(nextIndex);
        }, delayMs);
      }

      /* --- Server -> JS events --- */

      window.addEventListener("phx:init", function(e) {
        events = e.detail.events || [];
        speed = e.detail.speed || 1;
        stopTimer();
      });

      window.addEventListener("phx:play", function(e) {
        speed = e.detail.speed || 1;
        var idx = currentScrubberIndex();
        if (idx >= lastIndex()) {
          idx = 0;
          var scrubber = getEl("rp-scrubber");
          if (scrubber) scrubber.value = 0;
          sendTick(0);
        }
        playing = true;
        scheduleNext(idx);
      });

      window.addEventListener("phx:stop", function() {
        stopTimer();
      });

      window.addEventListener("phx:speed", function(e) {
        var idx = currentScrubberIndex();
        speed = e.detail.speed || 1;
        if (playing) {
          if (timerId) { clearTimeout(timerId); timerId = null; }
          scheduleNext(idx);
        }
      });

      /* --- User scrubber interaction --- */

      document.addEventListener("input", function(e) {
        if (e.target.id === "rp-scrubber") {
          if (playing) { stopTimer(); }
          sendScrub(parseInt(e.target.value, 10));
        }
      });
    })();
    """
  end

  def css do
    """
    *, *::before, *::after { box-sizing: border-box; }
    a { color: #4f46e5; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .rp-container { max-width: 960px; margin: 0 auto; padding: 2rem 1rem; }
    .rp-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 2rem; }
    .rp-header h1 { font-size: 1.5rem; font-weight: 700; margin: 0; }
    .rp-card { background: #fff; border-radius: 8px; border: 1px solid #e5e5e5; margin-bottom: 0.75rem; transition: box-shadow 0.15s; }
    .rp-card:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
    .rp-card-body { padding: 1rem 1.25rem; }
    .rp-badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 0.75rem; font-weight: 600; }
    .rp-badge-live { background: #dcfce7; color: #166534; }
    .rp-badge-done { background: #e5e5e5; color: #525252; }
    .rp-muted { color: #737373; }
    .rp-mono { font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace; }
    .rp-btn { display: inline-flex; align-items: center; gap: 0.25rem; padding: 0.375rem 0.75rem; border-radius: 6px; border: 1px solid #d4d4d4; background: #fff; cursor: pointer; font-size: 0.875rem; }
    .rp-btn:hover { background: #f5f5f5; }
    .rp-btn:disabled { opacity: 0.4; cursor: default; }
    .rp-btn-primary { background: #4f46e5; color: #fff; border-color: #4f46e5; }
    .rp-btn-primary:hover { background: #4338ca; }
    .rp-btn-warning { background: #f59e0b; color: #fff; border-color: #f59e0b; }
    .rp-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }
    @media (max-width: 768px) { .rp-grid { grid-template-columns: 1fr; } }
    .rp-controls { display: flex; align-items: center; gap: 0.75rem; padding: 1rem 1.25rem; }
    .rp-range { flex: 1; }
    .rp-timeline { max-height: 500px; overflow-y: auto; }
    .rp-timeline-item { display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem 0.75rem; border-radius: 6px; cursor: pointer; font-size: 0.875rem; border: none; background: none; width: 100%; text-align: left; }
    .rp-timeline-item:hover { background: #f0f0f0; }
    .rp-timeline-item.active { background: #4f46e5; color: #fff; }
    .rp-timeline-item.future { opacity: 0.35; }
    .rp-pre { background: #f0f0f0; border-radius: 6px; padding: 0.75rem; font-size: 0.8125rem; overflow-x: auto; white-space: pre-wrap; word-break: break-word; margin: 0; max-height: 320px; overflow-y: auto; }
    .rp-empty { text-align: center; padding: 4rem 1rem; color: #a3a3a3; }
    .rp-empty-icon { font-size: 3rem; margin-bottom: 1rem; }
    .rp-speed-menu { position: relative; display: inline-block; }
    .rp-speed-menu ul { display: none; position: absolute; bottom: 100%; right: 0; background: #fff; border: 1px solid #e5e5e5; border-radius: 6px; padding: 0.25rem; margin: 0; list-style: none; box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
    .rp-speed-menu:hover ul { display: block; }
    .rp-speed-menu li { padding: 0.25rem 0.75rem; cursor: pointer; border-radius: 4px; font-size: 0.875rem; white-space: nowrap; }
    .rp-speed-menu li:hover { background: #f0f0f0; }
    .rp-scrub-wrap { position: relative; height: 20px; }
    .rp-scrub-marker { position: absolute; top: 5px; width: 8px; height: 10px; margin-left: -4px; display: flex; align-items: center; justify-content: center; pointer-events: none; z-index: 1; }
    .rp-scrub-range { -webkit-appearance: none; appearance: none; width: 100%; height: 4px; margin: 8px 0; cursor: pointer; position: relative; z-index: 2; border-radius: 2px; background: #e5e5e5; }
    .rp-scrub-range::-webkit-slider-thumb { -webkit-appearance: none; width: 14px; height: 14px; border-radius: 50%; background: #4f46e5; border: 2px solid #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.15); }
    .rp-scrub-range::-moz-range-track { height: 4px; background: #e5e5e5; border: none; border-radius: 2px; }
    .rp-scrub-range::-moz-range-progress { height: 4px; background: #4f46e5; border-radius: 2px; }
    .rp-scrub-range::-moz-range-thumb { width: 14px; height: 14px; border-radius: 50%; background: #4f46e5; border: 2px solid #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.15); }
    .rp-hidden { display: none !important; }
    .rp-dot-live { display: inline-block; width: 8px; height: 8px; background: #22c55e; border-radius: 50%; animation: rp-pulse 2s infinite; }
    @keyframes rp-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
    """
  end
end
