/**
 * Trooper Minimalist Flow Animation
 * 3 Core Blocks: Flutter UI <---> Trooper (SWR Cache) <---> Remote API
 */

class MinimalFlowEngine {
  constructor() {
    this.statusText = document.getElementById('statusText');
    this.cardUi = document.getElementById('cardUi');
    this.cardTrooper = document.getElementById('cardTrooper');
    this.cardApi = document.getElementById('cardApi');

    this.uiStatePill = document.getElementById('uiStatePill');
    this.uiStateText = document.getElementById('uiStateText');

    this.trooperPill = document.getElementById('trooperPill');
    this.trooperPillText = document.getElementById('trooperPillText');

    this.apiPill = document.getElementById('apiPill');
    this.apiPillText = document.getElementById('apiPillText');

    // Labels
    this.labelReq = document.getElementById('labelReq');
    this.labelState = document.getElementById('labelState');
    this.labelFetch = document.getElementById('labelFetch');
    this.labelPayload = document.getElementById('labelPayload');

    // Particles
    this.pReq = document.getElementById('pReq');
    this.pState = document.getElementById('pState');
    this.pFetch = document.getElementById('pFetch');
    this.pPayload = document.getElementById('pPayload');

    this.startLoop();
  }

  resetCards() {
    this.cardUi.className = 'card card-ui';
    this.cardTrooper.className = 'card card-trooper';
    this.cardApi.className = 'card card-api';
  }

  animateParticle(particle, direction, color, durationMs, callback) {
    particle.style.background = color;
    particle.style.boxShadow = `0 0 10px ${color}`;
    particle.style.opacity = '1';
    particle.style.transition = 'none';

    if (direction === 'right') {
      particle.style.left = '0%';
    } else {
      particle.style.right = '0%';
    }

    // Force reflow
    particle.offsetHeight;

    particle.style.transition = `all ${durationMs}ms cubic-bezier(0.4, 0, 0.2, 1)`;
    if (direction === 'right') {
      particle.style.left = '92%';
    } else {
      particle.style.right = '92%';
    }

    setTimeout(() => {
      particle.style.opacity = '0';
      if (callback) callback();
    }, durationMs);
  }

  // --- PHASE 1: Cold Request & Cache Miss ---
  runPhase1() {
    this.resetCards();
    this.statusText.textContent = '1. Cold Start: Cache Miss & Initial Fetch';
    this.uiStateText.textContent = 'DataInitial()';
    this.uiStatePill.className = 'state-pill';
    this.trooperPillText.textContent = 'L1 Memory: Empty';
    this.apiPillText.textContent = 'Idle';
    this.apiPill.className = 'api-pill';

    // Step 1: UI calls .get()
    setTimeout(() => {
      this.cardUi.classList.add('active');
      this.labelReq.style.color = '#818cf8';
      this.animateParticle(this.pReq, 'right', '#6366f1', 500, () => {
        this.labelReq.style.color = '';
        this.cardTrooper.classList.add('active');
        this.trooperPillText.textContent = 'L1 Cache: MISS';

        // Step 2: Trooper emits DataLoading() to UI
        this.labelState.style.color = '#3b82f6';
        this.animateParticle(this.pState, 'left', '#3b82f6', 450, () => {
          this.labelState.style.color = '';
          this.uiStateText.textContent = 'DataLoading()';
          this.uiStatePill.className = 'state-pill loading';

          // Step 3: Trooper fetches from Remote API
          this.labelFetch.style.color = '#f43f5e';
          this.animateParticle(this.pFetch, 'right', '#f43f5e', 500, () => {
            this.labelFetch.style.color = '';
            this.cardApi.classList.add('active');
            this.apiPillText.textContent = 'Fetching...';
            this.apiPill.className = 'api-pill fetching';

            // Step 4: API returns 200 OK
            setTimeout(() => {
              this.apiPillText.textContent = '200 OK (280ms)';
              this.labelPayload.style.color = '#10b981';
              this.animateParticle(this.pPayload, 'left', '#10b981', 500, () => {
                this.labelPayload.style.color = '';
                this.cardApi.classList.remove('active');
                this.apiPillText.textContent = 'Idle';
                this.apiPill.className = 'api-pill';

                // Step 5: Trooper saves to cache and emits DataLoaded()
                this.cardTrooper.classList.remove('active');
                this.cardTrooper.classList.add('hit');
                this.trooperPillText.textContent = 'L1 Cache: FRESH (TTL 5m)';

                this.labelState.style.color = '#10b981';
                this.animateParticle(this.pState, 'left', '#10b981', 500, () => {
                  this.labelState.style.color = '';
                  this.cardUi.classList.remove('active');
                  this.cardUi.classList.add('active');
                  this.uiStateText.textContent = 'DataLoaded(Data)';
                  this.uiStatePill.className = 'state-pill loaded';

                  // Move to Phase 2
                  setTimeout(() => this.runPhase2(), 2200);
                });
              });
            }, 400);
          });
        });
      });
    }, 400);
  }

