(function () {
  /* Mobile menu */
  var btn = document.getElementById('menuBtn');
  var nav = document.getElementById('mobileNav');
  if (btn && nav) {
    btn.addEventListener('click', function () { nav.classList.toggle('open'); });
  }

  /* Active nav link */
  var page = location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-link').forEach(function (a) {
    if (a.getAttribute('href') === page) a.classList.add('active');
  });

  /* Scroll-in animations */
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { e.target.classList.add('visible'); io.unobserve(e.target); }
    });
  }, { threshold: 0.12 });

  document.querySelectorAll(
    '.service-card,.industry-card,.language-tile,.testimonial-card,' +
    '.industry-full-card,.cert-card,.value-card,.team-card,.why-feature'
  ).forEach(function (el) { el.classList.add('fade-in'); io.observe(el); });

  /* Year */
  var y = document.getElementById('year');
  if (y) y.textContent = new Date().getFullYear();
})();
