(() => {
  const button = document.getElementById('language');
  let language = localStorage.getItem('shotskiff-language') || 'en';
  function apply() {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    document.querySelectorAll('[data-en][data-zh]').forEach(node => {
      node.innerHTML = node.dataset[language];
    });
    button.textContent = language === 'zh' ? 'EN' : '中文';
    button.setAttribute('aria-label', language === 'zh' ? 'Switch to English' : '切换到中文');
  }
  button.addEventListener('click', () => {
    language = language === 'en' ? 'zh' : 'en';
    localStorage.setItem('shotskiff-language', language);
    apply();
  });
  apply();
})();
