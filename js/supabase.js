/* ============================================================
 * 酒链 B2B —— 公共模块
 * 客户端初始化 + 工具函数 + 导航 + 弹层 + 状态标签
 *
 * 注意：客户端实例必须叫 sb，不能叫 supabase。
 * UMD 版 SDK 已经占用 window.supabase 这个全局名，
 * 再声明 supabase 会直接报：
 *   "Identifier 'supabase' has already been declared"
 * ============================================================ */
(function () {
  'use strict';

  var CONFIG = window.APP_CONFIG || {};
  var isConfigured = !!(
    CONFIG.SUPABASE_URL &&
    CONFIG.SUPABASE_URL.indexOf('YOUR_SUPABASE_PROJECT_URL') === -1 &&
    CONFIG.SUPABASE_ANON_KEY &&
    CONFIG.SUPABASE_ANON_KEY.indexOf('YOUR_SUPABASE_ANON_KEY') === -1
  );

  var sb = isConfigured
    ? window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY, {
        auth: { persistSession: true, autoRefreshToken: true },
      })
    : null;

  /* ---------------- 基础工具 ---------------- */

  function qs(name) {
    return new URLSearchParams(location.search).get(name);
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function fmtMoney(n) {
    var locale = (WineApp && WineApp.getLang && WineApp.getLang() === 'ru') ? 'ru-RU'
      : (WineApp && WineApp.getLang && WineApp.getLang() === 'en') ? 'en-US' : 'zh-CN';
    return '¥' + Number(n || 0).toLocaleString(locale, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  }

  function fmtDate(s) {
    if (!s) return '—';
    var d = new Date(s);
    if (isNaN(d.getTime())) return '—';
    if (WineApp && WineApp.getLang && WineApp.getLang() === 'zh') {
      var pad = function (x) { return String(x).padStart(2, '0'); };
      return (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    }
    var locale = (WineApp && WineApp.getLang && WineApp.getLang() === 'ru') ? 'ru-RU' : 'en-US';
    return d.toLocaleString(locale, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  /* ---------------- 提示 toast ---------------- */

  var toastTimer = null;
  function toast(msg, type) {
    var el = document.getElementById('toast');
    if (!el) return;
    el.textContent = msg;
    el.className = 'toast show ' + (type || 'info');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.classList.remove('show'); }, 2600);
  }

  /* ---------------- 底部弹层 ---------------- */

  function openSheet(id) {
    var el = document.getElementById(id);
    if (el) el.classList.add('open');
  }
  function closeSheet(id) {
    var el = document.getElementById(id);
    if (el) el.classList.remove('open');
  }
  document.addEventListener('click', function (e) {
    if (e.target && e.target.classList && e.target.classList.contains('sheet-mask')) {
      e.target.classList.remove('open');
    }
  });

  /* ---------------- 登录态 ---------------- */

  async function currentUser() {
    if (!sb) return null;
    try {
      var res = await sb.auth.getUser();
      return res && res.data && res.data.user ? res.data.user : null;
    } catch (e) {
      return null;
    }
  }

  var _profile = null;
  async function currentProfile(force) {
    if (_profile && !force) return _profile;
    var user = await currentUser();
    if (!user) { _profile = null; return null; }
    try {
      var res = await sb.from('profiles').select('*').eq('id', user.id).maybeSingle();
      if (res.data) { _profile = res.data; return res.data; }
    } catch (e) { /* 触发器未建时走元数据兜底 */ }
    // 兜底：用注册时写入 auth 的元数据
    var meta = user.user_metadata || {};
    _profile = {
      id: user.id,
      email: user.email,
      role: meta.role || 'buyer',
      company_name: meta.company_name || '',
      contact_name: meta.contact_name || '',
      phone: meta.phone || '',
      region: '',
      bio: '',
      created_at: null,
    };
    return _profile;
  }

  function redirectToLogin() {
    var here = location.pathname.split('/').pop() + location.search;
    location.href = 'login.html?redirect=' + encodeURIComponent(here);
  }

  async function requireAuth() {
    var user = await currentUser();
    if (!user) { redirectToLogin(); return null; }
    return user;
  }

  async function requireRole(role) {
    var user = await requireAuth();
    if (!user) return null;
    var p = await currentProfile();
    if (p.role !== role) {
      toast(p.role === 'supplier' ? WineApp.t('nav.roleErrSupplier') : WineApp.t('nav.roleErrBuyer'), 'error');
      setTimeout(function () {
        location.href = p.role === 'supplier' ? 'supplier-dashboard.html' : 'buyer-dashboard.html';
      }, 900);
      return null;
    }
    return p;
  }

  async function logout() {
    if (sb) { try { await sb.auth.signOut(); } catch (e) { /* 忽略 */ } }
    _profile = null;
    location.href = 'login.html';
  }

  // 重新发送注册验证邮件（Supabase 开启邮箱确认时，注册后需点邮件里的链接才能登录）
  async function resendConfirm(email) {
    if (!sb) return { error: { message: WineApp.t('common.notConfigured') } };
    if (!email) return { error: { message: WineApp.t('common.needEmail') } };
    try {
      return await sb.auth.resend({ type: 'signup', email: email });
    } catch (e) {
      return { error: { message: e && e.message ? e.message : String(e) } };
    }
  }

  // 判断错误信息是否属于「邮箱尚未验证」
  function isUnconfirmedError(err) {
    var m = (err && err.message) ? String(err.message) : '';
    return /not\s*confirmed|email\s*not\s*confirmed|confirm/i.test(m);
  }

  /* ---------------- 导航 ---------------- */

  async function initNav() {
    var cfgAlert = document.getElementById('configAlert');
    if (cfgAlert && !isConfigured) {
      cfgAlert.classList.remove('hidden');
    }
    if (!sb) return;

    var navUser = document.getElementById('navUser');
    var navLogin = document.getElementById('navLogin');
    var navLogout = document.getElementById('navLogout');
    var navDash = document.getElementById('navDash');

    var p = await currentProfile();
    if (!p) {
      if (navUser) navUser.textContent = WineApp.t('nav.guest');
      if (navLogin) navLogin.classList.remove('hidden');
      if (navLogout) navLogout.classList.add('hidden');
      if (navDash) navDash.classList.add('hidden');
      return;
    }
    if (navUser) {
      navUser.innerHTML =
        '<span class="nav-name">' + escapeHtml(p.company_name || p.email) + '</span>' +
        '<span class="role-badge role-' + escapeHtml(p.role) + '">' +
        WineApp.roleLabel(p.role) + '</span>';
    }
    if (navLogin) navLogin.classList.add('hidden');
    if (navLogout) navLogout.classList.remove('hidden');
    if (navDash) {
      navDash.classList.remove('hidden');
      navDash.href = p.role === 'supplier' ? 'supplier-dashboard.html' : 'buyer-dashboard.html';
    }
  }

  /* ---------------- 状态字典 ---------------- */

  var ORDER_STATUS = {
    pending_confirm: { label: '待确认', cls: 'chip-warn' },
    confirmed: { label: '已确认', cls: 'chip-info' },
    shipped: { label: '已发货', cls: 'chip-gold' },
    completed: { label: '已完成', cls: 'chip-ok' },
    cancelled: { label: '已取消', cls: 'chip-gray' },
  };
  var INQUIRY_STATUS = {
    pending: { label: '待回复', cls: 'chip-warn' },
    replied: { label: '已回复', cls: 'chip-ok' },
  };
  var WINE_TYPES = ['红葡萄酒', '白葡萄酒', '起泡酒', '桃红葡萄酒', 'OEM定制'];

  function orderChip(status) {
    var s = ORDER_STATUS[status] || { cls: 'chip-gray' };
    return '<span class="chip ' + s.cls + '">' + escapeHtml(WineApp.t('status.' + status)) + '</span>';
  }
  function inquiryChip(status) {
    var s = INQUIRY_STATUS[status] || { cls: 'chip-gray' };
    return '<span class="chip ' + s.cls + '">' + escapeHtml(WineApp.t('status.' + status)) + '</span>';
  }

  /* ---------------- 确认弹层（样式化 confirm，替代原生 confirm） ---------------- */

  function confirmSheet(opts) {
    opts = opts || {};
    var mask = document.getElementById('confirmMask');
    if (!mask) {
      mask = document.createElement('div');
      mask.id = 'confirmMask';
      mask.className = 'confirm-mask';
      mask.innerHTML =
        '<div class="confirm-card">' +
        '<div class="confirm-title"></div>' +
        '<div class="confirm-msg"></div>' +
        '<div class="confirm-actions">' +
        '<button type="button" class="btn btn-ghost btn-sm" data-act="cancel"></button>' +
        '<button type="button" class="btn btn-sm" data-act="ok"></button>' +
        '</div></div>';
      document.body.appendChild(mask);
      mask.addEventListener('click', function (e) {
        if (e.target === mask || (e.target.getAttribute && e.target.getAttribute('data-act') === 'cancel')) {
          closeConfirmSheet();
        } else if (e.target.getAttribute && e.target.getAttribute('data-act') === 'ok') {
          closeConfirmSheet();
          if (typeof opts.onOk === 'function') opts.onOk();
        }
      });
    }
    mask.querySelector('.confirm-title').textContent = opts.title || WineApp.t('common.confirm');
    mask.querySelector('.confirm-msg').textContent = opts.message || '';
    var okBtn = mask.querySelector('[data-act="ok"]');
    okBtn.textContent = opts.okText || WineApp.t('common.confirm');
    okBtn.className = 'btn btn-sm ' + (opts.danger ? 'btn-danger' : 'btn-primary');
    mask.querySelector('[data-act="cancel"]').textContent = opts.cancelText || WineApp.t('common.cancel');
    mask.classList.add('open');
  }

  function closeConfirmSheet() {
    var mask = document.getElementById('confirmMask');
    if (mask) mask.classList.remove('open');
  }

  /* ---------------- 导出 ---------------- */

  window.WineApp = {
    sb: sb,
    isConfigured: isConfigured,
    qs: qs,
    escapeHtml: escapeHtml,
    fmtMoney: fmtMoney,
    fmtDate: fmtDate,
    toast: toast,
    openSheet: openSheet,
    closeSheet: closeSheet,
    currentUser: currentUser,
    currentProfile: currentProfile,
    requireAuth: requireAuth,
    requireRole: requireRole,
    redirectToLogin: redirectToLogin,
    logout: logout,
    resendConfirm: resendConfirm,
    isUnconfirmedError: isUnconfirmedError,
    initNav: initNav,
    ORDER_STATUS: ORDER_STATUS,
    INQUIRY_STATUS: INQUIRY_STATUS,
    WINE_TYPES: WINE_TYPES,
    orderChip: orderChip,
    inquiryChip: inquiryChip,
    confirmSheet: confirmSheet,
    closeConfirmSheet: closeConfirmSheet,
  };
})();
