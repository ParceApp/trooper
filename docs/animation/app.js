/**
 * Trooper Architecture Flow Animation Engine
 * Simulates Reactive Data Flow, SWR, Cache Hits, and Concurrency Coalescing
 */

class FlowAnimationEngine {
  constructor() {
    this.stage = document.getElementById('flowStage');
    this.svg = document.getElementById('connectionsSvg');
    this.guideLinesGroup = document.getElementById('guideLines');
    this.activePathsGroup = document.getElementById('activePaths');
    this.particlesGroup = document.getElementById('particles');

    // UI & Monitor elements
    this.scenarioTitle = document.getElementById('scenarioTitle');
    this.stepBadge = document.getElementById('stepBadge');
    this.tickerEntry = document.getElementById('tickerEntry');

    this.uiCard = document.getElementById('nodeUi');
    this.uiStatusPill = document.getElementById('uiStatusPill');
    this.widgetName = document.getElementById('widgetName');
    this.widgetRole = document.getElementById('widgetRole');
    this.widgetStateBadge = document.getElementById('widgetStateBadge');
    this.widgetLatency = document.getElementById('widgetLatency');

    this.controllerCard = document.getElementById('nodeController');
    this.controllerStatusPill = document.getElementById('controllerStatusPill');

    this.queueCard = document.getElementById('nodeQueue');
    this.queueStatusPill = document.getElementById('queueStatusPill');
    this.queueInFlight = document.getElementById('queueInFlight');
    this.queueCallers = document.getElementById('queueCallers');

    this.cacheCard = document.getElementById('nodeCache');
    this.cacheStatusPill = document.getElementById('cacheStatusPill');
    this.ttlFill = document.getElementById('ttlFill');
    this.cacheFreshness = document.getElementById('cacheFreshness');
    this.cacheAge = document.getElementById('cacheAge');

    this.storageCard = document.getElementById('nodeStorage');
    this.storageStatusPill = document.getElementById('storageStatusPill');
    this.storageCode = document.getElementById('storageCode');

    this.apiCard = document.getElementById('nodeApi');
    this.apiStatusPill = document.getElementById('apiStatusPill');
    this.apiActivity = document.getElementById('apiActivity');
    this.apiStatusText = document.getElementById('apiStatusText');

    // Nodes registry
    this.nodes = {
      ui: document.getElementById('nodeUi'),
      controller: document.getElementById('nodeController'),
      queue: document.getElementById('nodeQueue'),
      cache: document.getElementById('nodeCache'),
      storage: document.getElementById('nodeStorage'),
      api: document.getElementById('nodeApi')
    };

    // State
    this.currentPhase = 1; // 1: Cold Start, 2: Cache Hit, 3: SWR, 4: Coalescing
    this.isPlaying = true;
    this.playbackSpeed = 1.0;
    this.phaseStep = 0;
    this.phaseTimer = null;

    this.initControls();
    this.drawStaticGuides();
    window.addEventListener('resize', () => this.drawStaticGuides());

    // Auto-start
    this.startPhase(1);
  }

  getNodePorts(element) {
    const stageRect = this.stage.getBoundingClientRect();
    const rect = element.getBoundingClientRect();
    const left = rect.left - stageRect.left;
    const top = rect.top - stageRect.top;
    const right = left + rect.width;
    const bottom = top + rect.height;
    const centerX = left + rect.width / 2;
    const centerY = top + rect.height / 2;

    return {
      center: { x: centerX, y: centerY },
      top: { x: centerX, y: top },
      bottom: { x: centerX, y: bottom },
      left: { x: left, y: centerY },
      right: { x: right, y: centerY },
      topRight: { x: right - 20, y: top },
      bottomLeft: { x: left + 20, y: bottom },
      bottomRight: { x: right - 20, y: bottom }
    };
  }

  getCurvedPath(p1, p2, curveOffset = 0) {
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    // Elegant cubic or quadratic curve based on delta
    const cx1 = p1.x + dx * 0.5;
    const cy1 = p1.y + curveOffset;
    const cx2 = p1.x + dx * 0.5;
    const cy2 = p2.y + curveOffset;
    return `M ${p1.x} ${p1.y} C ${cx1} ${cy1}, ${cx2} ${cy2}, ${p2.x} ${p2.y}`;
  }

