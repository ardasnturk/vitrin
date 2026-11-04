// The page's small behaviours. Everything works with no JavaScript except the motion, and the motion stops under
// prefers-reduced-motion.
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const { copied = 'Copied', copyFallback = 'Press ⌘C' } = document.documentElement.dataset;

// Copy buttons
$$('.copy').forEach((button) => {
  button.addEventListener('click', async () => {
    const label = button.dataset.label ?? (button.dataset.label = button.textContent);
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.textContent = copied;
      button.classList.add('done');
      setTimeout(() => {
        button.textContent = label;
        button.classList.remove('done');
      }, 1600);
    } catch {
      button.textContent = copyFallback;
    }
  });
});

// The language menu remembers a choice, and closes when the click lands elsewhere.
const languages = document.querySelector('.lang');
languages?.addEventListener('click', (event) => {
  const link = event.target.closest('a');
  if (!link) return;
  try {
    localStorage.setItem('vitrin-language', link.hreflang);
  } catch {}
});
document.addEventListener('click', (event) => {
  if (languages && !languages.contains(event.target)) languages.open = false;
});

// Mobile menu
const menu = document.querySelector('.menu');
const links = document.getElementById('nav-links');
const setMenu = (open) => {
  links.classList.toggle('open', open);
  menu.setAttribute('aria-expanded', String(open));
};
menu.addEventListener('click', () => setMenu(!links.classList.contains('open')));
links.addEventListener('click', (event) => {
  if (event.target.closest('a')) setMenu(false);
});

// Sticky nav and reading progress
const nav = document.querySelector('.nav');
const progress = document.querySelector('.progress');
let ticking = false;
const onScroll = () => {
  ticking = false;
  const max = document.documentElement.scrollHeight - innerHeight;
  nav.classList.toggle('stuck', scrollY > 8);
  progress.style.setProperty('--p', max > 0 ? scrollY / max : 0);
  updateSteps();
};
addEventListener('scroll', () => {
  if (!ticking) {
    ticking = true;
    requestAnimationFrame(onScroll);
  }
}, { passive: true });

// Count up, once on screen
const countUp = (el) => {
  const target = Number(el.dataset.count);
  const format = (n) => (el.hasAttribute('data-sep') ? n.toLocaleString(document.documentElement.lang) : String(n));
  if (reduceMotion || target < 3) return;
  const started = performance.now();
  const frame = (now) => {
    const t = Math.min((now - started) / 1300, 1);
    el.textContent = format(Math.round(target * (1 - (1 - t) ** 4)));
    if (t < 1) requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
};

// Scroll reveal
const reveal = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    entry.target.classList.add('in');
    $$('[data-count]', entry.target).forEach(countUp);
    reveal.unobserve(entry.target);
  }
}, { threshold: 0.14, rootMargin: '0px 0px -6% 0px' });
$$('.term .ln').forEach((line, i) => line.style.setProperty('--l', i));
$$('.reveal').forEach((el) => reveal.observe(el));

// The hero window's tabs: they turn by themselves while it is on screen, until someone picks one.
const tabs = $$('.tabs [role="tab"]');
let heroVisible = false;
let heroAuto = !reduceMotion;
const selectTab = (tab, focus) => {
  for (const t of tabs) {
    const on = t === tab;
    t.setAttribute('aria-selected', String(on));
    t.tabIndex = on ? 0 : -1;
    document.getElementById(t.getAttribute('aria-controls')).hidden = !on;
  }
  // Only the tab strip scrolls: scrollIntoView would also move the page.
  const strip = tab.parentElement;
  strip.scrollTo({ left: tab.offsetLeft - strip.offsetLeft - 8, behavior: reduceMotion ? 'auto' : 'smooth' });
  if (focus) tab.focus();
};
tabs.forEach((tab, i) => {
  tab.addEventListener('click', () => {
    heroAuto = false;
    selectTab(tab, false);
  });
  tab.addEventListener('keydown', (event) => {
    const next = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    heroAuto = false;
    selectTab(tabs[(next + tabs.length) % tabs.length], true);
  });
});
const win = document.getElementById('win');
new IntersectionObserver(([entry]) => {
  heroVisible = entry.isIntersecting;
}, { threshold: 0.35 }).observe(win);
setInterval(() => {
  if (!heroAuto || !heroVisible || document.hidden) return;
  const i = tabs.findIndex((t) => t.getAttribute('aria-selected') === 'true');
  selectTab(tabs[(i + 1) % tabs.length], false);
}, 3400);

