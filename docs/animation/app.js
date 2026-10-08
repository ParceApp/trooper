/**
 * Trooper Minimalist Flow Animation Engine
 * Clean Material 3 / Airbnb Design Standards
 */

class CleanFlowEngine {
  constructor() {
    this.chipIndicator = document.getElementById('chipIndicator');
    this.chipPhase = document.getElementById('chipPhase');
    this.chipLabel = document.getElementById('chipLabel');

    this.nodeUi = document.getElementById('nodeUi');
    this.nodeTrooper = document.getElementById('nodeTrooper');
    this.nodeApi = document.getElementById('nodeApi');

    this.uiStatusPill = document.getElementById('uiStatusPill');
    this.uiStatusCode = document.getElementById('uiStatusCode');

    this.cachePill = document.getElementById('cachePill');
    this.cacheStatusText = document.getElementById('cacheStatusText');

    this.networkPill = document.getElementById('networkPill');
    this.netStatusText = document.getElementById('netStatusText');

    this.badgeReq = document.getElementById('badgeReq');
    this.badgeState = document.getElementById('badgeState');
    this.badgeFetch = document.getElementById('badgeFetch');
    this.badgeResponse = document.getElementById('badgeResponse');

    this.pReq = document.getElementById('pReq');
    this.pState = document.getElementById('pState');
    this.pFetch = document.getElementById('pFetch');
    this.pResponse = document.getElementById('pResponse');

    this.startLoop();
  }

  resetCards() {
    this.nodeUi.className = 'node-card';
    this.nodeTrooper.className = 'node-card node-trooper';
    this.nodeApi.className = 'node-card';
  }

  animateParticle(particle, direction, color, durationMs, callback) {
    particle.style.background = color;
    particle.style.boxShadow = `0 0 8px ${color}`;
    particle.style.opacity = '1';
    particle.style.transition = 'none';

    if (direction === 'right') {
      particle.style.left = '0%';
    } else {
      particle.style.right = '0%';
    }

    // Force reflow
    particle.offsetHeight;

    particle.style.transition = `all ${durationMs}ms cubic-bezier(0.2, 0.0, 0, 1.0)`;
    if (direction === 'right') {
      particle.style.left = '94%';
    } else {
      particle.style.right = '94%';
    }

    setTimeout(() => {
      particle.style.opacity = '0';
      if (callback) callback();
    }, durationMs);
  }

  // --- PHASE 1: Cold Start (Cache Miss & Initial Fetch) ---
  runPhase1() {
    this.resetCards();
    this.chipPhase.textContent = 'Phase 1';
    this.chipLabel.textContent = 'Cold Request · Cache Miss';
    this.chipIndicator.style.background = '#6366f1';

    this.uiStatusCode.textContent = 'DataInitial()';
    this.uiStatusPill.className = 'status-pill';
    this.cacheStatusText.textContent = 'L1 Cache: Empty';
    this.netStatusText.textContent = 'Idle';
    this.networkPill.className = 'network-pill';

    setTimeout(() => {
      // 1. UI calls .get()
      this.nodeUi.classList.add('active');
      this.badgeReq.style.color = '#818cf8';
      this.animateParticle(this.pReq, 'right', '#6366f1', 450, () => {
        this.badgeReq.style.color = '';
        this.nodeTrooper.classList.add('active');
        this.cacheStatusText.textContent = 'L1 Cache: MISS';

        // 2. Trooper emits DataLoading() to UI
        this.badgeState.style.color = '#6366f1';
        this.animateParticle(this.pState, 'left', '#6366f1', 420, () => {
          this.badgeState.style.color = '';
          this.uiStatusCode.textContent = 'DataLoading()';
          this.uiStatusPill.className = 'status-pill loading';

          // 3. Trooper fetches from Remote API
          this.badgeFetch.style.color = '#f43f5e';
          this.animateParticle(this.pFetch, 'right', '#f43f5e', 480, () => {
            this.badgeFetch.style.color = '';
            this.nodeApi.classList.add('active');
            this.netStatusText.textContent = 'Fetching...';
            this.networkPill.className = 'network-pill fetching';

            // 4. Remote API delivers payload 200 OK
            setTimeout(() => {
              this.netStatusText.textContent = '200 OK (260ms)';
              this.badgeResponse.style.color = '#10b981';
              this.animateParticle(this.pResponse, 'left', '#10b981', 480, () => {
                this.badgeResponse.style.color = '';
                this.nodeApi.classList.remove('active');
                this.netStatusText.textContent = 'Idle';
                this.networkPill.className = 'network-pill';

                // 5. Trooper caches result & emits DataLoaded
                this.nodeTrooper.classList.remove('active');
                this.nodeTrooper.classList.add('hit');
                this.cacheStatusText.textContent = 'L1 Cache: FRESH (5m)';

                this.badgeState.style.color = '#10b981';
                this.animateParticle(this.pState, 'left', '#10b981', 460, () => {
                  this.badgeState.style.color = '';
                  this.nodeUi.classList.remove('active');
                  this.nodeUi.classList.add('hit');
                  this.uiStatusCode.textContent = 'DataLoaded(Data)';
                  this.uiStatusPill.className = 'status-pill loaded';

                  // Advance to Phase 2
                  setTimeout(() => this.runPhase2(), 2300);
                });
              });
            }, 350);
          });
        });
      });
    }, 400);
  }