  drawStaticGuides() {
    this.guideLinesGroup.innerHTML = '';
    const ui = this.getNodePorts(this.nodes.ui);
    const controller = this.getNodePorts(this.nodes.controller);
    const queue = this.getNodePorts(this.nodes.queue);
    const cache = this.getNodePorts(this.nodes.cache);
    const storage = this.getNodePorts(this.nodes.storage);
    const api = this.getNodePorts(this.nodes.api);

    // Explicit wire routes between edge ports
    const wires = [
      // 1. UI right -> Controller left
      { from: ui.right, to: controller.left, offset: 0, id: 'wire-ui-ctrl' },
      // 2. Controller right -> Queue left
      { from: controller.right, to: queue.left, offset: 0, id: 'wire-ctrl-queue' },
      // 3. Queue bottom -> API top (Network path)
      { from: queue.bottom, to: api.top, offset: 0, id: 'wire-queue-api' },
      // 4. Queue left-bottom -> Cache top-right (Cache check path)
      { from: { x: queue.left.x, y: queue.bottom.y - 30 }, to: cache.topRight, offset: 15, id: 'wire-queue-cache' },
      // 5. Cache top -> UI bottom (Fast lane 0ms return path!)
      { from: cache.top, to: ui.bottom, offset: 0, id: 'wire-cache-ui' },
      // 6. Queue bottom-left -> Storage top (Persistence path)
      { from: queue.bottomLeft, to: storage.top, offset: -10, id: 'wire-queue-storage' }
    ];

    wires.forEach(w => {
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', this.getCurvedPath(w.from, w.to, w.offset));
      path.setAttribute('class', 'guide-path');
      path.setAttribute('id', w.id);
      this.guideLinesGroup.appendChild(path);
    });
  }

  logTelemetry(eventText) {
    const now = new Date();
    const timeStr = `${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}.${String(Math.floor(now.getMilliseconds() / 10)).padStart(2, '0')}`;
    this.tickerEntry.innerHTML = `<span style="color:#6366f1;font-weight:600;">[${timeStr}]</span> ${eventText}`;
  }

  /**
   * Spawns an animated glowing particle along a path between two nodes
   */
  sendParticle(fromNode, toNode, color = '#6366f1', curveOffset = 0, durationMs = 600, callback = null, routeType = 'auto') {
    const pFrom = this.getNodePorts(fromNode);
    const pTo = this.getNodePorts(toNode);

    let start = pFrom.right;
    let end = pTo.left;

    if (fromNode === this.nodes.cache && toNode === this.nodes.ui) {
      // Fast lane UP
      start = pFrom.top;
      end = pTo.bottom;
    } else if (fromNode === this.nodes.queue && toNode === this.nodes.api) {
      // Down to API
      start = pFrom.bottom;
      end = pTo.top;
    } else if (fromNode === this.nodes.api && toNode === this.nodes.queue) {
      // Up from API
      start = pFrom.top;
      end = pTo.bottom;
    } else if (fromNode === this.nodes.queue && toNode === this.nodes.cache) {
      start = { x: pFrom.left.x, y: pFrom.bottom.y - 30 };
      end = pTo.topRight;
    } else if (fromNode === this.nodes.queue && toNode === this.nodes.ui) {
      start = pFrom.left;
      end = pTo.right;
    } else if (fromNode === this.nodes.api && toNode === this.nodes.cache) {
      start = pFrom.left;
      end = pTo.right;
    }

    const d = this.getCurvedPath(start, end, curveOffset);

    // Active stroke line with animation
    const activePath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    activePath.setAttribute('d', d);
    activePath.setAttribute('class', 'active-path');
    activePath.setAttribute('stroke', color);
    activePath.setAttribute('stroke-dasharray', '8 4');
    this.activePathsGroup.appendChild(activePath);

    // Glowing particle circle
    const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    circle.setAttribute('r', '6');
    circle.setAttribute('fill', '#ffffff');
    circle.setAttribute('stroke', color);
    circle.setAttribute('stroke-width', '2.5');
    circle.setAttribute('class', 'pulse-particle');
    this.particlesGroup.appendChild(circle);

    // Precalculate total path length for buttery smooth interpolation
    const pathElem = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    pathElem.setAttribute('d', d);
    const totalLength = pathElem.getTotalLength();

    const actualDuration = durationMs / this.playbackSpeed;
    const startTime = performance.now();

    const animate = (now) => {
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / actualDuration, 1);

      // Smooth easeInOut
      const ease = progress < 0.5 ? 2 * progress * progress : -1 + (4 - 2 * progress) * progress;
      const point = pathElem.getPointAtLength(ease * totalLength);

      circle.setAttribute('cx', point.x);
      circle.setAttribute('cy', point.y);

      if (progress < 1) {
        requestAnimationFrame(animate);
      } else {
        circle.remove();
        activePath.style.transition = 'opacity 0.25s ease';
        activePath.style.opacity = '0';
        setTimeout(() => activePath.remove(), 250);
        if (callback) callback();
      }
    };