  // --- PHASE 2: Instant Cache Hit (0ms) ---
  runPhase2() {
    this.resetCards();
    this.statusText.textContent = '2. Subsequent Request: Instant L1 Cache Hit (0ms)';

    setTimeout(() => {
      // UI calls .get()
      this.cardUi.classList.add('active');
      this.labelReq.style.color = '#818cf8';
      this.animateParticle(this.pReq, 'right', '#6366f1', 350, () => {
        this.labelReq.style.color = '';
        this.cardTrooper.classList.add('hit');
        this.trooperPillText.textContent = '⚡ HIT! Served in 0ms';

        // Trooper immediately returns DataLoaded (0 Network calls!)
        this.labelState.style.color = '#10b981';
        this.animateParticle(this.pState, 'left', '#10b981', 350, () => {
          this.labelState.style.color = '';
          this.uiStateText.textContent = 'DataLoaded (⚡ 0ms)';
          this.uiStatePill.className = 'state-pill loaded';

          // Move to Phase 3
          setTimeout(() => this.runPhase3(), 2200);
        });
      });
    }, 400);
  }

  // --- PHASE 3: Zero-Flicker SWR Revalidation ---
  runPhase3() {
    this.resetCards();
    this.statusText.textContent = '3. Stale-While-Revalidate: Zero-Flicker Background Update';
    this.cardTrooper.classList.add('swr');
    this.trooperPillText.textContent = 'L1 Cache: STALE (TTL Expired)';

    setTimeout(() => {
      // UI calls .get()
      this.cardUi.classList.add('active');
      this.labelReq.style.color = '#818cf8';
      this.animateParticle(this.pReq, 'right', '#6366f1', 400, () => {
        this.labelReq.style.color = '';

        // SWR Magic: Trooper IMMEDIATELY returns DataRefreshing to UI!
        // UI stays loaded, showing existing data without full-page spinner!
        this.labelState.style.color = '#f59e0b';
        this.animateParticle(this.pState, 'left', '#f59e0b', 400, () => {
          this.labelState.style.color = '';
          this.uiStateText.textContent = 'DataRefreshing(Data)';
          this.uiStatePill.className = 'state-pill refreshing';

          // Background Fetch sent to API
          this.labelFetch.style.color = '#f59e0b';
          this.animateParticle(this.pFetch, 'right', '#f59e0b', 500, () => {
            this.labelFetch.style.color = '';
            this.cardApi.classList.add('active');
            this.apiPillText.textContent = 'SWR Fetch...';
            this.apiPill.className = 'api-pill fetching';

            setTimeout(() => {
              this.apiPillText.textContent = '200 OK (Fresh)';
              this.labelPayload.style.color = '#10b981';
              this.animateParticle(this.pPayload, 'left', '#10b981', 500, () => {
                this.labelPayload.style.color = '';
                this.cardApi.classList.remove('active');
                this.apiPillText.textContent = 'Idle';
                this.apiPill.className = 'api-pill';

                // L1 Cache updated
                this.cardTrooper.classList.remove('swr');
                this.cardTrooper.classList.add('hit');
                this.trooperPillText.textContent = 'L1 Cache: FRESH v2';

                // Silent UI update to fresh DataLoaded
                this.labelState.style.color = '#10b981';
                this.animateParticle(this.pState, 'left', '#10b981', 450, () => {
                  this.labelState.style.color = '';
                  this.uiStateText.textContent = 'DataLoaded(Fresh v2)';
                  this.uiStatePill.className = 'state-pill loaded';

                  // Loop back to Phase 1
                  setTimeout(() => this.runPhase1(), 2600);
                });
              });
            }, 400);
          });
        });
      });
    }, 600);
  }

  startLoop() {
    this.runPhase1();
  }
}

window.addEventListener('DOMContentLoaded', () => {
  new MinimalFlowEngine();
});
