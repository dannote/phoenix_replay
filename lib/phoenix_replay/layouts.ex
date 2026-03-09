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
        <link rel="stylesheet" href="/assets/css/app.css" />

        <script defer type="text/javascript" src="/assets/js/app.js">
        </script>
        <script>
          <%= Phoenix.HTML.raw(PhoenixReplay.Layouts.player_js()) %>
        </script>
      </head>
      <body class="m-0 font-sans bg-neutral-100 text-neutral-900 antialiased">
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

      var events = [];
      var playing = false;
      var speed = 1;
      var eventTimerId = null;
      var rafId = null;
      var playStartWall = 0;
      var playStartMs = 0;
      var currentEventIdx = 0;
      var currentMs = 0;
      var durationMs = 0;
      var dragging = false;

      function getEl(id) { return document.getElementById(id); }
      function lastIndex() { return Math.max(0, events.length - 1); }

      function msToEventIndex(ms) {
        var best = 0;
        for (var i = 0; i < events.length; i++) {
          if (events[i].ms <= ms) best = i;
          else break;
        }
        return best;
      }

      function sendForm(formId, inputName, value) {
        var form = getEl(formId);
        if (!form) return;
        var input = form.querySelector("input[name=" + inputName + "]");
        if (!input) return;
        input.value = String(value);
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }

      function sendTick(index) { sendForm("rp-tick-bridge", "index", index); }
      function sendScrub(index) { sendForm("rp-scrub-bridge", "index", index); }
      function sendEnded() { sendForm("rp-ended-bridge", "ended", "1"); }

      function setThumb(ms) {
        currentMs = ms;
        var thumb = getEl("rp-thumb");
        if (!thumb) return;
        var pct = durationMs > 0 ? (ms / durationMs) * 100 : 0;
        thumb.style.left = pct + "%";
      }

      function currentPlayMs() {
        var elapsed = (performance.now() - playStartWall) * speed;
        return Math.min(playStartMs + elapsed, durationMs);
      }

      function animateScrubber() {
        if (!playing) return;
        setThumb(currentPlayMs());
        rafId = requestAnimationFrame(animateScrubber);
      }

      function stopAll() {
        playing = false;
        if (eventTimerId) { clearTimeout(eventTimerId); eventTimerId = null; }
        if (rafId) { cancelAnimationFrame(rafId); rafId = null; }
      }

      function scheduleNextEvent(fromIndex) {
        if (!playing) return;
        var nextIndex = fromIndex + 1;
        if (nextIndex > lastIndex()) {
          stopAll();
          sendEnded();
          return;
        }
        var delayMs = (events[nextIndex].ms - events[fromIndex].ms) / speed;
        eventTimerId = setTimeout(function() {
          if (!playing) return;
          currentEventIdx = nextIndex;
          sendTick(nextIndex);
          scheduleNextEvent(nextIndex);
        }, delayMs);
      }

      /* Pointer → ms conversion */
      function pointerToMs(e) {
        var scrubber = getEl("rp-scrubber");
        if (!scrubber) return 0;
        var rect = scrubber.getBoundingClientRect();
        var pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        return pct * durationMs;
      }

      /* Pointer events on the scrubber */
      document.addEventListener("pointerdown", function(e) {
        var scrubber = getEl("rp-scrubber");
        if (!scrubber || !scrubber.contains(e.target)) return;
        e.preventDefault();
        dragging = true;
        scrubber.setPointerCapture(e.pointerId);
        if (playing) stopAll();
        var ms = pointerToMs(e);
        setThumb(ms);
        var idx = msToEventIndex(ms);
        sendScrub(idx);
      });

      document.addEventListener("pointermove", function(e) {
        if (!dragging) return;
        var ms = pointerToMs(e);
        setThumb(ms);
        var idx = msToEventIndex(ms);
        sendScrub(idx);
      });

      document.addEventListener("pointerup", function(e) {
        if (!dragging) return;
        dragging = false;
        var scrubber = getEl("rp-scrubber");
        if (scrubber) scrubber.releasePointerCapture(e.pointerId);
      });

      /* Server → JS events */

      window.addEventListener("phx:init", function(e) {
        events = e.detail.events || [];
        speed = e.detail.speed || 1;
        durationMs = events.length > 0 ? events[lastIndex()].ms : 0;
        stopAll();
        currentEventIdx = 0;
        setThumb(0);
      });

      window.addEventListener("phx:play", function(e) {
        speed = e.detail.speed || 1;
        var idx = msToEventIndex(currentMs);

        if (idx >= lastIndex()) {
          idx = 0;
          currentMs = 0;
          setThumb(0);
          sendTick(0);
        }

        currentEventIdx = idx;
        playStartMs = currentMs;
        playStartWall = performance.now();
        playing = true;

        scheduleNextEvent(idx);
        rafId = requestAnimationFrame(animateScrubber);
      });

      window.addEventListener("phx:stop", function() {
        var ms = playing ? currentPlayMs() : currentMs;
        stopAll();
        setThumb(ms);
      });

      window.addEventListener("phx:speed", function(e) {
        var newSpeed = e.detail.speed || 1;
        if (playing) {
          var ms = currentPlayMs();
          playStartMs = ms;
          playStartWall = performance.now();
          speed = newSpeed;
          if (eventTimerId) { clearTimeout(eventTimerId); eventTimerId = null; }
          scheduleNextEvent(currentEventIdx);
        } else {
          speed = newSpeed;
        }
      });

      window.addEventListener("phx:jump", function(e) {
        var idx = e.detail.index || 0;
        var ms = events[idx] ? events[idx].ms : 0;
        setThumb(ms);
      });
    })();
    """
  end


end