    requestAnimationFrame(animate);
  }

  clearNodeStates() {
    Object.values(this.nodes).forEach(n => {
      n.classList.remove('active', 'hit', 'swr');
    });
  }

  // --- PHASE 1: Cold Start & Cache Miss ---
  runPhase1() {
    this.scenarioTitle.textContent = 'Phase 1: Cold Start & Cache Miss';
    this.stepBadge.textContent = 'Phase 1 / 4';
    this.logTelemetry('User requests profile: userProfile.get((id: 42))');

    // UI triggers request
    this.nodes.ui.classList.add('active');
    this.uiStatusPill.textContent = 'Requesting';
    this.widgetStateBadge.textContent = 'DataInitial()';
    this.widgetStateBadge.className = 'widget-badge';
    this.widgetName.textContent = 'Loading...';
    this.widgetName.classList.add('skeleton-loading');
    this.widgetRole.textContent = 'Please wait...';
    this.widgetRole.classList.add('skeleton-loading');

    this.sendParticle(this.nodes.ui, this.nodes.controller, '#6366f1', -15, 500, () => {
      this.nodes.controller.classList.add('active');
      this.controllerStatusPill.textContent = 'Dispatch';

      this.sendParticle(this.nodes.controller, this.nodes.queue, '#6366f1', 0, 500, () => {
        this.nodes.queue.classList.add('active');
        this.queueStatusPill.textContent = 'Checking Cache';
        this.queueInFlight.textContent = '1';

        // Check L1 Cache
        this.sendParticle(this.nodes.queue, this.nodes.cache, '#6366f1', -20, 450, () => {
          this.nodes.cache.classList.add('active');
          this.cacheStatusPill.textContent = 'MISS (Empty)';
          this.logTelemetry('CacheStore L1 MISS for key "user_profile:42"');

          // Transition UI to DataLoading
          this.widgetStateBadge.textContent = 'DataLoading()';
          this.widgetStateBadge.className = 'widget-badge loading';
          this.widgetLatency.textContent = '12ms';

          // Forward to Network API
          setTimeout(() => {
            this.logTelemetry('TrooperQueryQueue: In-flight request dispatched to REST API');
            this.sendParticle(this.nodes.queue, this.nodes.api, '#f43f5e', 0, 600, () => {
              this.nodes.api.classList.add('active');
              this.apiActivity.classList.add('active');
              this.apiStatusPill.textContent = 'Fetching 200';
              this.apiStatusText.textContent = '200 OK (320ms)';

              // API returns response
              setTimeout(() => {
                this.apiActivity.classList.remove('active');
                this.apiStatusPill.textContent = 'Idle';
                this.apiStatusText.textContent = 'Payload Delivered';

                this.sendParticle(this.nodes.api, this.nodes.queue, '#10b981', 0, 600, () => {
                  this.logTelemetry('Received HTTP 200 OK: Writing to L1 CacheStore & L2 Persistence');
                  this.queueInFlight.textContent = '0';

                  // Write L1 Cache & L2 Storage
                  this.nodes.cache.classList.remove('active');
                  this.nodes.cache.classList.add('hit');
                  this.cacheStatusPill.textContent = 'FRESH';
                  this.cacheFreshness.textContent = 'Status: Fresh';
                  this.cacheAge.textContent = 'Age: 0s';
                  this.ttlFill.style.width = '100%';
                  this.ttlFill.style.background = 'linear-gradient(90deg, #10b981, #06b6d4)';

                  this.nodes.storage.classList.add('active');
                  this.storageStatusPill.textContent = 'Saved';
                  this.storageCode.textContent = '{"version":1,"cachedAt":"2026-10-08T22:15:00Z","name":"Alice Vance"}';

                  // Emit DataLoaded to UI
                  this.sendParticle(this.nodes.queue, this.nodes.ui, '#10b981', -30, 650, () => {
                    this.clearNodeStates();
                    this.nodes.ui.classList.add('hit');
                    this.uiStatusPill.textContent = 'Loaded';
                    this.widgetName.classList.remove('skeleton-loading');
                    this.widgetName.textContent = 'Alice Vance';
                    this.widgetRole.classList.remove('skeleton-loading');
                    this.widgetRole.textContent = 'Staff Dart Architect';
                    this.widgetStateBadge.textContent = 'DataLoaded(User)';
                    this.widgetStateBadge.className = 'widget-badge loaded';
                    this.widgetLatency.textContent = '340ms (Cold)';
                    this.logTelemetry('StateTransition: Emitted DataLoaded<User> to UI. Cached in L1.');

                    this.scheduleNextPhase(2, 2800);
                  });
                });
              }, 400 / this.playbackSpeed);
            });
          }, 300 / this.playbackSpeed);
        });
      });
    });
  }

  // --- PHASE 2: Instant Cache Hit (0ms) ---
  runPhase2() {
    this.scenarioTitle.textContent = 'Phase 2: Instant Cache Hit (0ms Zero Network)';
    this.stepBadge.textContent = 'Phase 2 / 4';
    this.clearNodeStates();
    this.logTelemetry('Subsequent call: userProfile.get((id: 42))');

    this.nodes.ui.classList.add('active');
    this.uiStatusPill.textContent = 'Querying';

    this.sendParticle(this.nodes.ui, this.nodes.controller, '#6366f1', -15, 300, () => {
      this.sendParticle(this.nodes.controller, this.nodes.queue, '#6366f1', 0, 300, () => {
        // Query checks L1 Cache
        this.sendParticle(this.nodes.queue, this.nodes.cache, '#10b981', -20, 300, () => {
          this.nodes.cache.classList.add('hit');
          this.cacheStatusPill.textContent = '⚡ HIT (0ms)';
          this.logTelemetry('⚡ CacheStore L1 HIT! Fresh entry served directly from memory (0 Network Calls).');

          // Return immediately to UI
          this.sendParticle(this.nodes.cache, this.nodes.ui, '#10b981', -40, 450, () => {
            this.clearNodeStates();
            this.nodes.ui.classList.add('hit');
            this.uiStatusPill.textContent = 'Instant Read';
            this.widgetLatency.textContent = '⚡ 0ms (L1 Hit)';
            this.widgetStateBadge.textContent = 'DataLoaded(Cached)';
            this.widgetStateBadge.className = 'widget-badge loaded';

            this.scheduleNextPhase(3, 2600);
          });
        });
      });
    });
  }

  // --- PHASE 3: SWR Revalidation (Zero-Flicker Guarantee) ---
  runPhase3() {
    this.scenarioTitle.textContent = 'Phase 3: SWR Revalidation (Zero-Flicker Background Update)';
    this.stepBadge.textContent = 'Phase 3 / 4';
    this.clearNodeStates();
    this.logTelemetry('Simulating TTL Expiry: Cache entry becomes STALE');

    // Simulate TTL Expiry
    this.nodes.cache.classList.add('swr');
    this.cacheStatusPill.textContent = 'STALE';
    this.cacheFreshness.textContent = 'Status: Stale (TTL Expired)';
    this.cacheAge.textContent = 'Age: 5m 02s';
    this.ttlFill.style.width = '15%';
    this.ttlFill.style.background = '#f59e0b';

    setTimeout(() => {
      this.logTelemetry('Background Revalidation triggered by userProfile.get((id: 42))');
      this.nodes.ui.classList.add('swr');
      this.uiStatusPill.textContent = 'Revalidating';

      // SWR: UI IMMEDIATELY gets DataRefreshing while showing stale data!
      this.widgetStateBadge.textContent = 'DataRefreshing(User)';
      this.widgetStateBadge.className = 'widget-badge refreshing';
      this.widgetLatency.textContent = '0ms + Bg Fetch';
      this.logTelemetry('Zero-Flicker: DataRefreshing extends DataLoaded -> UI keeps rendered content!');

      // Background Fetch dispatched
      this.sendParticle(this.nodes.queue, this.nodes.api, '#f59e0b', 0, 700, () => {
        this.nodes.api.classList.add('active');
        this.apiActivity.classList.add('active');
        this.apiStatusPill.textContent = 'SWR Fetch';
        this.apiStatusText.textContent = 'Revalidating in Background';

        setTimeout(() => {
          this.apiActivity.classList.remove('active');
          this.apiStatusPill.textContent = 'Idle';
          this.apiStatusText.textContent = 'Delivered Fresh v2';

          this.sendParticle(this.nodes.api, this.nodes.cache, '#10b981', 15, 600, () => {
            // Cache refreshed
            this.nodes.cache.classList.remove('swr');
            this.nodes.cache.classList.add('hit');
            this.cacheStatusPill.textContent = 'FRESH v2';
            this.cacheFreshness.textContent = 'Status: Fresh';
            this.cacheAge.textContent = 'Age: 0s';
            this.ttlFill.style.width = '100%';
            this.ttlFill.style.background = 'linear-gradient(90deg, #10b981, #06b6d4)';

            // Silent UI update to fresh data
            this.sendParticle(this.nodes.cache, this.nodes.ui, '#10b981', -35, 600, () => {
              this.clearNodeStates();
              this.nodes.ui.classList.add('hit');
              this.uiStatusPill.textContent = 'Fresh';
              this.widgetRole.textContent = 'Principal Engineer & Dart Master';
              this.widgetStateBadge.textContent = 'DataLoaded(Fresh v2)';
              this.widgetStateBadge.className = 'widget-badge loaded';
              this.widgetLatency.textContent = 'Refreshed Silently';
              this.logTelemetry('Background fetch succeeded: UI updated seamlessly with zero layout shift!');

              this.scheduleNextPhase(4, 2800);
            });
          });
        }, 500 / this.playbackSpeed);
      });
    }, 800 / this.playbackSpeed);
  }

  // --- PHASE 4: Request Coalescing (Stampede Protection) ---
  runPhase4() {
    this.scenarioTitle.textContent = 'Phase 4: Concurrency Coalescing (Stampede Protection)';
    this.stepBadge.textContent = 'Phase 4 / 4';
    this.clearNodeStates();
    this.logTelemetry('Cache Stampede: 3 Components call userProfile.get((id: 42)) simultaneously!');

    this.nodes.ui.classList.add('active');
    this.uiStatusPill.textContent = '3 Concurrent Calls';

    // 3 Simultaneous particles from UI
    this.sendParticle(this.nodes.ui, this.nodes.controller, '#818cf8', -25, 400);
    this.sendParticle(this.nodes.ui, this.nodes.controller, '#a78bfa', -10, 420);
    this.sendParticle(this.nodes.ui, this.nodes.controller, '#c084fc', 5, 440, () => {
      this.nodes.controller.classList.add('active');

      this.sendParticle(this.nodes.controller, this.nodes.queue, '#818cf8', 0, 450, () => {
        this.nodes.queue.classList.add('active');
        this.queueStatusPill.textContent = 'COALESCED (3:1)';
        this.queueInFlight.textContent = '1';
        this.queueCallers.textContent = '3';
        this.logTelemetry('TrooperQueryQueue: Deduplicating 3 callers into 1 single in-flight Future!');

        // Only ONE single request flies to API!
        this.sendParticle(this.nodes.queue, this.nodes.api, '#f43f5e', 0, 650, () => {
          this.nodes.api.classList.add('active');
          this.apiActivity.classList.add('active');
          this.apiStatusPill.textContent = '1 Single Request';
          this.apiStatusText.textContent = 'Server sees only 1 hit!';

          setTimeout(() => {
            this.apiActivity.classList.remove('active');
            this.apiStatusPill.textContent = 'Idle';
            this.apiStatusText.textContent = 'Multicasting response';

            // Result returns to queue
            this.sendParticle(this.nodes.api, this.nodes.queue, '#10b981', 0, 500, () => {
              this.logTelemetry('Response received: Multicasting 1 result to all 3 waiting callers!');
              this.queueInFlight.textContent = '0';
              this.queueCallers.textContent = '0';

              // Multicast fan-out back to UI
              this.sendParticle(this.nodes.queue, this.nodes.ui, '#10b981', -35, 550);
              this.sendParticle(this.nodes.queue, this.nodes.ui, '#34d399', -20, 580);
              this.sendParticle(this.nodes.queue, this.nodes.ui, '#6ee7b7', -5, 610, () => {
                this.clearNodeStates();
                this.nodes.ui.classList.add('hit');
                this.uiStatusPill.textContent = 'All 3 Resolved';
                this.widgetStateBadge.textContent = 'Coalesced (Saved 66%)';
                this.widgetStateBadge.className = 'widget-badge loaded';
                this.widgetLatency.textContent = 'Stampede Averted';
                this.logTelemetry('All 3 callers satisfied with 1 network hit. 66% server load saved.');

                // Loop back to Phase 1
                this.scheduleNextPhase(1, 3200);
              });
            });
          }, 450 / this.playbackSpeed);
        });
      });
    });
  }

  scheduleNextPhase(phaseNumber, delayMs) {
    if (!this.isPlaying) return;
    this.phaseTimer = setTimeout(() => {
      this.startPhase(phaseNumber);
    }, delayMs / this.playbackSpeed);
  }

  startPhase(phaseNumber) {
    clearTimeout(this.phaseTimer);
    this.currentPhase = phaseNumber;

    switch (phaseNumber) {
      case 1:
        this.runPhase1();
        break;
      case 2:
        this.runPhase2();
        break;
      case 3:
        this.runPhase3();
        break;
      case 4:
        this.runPhase4();
        break;
    }
  }

  initControls() {
    const playPauseBtn = document.getElementById('playPauseBtn');
    const playIcon = document.getElementById('playIcon');
    const pauseIcon = document.getElementById('pauseIcon');
    const prevBtn = document.getElementById('prevBtn');
    const nextBtn = document.getElementById('nextBtn');
    const speedBtn = document.getElementById('speedBtn');
    const resetBtn = document.getElementById('resetBtn');

    playPauseBtn.addEventListener('click', () => {
      this.isPlaying = !this.isPlaying;
      if (this.isPlaying) {
        playIcon.classList.add('hidden');
        pauseIcon.classList.remove('hidden');
        this.startPhase(this.currentPhase);
      } else {
        playIcon.classList.remove('hidden');
        pauseIcon.classList.add('hidden');
        clearTimeout(this.phaseTimer);
      }
    });

    // Update play icon state initially
    playIcon.classList.add('hidden');
    pauseIcon.classList.remove('hidden');

    prevBtn.addEventListener('click', () => {
      const prev = this.currentPhase === 1 ? 4 : this.currentPhase - 1;
      this.startPhase(prev);
    });

    nextBtn.addEventListener('click', () => {
      const next = this.currentPhase === 4 ? 1 : this.currentPhase + 1;
      this.startPhase(next);
    });

    speedBtn.addEventListener('click', () => {
      if (this.playbackSpeed === 1.0) {
        this.playbackSpeed = 1.5;
        speedBtn.textContent = '1.5x';
      } else if (this.playbackSpeed === 1.5) {
        this.playbackSpeed = 2.0;
        speedBtn.textContent = '2.0x';
      } else {
        this.playbackSpeed = 1.0;
        speedBtn.textContent = '1.0x';
      }
    });

    resetBtn.addEventListener('click', () => {
      this.startPhase(1);
    });
  }
}

// Initialize on DOM load
window.addEventListener('DOMContentLoaded', () => {
  window.flowEngine = new FlowAnimationEngine();
});
