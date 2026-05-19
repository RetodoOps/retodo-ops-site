(function () {

  /* ── Mobile menu ─────────────────────────────────────────── */
  var menuBtn = document.getElementById('menuBtn');
  var mobileNav = document.getElementById('mobileNav');
  if (menuBtn && mobileNav) {
    menuBtn.addEventListener('click', function () { mobileNav.classList.toggle('open'); });
  }

  /* ── Active nav link ─────────────────────────────────────── */
  var page = location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-link').forEach(function (a) {
    if (a.getAttribute('href') === page) a.classList.add('active');
  });

  /* ── Navbar scroll shadow ────────────────────────────────── */
  var navbar = document.querySelector('.navbar');
  if (navbar) {
    window.addEventListener('scroll', function () {
      navbar.classList.toggle('scrolled', window.scrollY > 10);
    }, { passive: true });
  }

  /* ── Year ────────────────────────────────────────────────── */
  var y = document.getElementById('year');
  if (y) y.textContent = new Date().getFullYear();

  /* ── Cookie consent ──────────────────────────────────────── */
  var cookieBanner = document.getElementById('cookieBanner');
  if (cookieBanner) {
    if (!localStorage.getItem('cookieConsent')) {
      cookieBanner.classList.remove('hidden');
    } else {
      cookieBanner.classList.add('hidden');
    }
    var acceptBtn  = document.getElementById('cookieAccept');
    var declineBtn = document.getElementById('cookieDecline');
    if (acceptBtn)  acceptBtn.addEventListener('click',  function () { localStorage.setItem('cookieConsent', 'accepted'); cookieBanner.classList.add('hidden'); });
    if (declineBtn) declineBtn.addEventListener('click', function () { localStorage.setItem('cookieConsent', 'declined'); cookieBanner.classList.add('hidden'); });
  }

  /* ── Logo strip marquee — duplicate for seamless loop ───── */
  var strip = document.querySelector('.clients-strip');
  if (strip) {
    strip.innerHTML += strip.innerHTML; /* duplicate for seamless loop */
  }

  /* ── IntersectionObserver factory ───────────────────────── */
  function makeObserver(cb, opts) {
    return new IntersectionObserver(cb, opts || { threshold: 0.15 });
  }

  /* ── Stagger grid animations ─────────────────────────────── */
  document.querySelectorAll(
    '.services-grid,.industries-grid,.languages-grid,' +
    '.why-features,.why-certs,.team-grid,.certs-grid,.values-grid,' +
    '.testimonials-grid,.agency-cards,.industry-full-grid'
  ).forEach(function (grid) {
    grid.classList.add('stagger');
    var children = Array.from(grid.children);
    var obs = makeObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          children.forEach(function (child) { child.classList.add('visible'); });
          obs.disconnect();
        }
      });
    }, { threshold: 0.08 });
    obs.observe(grid);
  });

  /* ── Legacy fade-in (non-grid items) ─────────────────────── */
  var fadeObs = makeObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { e.target.classList.add('visible'); fadeObs.unobserve(e.target); }
    });
  });
  document.querySelectorAll(
    '.language-full-section,.service-detail,.process-step,.agency-card'
  ).forEach(function (el) { el.classList.add('fade-in'); fadeObs.observe(el); });

  /* ── Stats count-up ──────────────────────────────────────── */
  var statsBar = document.querySelector('.stats-bar');
  if (statsBar) {
    var statsDone = false;
    var statsObs = makeObserver(function (entries) {
      if (entries[0].isIntersecting && !statsDone) {
        statsDone = true;
        statsObs.disconnect();
        statsBar.querySelectorAll('.stat-item').forEach(function (item, i) {
          item.classList.add('counted');
          var numEl = item.querySelector('.stat-number');
          if (!numEl) return;
          var raw = numEl.textContent.trim();
          var numeric = parseFloat(raw.replace(/[^0-9.]/g, ''));
          if (!isNaN(numeric) && numeric > 0 && numeric < 100000) {
            var suffix = raw.replace(/[0-9.,]/g, '');
            var duration = 1200;
            var start = performance.now();
            var from = 0;
            (function tick(now) {
              var pct = Math.min((now - start) / duration, 1);
              var ease = 1 - Math.pow(1 - pct, 3);
              var val = from + (numeric - from) * ease;
              numEl.textContent = (Number.isInteger(numeric) ? Math.round(val) : val.toFixed(1)) + suffix;
              if (pct < 1) requestAnimationFrame(tick);
            })(start);
          }
        });
      }
    }, { threshold: 0.4 });
    statsObs.observe(statsBar);
  }

  /* ── Process line draw on scroll ────────────────────────── */
  var procGrid = document.querySelector('.process-grid');
  if (procGrid) {
    var procObs = makeObserver(function (entries) {
      if (entries[0].isIntersecting) {
        procGrid.classList.add('line-ready');
        procObs.disconnect();
      }
    }, { threshold: 0.3 });
    procObs.observe(procGrid);
  }

  /* ── GitHub code block typewriter ────────────────────────── */
  var codeBody = document.querySelector('.code-body');
  if (codeBody) {
    var originalText = codeBody.textContent;
    codeBody.textContent = '';
    var cursor = document.createElement('span');
    cursor.className = 'type-cursor';
    codeBody.appendChild(cursor);
    var typed = false;

    var codeObs = makeObserver(function (entries) {
      if (entries[0].isIntersecting && !typed) {
        typed = true;
        codeObs.disconnect();
        var i = 0;
        var speed = 18; /* ms per character */
        (function type() {
          if (i < originalText.length) {
            codeBody.insertBefore(document.createTextNode(originalText[i]), cursor);
            i++;
            setTimeout(type, speed);
          }
        })();
      }
    }, { threshold: 0.5 });
    codeObs.observe(codeBody);
  }

})();
