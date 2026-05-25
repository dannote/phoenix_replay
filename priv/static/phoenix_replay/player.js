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

  function pointerToMs(e) {
    var scrubber = getEl("rp-scrubber");
    if (!scrubber) return 0;
    var rect = scrubber.getBoundingClientRect();
    var pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    return pct * durationMs;
  }

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

  function scrollActiveEvent() {
    var container = getEl("rp-events");
    if (!container) return;
    var active = container.querySelector("[class*='bg-neutral-900']");
    if (!active) return;
    container.scrollTop = active.offsetTop - container.offsetTop;
  }

  var scrollObserver = new MutationObserver(scrollActiveEvent);

  function observeEvents() {
    var container = getEl("rp-events");
    if (container) scrollObserver.observe(container, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
  }

  document.addEventListener("DOMContentLoaded", observeEvents);
  window.addEventListener("phx:init", observeEvents);
})();
