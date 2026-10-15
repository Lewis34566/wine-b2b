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
    return '¥' + Number(n || 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  }

  function fmtDate(s) {
    if (!s) return '—';
    var d = new Date(s);
    var pad = function (x) { return String(x).padStart(2, '0'); };
    return (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
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
      toast(p.role === 'supplier' ? '当前账号是供应商，请使用供应商后台' : '当前账号是采购商，请使用采购商后台', 'error');
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
    if (!sb) return { error: { message: '未配置 Supabase 密钥' } };
    if (!email) return { error: { message: '缺少邮箱地址' } };
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
      if (navUser) navUser.textContent = '未登录';
      if (navLogin) navLogin.classList.remove('hidden');
      if (navLogout) navLogout.classList.add('hidden');
      if (navDash) navDash.classList.add('hidden');
      return;
    }
    if (navUser) {
      navUser.innerHTML =
        '<span class="nav-name">' + escapeHtml(p.company_name || p.email) + '</span>' +
        '<span class="role-badge role-' + escapeHtml(p.role) + '">' +
        (p.role === 'supplier' ? '供应商' : '采购商') + '</span>';
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
    var s = ORDER_STATUS[status] || { label: status, cls: 'chip-gray' };
    return '<span class="chip ' + s.cls + '">' + s.label + '</span>';
  }
  function inquiryChip(status) {
    var s = INQUIRY_STATUS[status] || { label: status, cls: 'chip-gray' };
    return '<span class="chip ' + s.cls + '">' + s.label + '</span>';
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
  };
})();