  // --- PHASE 2: Instant Cache Hit (0ms) ---
  runPhase2() {
    this.resetCards();
    this.chipPhase.textContent = 'Phase 2';
    this.chipLabel.textContent = 'Subsequent Request · Instant L1 Cache Hit';
    this.chipIndicator.style.background = '#10b981';

    setTimeout(() => {
      // UI calls .get()
      this.nodeUi.classList.add('active');
      this.badgeReq.style.color = '#818cf8';
      this.animateParticle(this.pReq, 'right', '#6366f1', 340, () => {
        this.badgeReq.style.color = '';
        this.nodeTrooper.classList.add('hit');
        this.cacheStatusText.textContent = '⚡ HIT · Served in 0ms';

        // Instant return from memory (0 network calls)
        this.badgeState.style.color = '#10b981';
        this.animateParticle(this.pState, 'left', '#10b981', 340, () => {
          this.badgeState.style.color = '';
          this.uiStatusCode.textContent = 'DataLoaded(0ms)';
          this.uiStatusPill.className = 'status-pill loaded';

          // Advance to Phase 3
          setTimeout(() => this.runPhase3(), 2300);
        });
      });
    }, 400);
  }

  // --- PHASE 3: Zero-Flicker SWR Revalidation ---
  runPhase3() {
    this.resetCards();
    this.chipPhase.textContent = 'Phase 3';
    this.chipLabel.textContent = 'Stale-While-Revalidate · Zero-Flicker Update';
    this.chipIndicator.style.background = '#f59e0b';
    this.nodeTrooper.classList.add('swr');
    this.cacheStatusText.textContent = 'L1 Cache: STALE';

    setTimeout(() => {
      // UI calls .get()
      this.nodeUi.classList.add('active');
      this.badgeReq.style.color = '#818cf8';
      this.animateParticle(this.pReq, 'right', '#6366f1', 380, () => {
        this.badgeReq.style.color = '';

        // SWR: Instant DataRefreshing emitted while keeping UI loaded
        this.badgeState.style.color = '#f59e0b';
        this.animateParticle(this.pState, 'left', '#f59e0b', 380, () => {
          this.badgeState.style.color = '';
          this.uiStatusCode.textContent = 'DataRefreshing(Data)';
          this.uiStatusPill.className = 'status-pill refreshing';

          // Background Fetch dispatched
          this.badgeFetch.style.color = '#f59e0b';
          this.animateParticle(this.pFetch, 'right', '#f59e0b', 460, () => {
            this.badgeFetch.style.color = '';
            this.nodeApi.classList.add('active');
            this.netStatusText.textContent = 'SWR Fetch...';
            this.networkPill.className = 'network-pill fetching';

            setTimeout(() => {
              this.netStatusText.textContent = '200 OK (Fresh)';
              this.badgeResponse.style.color = '#10b981';
              this.animateParticle(this.pResponse, 'left', '#10b981', 460, () => {
                this.badgeResponse.style.color = '';
                this.nodeApi.classList.remove('active');
                this.netStatusText.textContent = 'Idle';
                this.networkPill.className = 'network-pill';

                // Cache updated
                this.nodeTrooper.classList.remove('swr');
                this.nodeTrooper.classList.add('hit');
                this.cacheStatusText.textContent = 'L1 Cache: FRESH v2';

                // Silent UI update to fresh data
                this.badgeState.style.color = '#10b981';
                this.animateParticle(this.pState, 'left', '#10b981', 420, () => {
                  this.badgeState.style.color = '';
                  this.uiStatusCode.textContent = 'DataLoaded(Fresh v2)';
                  this.uiStatusPill.className = 'status-pill loaded';

                  // Loop back to Phase 1
                  setTimeout(() => this.runPhase1(), 2600);
                });
              });
            }, 350);
          });
        });
      });
    }, 500);
  }

  startLoop() {
    this.runPhase1();
  }
}

window.addEventListener('DOMContentLoaded', () => {
  new CleanFlowEngine();
});
