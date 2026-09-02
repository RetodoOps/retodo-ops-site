(() => {
  const languageCodes = Object.freeze({
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
  const countries = `Afghanistan|Albania|Algeria|Andorra|Angola|Antigua and Barbuda|Argentina|Armenia|Australia|Austria|Azerbaijan|Bahamas|Bahrain|Bangladesh|Barbados|Belarus|Belgium|Belize|Benin|Bhutan|Bolivia|Bosnia and Herzegovina|Botswana|Brazil|Brunei|Bulgaria|Burkina Faso|Burundi|Cabo Verde|Cambodia|Cameroon|Canada|Central African Republic|Chad|Chile|China|Colombia|Comoros|Congo|Costa Rica|Côte d’Ivoire|Croatia|Cuba|Cyprus|Czechia|Democratic Republic of the Congo|Denmark|Djibouti|Dominica|Dominican Republic|Ecuador|Egypt|El Salvador|Equatorial Guinea|Eritrea|Estonia|Eswatini|Ethiopia|Fiji|Finland|France|Gabon|Gambia|Georgia|Germany|Ghana|Greece|Grenada|Guatemala|Guinea|Guinea-Bissau|Guyana|Haiti|Honduras|Hungary|Iceland|India|Indonesia|Iran|Iraq|Ireland|Israel|Italy|Jamaica|Japan|Jordan|Kazakhstan|Kenya|Kiribati|Kosovo|Kuwait|Kyrgyzstan|Laos|Latvia|Lebanon|Lesotho|Liberia|Libya|Liechtenstein|Lithuania|Luxembourg|Madagascar|Malawi|Malaysia|Maldives|Mali|Malta|Marshall Islands|Mauritania|Mauritius|Mexico|Micronesia|Moldova|Monaco|Mongolia|Montenegro|Morocco|Mozambique|Myanmar|Namibia|Nauru|Nepal|Netherlands|New Zealand|Nicaragua|Niger|Nigeria|North Korea|North Macedonia|Norway|Oman|Pakistan|Palau|Palestine|Panama|Papua New Guinea|Paraguay|Peru|Philippines|Poland|Portugal|Qatar|Romania|Russia|Rwanda|Saint Kitts and Nevis|Saint Lucia|Saint Vincent and the Grenadines|Samoa|San Marino|São Tomé and Príncipe|Saudi Arabia|Senegal|Serbia|Seychelles|Sierra Leone|Singapore|Slovakia|Slovenia|Solomon Islands|Somalia|South Africa|South Korea|South Sudan|Spain|Sri Lanka|Sudan|Suriname|Sweden|Switzerland|Syria|Taiwan|Tajikistan|Tanzania|Thailand|Timor-Leste|Togo|Tonga|Trinidad and Tobago|Tunisia|Türkiye|Turkmenistan|Tuvalu|Uganda|Ukraine|United Arab Emirates|United Kingdom|United States|Uruguay|Uzbekistan|Vanuatu|Vatican City|Venezuela|Vietnam|Yemen|Zambia|Zimbabwe`.split('|');
  const commonNationalities = `Afghan|Albanian|Algerian|American|Argentinian|Armenian|Australian|Austrian|Azerbaijani|Bangladeshi|Belarusian|Belgian|Bosnian|Brazilian|British|Bulgarian|Canadian|Chilean|Chinese|Colombian|Croatian|Cypriot|Czech|Danish|Dutch|Egyptian|Estonian|Finnish|French|Georgian|German|Greek|Hungarian|Icelandic|Indian|Indonesian|Irish|Israeli|Italian|Japanese|Kazakh|Korean|Latvian|Lithuanian|Luxembourgish|Macedonian|Malaysian|Maltese|Mexican|Moldovan|Montenegrin|Moroccan|New Zealander|Nigerian|Norwegian|Pakistani|Polish|Portuguese|Romanian|Russian|Serbian|Singaporean|Slovak|Slovenian|South African|Spanish|Swedish|Swiss|Taiwanese|Thai|Turkish|Ukrainian|Vietnamese`.split('|');
  const services = Object.freeze([
    'Translation', 'MTPE', 'Proofreading', 'Independent Review', 'LQA',
    'Terminology', 'DTP', 'Transcription', 'Subtitling', 'Voice-over',
    'Transcreation', 'Project Management', 'Other'
  ]);

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
    languages: Object.freeze(Object.keys(languageCodes)),
    languageCodes,
    services,
    countries: Object.freeze(countries),
    nationalities: Object.freeze([...new Set([...commonNationalities, ...countries])]),
    populateServiceSelect(id, { selected = '', includeQuoteDiscount = false } = {}) {
      const select = document.getElementById(id);
      if (!select) return;
      const values = includeQuoteDiscount
        ? [...services.slice(0, -1), 'Quote discount', services.at(-1)]
        : services;
      select.innerHTML = values.map(service => {
        const safe = String(service).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
        return `<option value="${safe}" ${service === selected ? 'selected' : ''}>${safe}</option>`;
      }).join('');
    },
    installDatalists() {
      installDatalist('tms-language-options', Object.keys(languageCodes));
      installDatalist('tms-country-options', countries);
      installDatalist('tms-nationality-options', [...commonNationalities, ...countries]);
    }
  });
})();