// The hero window leans a little toward the pointer
if (!reduceMotion && window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
  const hero = document.querySelector('.hero');
  hero.addEventListener('pointermove', (event) => {
    const box = win.getBoundingClientRect();
    const x = (event.clientX - box.left - box.width / 2) / box.width;
    const y = (event.clientY - box.top - box.height / 2) / box.height;
    win.style.setProperty('--ry', `${(x * 4).toFixed(2)}deg`);
    win.style.setProperty('--rx', `${(y * -3).toFixed(2)}deg`);
  });
  hero.addEventListener('pointerleave', () => {
    win.style.setProperty('--ry', '0deg');
    win.style.setProperty('--rx', '0deg');
  });

  // The light that follows the pointer over the Mac app's tiles
  $$('.tile').forEach((tile) => {
    tile.addEventListener('pointermove', (event) => {
      const box = tile.getBoundingClientRect();
      tile.style.setProperty('--mx', `${event.clientX - box.left}px`);
      tile.style.setProperty('--my', `${event.clientY - box.top}px`);
    });
  });
}

// The four steps: the one in the middle of the screen lights up and its scene shows beside it. On a narrow screen
// each scene moves under its own step.
const steps = $$('.step');
const panels = $$('.panel');
const box = document.querySelector('.scene-box');
const list = document.querySelector('.steps');
const narrow = window.matchMedia('(max-width: 1020px)');
function placePanels() {
  panels.forEach((panel, i) => {
    if (narrow.matches) {
      panel.classList.add('static', 'on');
      steps[i].append(panel);
    } else {
      panel.classList.remove('static');
      box.append(panel);
    }
  });
  updateSteps();
}
function updateSteps() {
  if (narrow.matches) return;
  const middle = innerHeight * 0.5;
  let active = 0;
  steps.forEach((step, i) => {
    if (step.getBoundingClientRect().top < middle) active = i;
  });
  steps.forEach((step, i) => step.classList.toggle('on', i === active));
  panels.forEach((panel, i) => panel.classList.toggle('on', i === active));
  list.style.setProperty('--done', active / (steps.length - 1));
}
narrow.addEventListener('change', placePanels);
placePanels();

// Style switcher: the shots fade out, change and fade back in.
const fan = document.getElementById('fan');
const styleTabs = $$('.switch [role="tab"]');
const fanImages = $$('img', fan);
const pickStyle = (tab, focus) => {
  for (const t of styleTabs) {
    const on = t === tab;
    t.setAttribute('aria-selected', String(on));
    t.tabIndex = on ? 0 : -1;
  }
  fan.classList.add('swap');
  setTimeout(() => {
    fanImages.forEach((img) => {
      // Relative to the page, which may sit in a language folder.
      img.src = img.getAttribute('src').replace(/[a-z]+-shot-/, `${tab.dataset.style}-shot-`);
    });
    fan.classList.remove('swap');
  }, reduceMotion ? 0 : 280);
  if (focus) tab.focus();
};
styleTabs.forEach((tab, i) => {
  tab.addEventListener('click', () => pickStyle(tab, false));
  tab.addEventListener('keydown', (event) => {
    const next = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: styleTabs.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    pickStyle(styleTabs[(next + styleTabs.length) % styleTabs.length], true);
  });
});

// The App Preview samples play only while they are on screen, and never under reduced motion.
if (reduceMotion) {
  $$('video').forEach((video) => {
    video.controls = true;
  });
} else {
  const videos = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) entry.target.play().catch(() => {});
      else entry.target.pause();
    }
  }, { threshold: 0.35 });
  $$('video[data-autoplay]').forEach((video) => videos.observe(video));
}

onScroll();
