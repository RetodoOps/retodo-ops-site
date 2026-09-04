(() => {
  const fallbackLanguageCodes = Object.freeze({
    'English':'EN','English (US)':'EN-US','English (UK)':'EN-GB','Bulgarian':'BG',
    'Swedish':'SV','Danish':'DA','Finnish':'FI','Norwegian':'NO',
    'Norwegian (Bokmål)':'NB','Norwegian (Nynorsk)':'NN','Icelandic':'IS',
    'German':'DE','French':'FR','Spanish':'ES','Italian':'IT','Dutch':'NL',
    'Polish':'PL','Portuguese':'PT','Portuguese (Brazil)':'PT-BR',
    'Portuguese (Portugal)':'PT-PT','Russian':'RU','Ukrainian':'UK',
    'Czech':'CS','Slovak':'SK','Hungarian':'HU','Romanian':'RO','Greek':'EL',
    'Turkish':'TR','Estonian':'ET','Latvian':'LV','Lithuanian':'LT','Slovenian':'SL',
    'Croatian':'HR','Serbian':'SR','Bosnian':'BS','Macedonian':'MK','Albanian':'SQ',
    'Chinese (Simplified)':'ZH-CN','Chinese (Traditional)':'ZH-TW','Japanese':'JA',
    'Korean':'KO','Arabic':'AR','Hebrew':'HE','Hindi':'HI','Thai':'TH',
    'Vietnamese':'VI','Indonesian':'ID','Malay':'MS'
  });
  let languageCodes = {...fallbackLanguageCodes};
  let languages = Object.keys(languageCodes);
  let languageLoadPromise = null;
  const countries = `Afghanistan|Albania|Algeria|Andorra|Angola|Antigua and Barbuda|Argentina|Armenia|Australia|Austria|Azerbaijan|Bahamas|Bahrain|Bangladesh|Barbados|Belarus|Belgium|Belize|Benin|Bhutan|Bolivia|Bosnia and Herzegovina|Botswana|Brazil|Brunei|Bulgaria|Burkina Faso|Burundi|Cabo Verde|Cambodia|Cameroon|Canada|Central African Republic|Chad|Chile|China|Colombia|Comoros|Congo|Costa Rica|Côte d’Ivoire|Croatia|Cuba|Cyprus|Czechia|Democratic Republic of the Congo|Denmark|Djibouti|Dominica|Dominican Republic|Ecuador|Egypt|El Salvador|Equatorial Guinea|Eritrea|Estonia|Eswatini|Ethiopia|Fiji|Finland|France|Gabon|Gambia|Georgia|Germany|Ghana|Greece|Grenada|Guatemala|Guinea|Guinea-Bissau|Guyana|Haiti|Honduras|Hungary|Iceland|India|Indonesia|Iran|Iraq|Ireland|Israel|Italy|Jamaica|Japan|Jordan|Kazakhstan|Kenya|Kiribati|Kosovo|Kuwait|Kyrgyzstan|Laos|Latvia|Lebanon|Lesotho|Liberia|Libya|Liechtenstein|Lithuania|Luxembourg|Madagascar|Malawi|Malaysia|Maldives|Mali|Malta|Marshall Islands|Mauritania|Mauritius|Mexico|Micronesia|Moldova|Monaco|Mongolia|Montenegro|Morocco|Mozambique|Myanmar|Namibia|Nauru|Nepal|Netherlands|New Zealand|Nicaragua|Niger|Nigeria|North Korea|North Macedonia|Norway|Oman|Pakistan|Palau|Palestine|Panama|Papua New Guinea|Paraguay|Peru|Philippines|Poland|Portugal|Qatar|Romania|Russia|Rwanda|Saint Kitts and Nevis|Saint Lucia|Saint Vincent and the Grenadines|Samoa|San Marino|São Tomé and Príncipe|Saudi Arabia|Senegal|Serbia|Seychelles|Sierra Leone|Singapore|Slovakia|Slovenia|Solomon Islands|Somalia|South Africa|South Korea|South Sudan|Spain|Sri Lanka|Sudan|Suriname|Sweden|Switzerland|Syria|Taiwan|Tajikistan|Tanzania|Thailand|Timor-Leste|Togo|Tonga|Trinidad and Tobago|Tunisia|Türkiye|Turkmenistan|Tuvalu|Uganda|Ukraine|United Arab Emirates|United Kingdom|United States|Uruguay|Uzbekistan|Vanuatu|Vatican City|Venezuela|Vietnam|Yemen|Zambia|Zimbabwe`.split('|');
  const commonNationalities = `Afghan|Albanian|Algerian|American|Argentinian|Armenian|Australian|Austrian|Azerbaijani|Bangladeshi|Belarusian|Belgian|Bosnian|Brazilian|British|Bulgarian|Canadian|Chilean|Chinese|Colombian|Croatian|Cypriot|Czech|Danish|Dutch|Egyptian|Estonian|Finnish|French|Georgian|German|Greek|Hungarian|Icelandic|Indian|Indonesian|Irish|Israeli|Italian|Japanese|Kazakh|Korean|Latvian|Lithuanian|Luxembourgish|Macedonian|Malaysian|Maltese|Mexican|Moldovan|Montenegrin|Moroccan|New Zealander|Nigerian|Norwegian|Pakistani|Polish|Portuguese|Romanian|Russian|Serbian|Singaporean|Slovak|Slovenian|South African|Spanish|Swedish|Swiss|Taiwanese|Thai|Turkish|Ukrainian|Vietnamese`.split('|');
  const fallbackServices = Object.freeze([
    'Translation', 'MTPE', 'Proofreading', 'Independent Review', 'LQA',
    'Terminology', 'DTP', 'Transcription', 'Subtitling', 'Voice-over',
    'Transcreation', 'Project Management', 'Other'
  ]);
  let services = [...fallbackServices];
  let serviceLoadPromise = null;

  const escapeOption = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;')
    .replaceAll('>','&gt;').replaceAll('"','&quot;');

  function installSettingsNav() {
    const nav = document.querySelector('.sidebar .nav');
    if (!nav) return;
    const existing = [...nav.querySelectorAll('a.nav-item')].filter(link => {
      try { return new URL(link.href, location.href).pathname.endsWith('/settings.html'); }
      catch (_) { return false; }
    });
    if (existing.length) {
      existing.slice(1).forEach(link => link.remove());
      return;
    }
    const link = document.createElement('a');
    link.className = `nav-item${location.pathname.endsWith('/settings.html') ? ' active' : ''}`;
    link.href = 'settings.html';
    link.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M19.43 12.98c.04-.32.07-.65.07-.98s-.03-.66-.08-.98l2.11-1.65-2-3.46-2.49 1a7.2 7.2 0 0 0-1.69-.98L15 3.27h-4l-.38 2.66c-.61.25-1.17.59-1.69.98l-2.49-1-2 3.46 2.11 1.65c-.04.32-.08.66-.08.98s.03.66.08.98l-2.11 1.65 2 3.46 2.49-1c.52.4 1.08.73 1.69.98L11 20.73h4l.38-2.66c.61-.25 1.17-.58 1.69-.98l2.49 1 2-3.46-2.13-1.65zM13 15.5A3.5 3.5 0 1 1 13 8a3.5 3.5 0 0 1 0 7.5z"/></svg>Settings';
    const divider = nav.querySelector('.nav-divider');
    if (divider) divider.before(link); else nav.appendChild(link);
  }

  function installDatalist(id, values) {
    let list = document.getElementById(id);
    if (!list) {
      list = document.createElement('datalist');
      list.id = id;
      document.body.appendChild(list);
    }
    list.innerHTML = [...new Set(values)].sort((a, b) => a.localeCompare(b, 'en'))
      .map(value => `<option value="${String(value).replaceAll('&','&amp;').replaceAll('"','&quot;')}"></option>`).join('');
  }

  window.TMS_REF = Object.freeze({
    get languages() { return Object.freeze([...languages]); },
    get languageCodes() { return Object.freeze({...languageCodes}); },
    async loadLanguages(supabase) {
      if (!supabase) return [...languages];
      if (!languageLoadPromise) languageLoadPromise = (async () => {
        const { data, error } = await supabase.from('language_catalog')
          .select('name,code,sort_order').eq('active', true).order('sort_order').order('name');
        if (!error && data?.length) {
          languages = data.map(row => row.name);
          languageCodes = Object.fromEntries(data.map(row => [row.name, row.code]));
        }
        return [...languages];
      })();
      return languageLoadPromise;
    },
    get services() { return Object.freeze([...services]); },
    async loadServices(supabase) {
      if (!supabase) return [...services];
      if (!serviceLoadPromise) serviceLoadPromise = (async () => {
        const { data, error } = await supabase.from('service_catalog')
          .select('name,sort_order').eq('active', true).order('sort_order').order('name');
        if (!error && data?.length) services = data.map(row => row.name);
        return [...services];
      })();
      return serviceLoadPromise;
    },
    countries: Object.freeze(countries),
    nationalities: Object.freeze([...new Set([...commonNationalities, ...countries])]),
    populateServiceSelect(id, { selected = '', includeQuoteDiscount = false } = {}) {
      const select = document.getElementById(id);
      if (!select) return;
      const values = [...services];
      if (includeQuoteDiscount) {
        const otherIndex = values.indexOf('Other');
        values.splice(otherIndex < 0 ? values.length : otherIndex, 0, 'Quote discount');
      }
      select.innerHTML = values.map(service => {
        const safe = escapeOption(service);
        return `<option value="${safe}" ${service === selected ? 'selected' : ''}>${safe}</option>`;
      }).join('');
    },
    installDatalists() {
      installDatalist('tms-language-options', languages);
      installDatalist('tms-country-options', countries);
      installDatalist('tms-nationality-options', [...commonNationalities, ...countries]);
    }
  });
  installSettingsNav();
})();
