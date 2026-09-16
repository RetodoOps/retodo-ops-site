(function (global) {
    function escapeHtml(value) {
        return String(value ?? '')
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
    }

    function formatDateTime(value) {
        if (!value) return '—';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return String(value);
        return new Intl.DateTimeFormat(undefined, {
            year: 'numeric', month: 'short', day: 'numeric',
            hour: '2-digit', minute: '2-digit',
        }).format(date);
    }

    function safeFilename(value) {
        return String(value || 'signed')
            .replace(/[^a-z0-9_-]+/gi, '_')
            .replace(/^_+|_+$/g, '') || 'signed';
    }

    function agreementProviderId(provider) {
        const values = [provider?.registration_or_id_number, provider?.tax_vat_number]
            .map(value => String(value || '').trim()).filter(Boolean);
        return [...new Set(values)].join(' / ');
    }

    function createSheet(agreement, provider, legalHtml) {
        const terms = String(legalHtml || '').trim();
        if (!terms) throw new Error('Agreement terms are unavailable. Reload the page and try again.');
        const sheet = document.createElement('article');
        sheet.className = 'agreement-pdf-sheet agreement-pdf-rendering';
        sheet.setAttribute('aria-hidden', 'true');
        const effective = String(agreement?.effective_date || '').slice(0, 10) || '—';
        const version = agreement?.agreement_version || '1.0';
        const providerName = provider?.service_provider_name || '—';
        const registrationEmail = provider?.registration_email || '—';
        const documentHash = agreement?.agreement_sha256 || 'recorded in the immutable audit trail';
        const retodo = agreement?.retodo || {};
        sheet.innerHTML = `<header class="agreement-pdf-brand"><img src="Logo-440x140.png" alt="Retodo Ops"><div><h1>Freelancer Framework Agreement</h1><p>Agreement version ${escapeHtml(version)} · Effective ${escapeHtml(effective)}</p></div></header><section class="agreement-pdf-parties"><h2>Retodo party</h2><dl><div><dt>Legal name</dt><dd>${escapeHtml(retodo.legal_name || 'Retodo EOOD')}</dd></div><div><dt>UIC</dt><dd>${escapeHtml(retodo.registration_number || '208524462')}</dd></div><div><dt>Address</dt><dd>${escapeHtml(retodo.address || '48A Svetla St., 1360 Sofia, Bulgaria')}</dd></div><div><dt>Contact</dt><dd>${escapeHtml(retodo.primary_contact || 'Retodo Ops Operations / ops@retodo-ops.com')}</dd></div><div><dt>Signatory</dt><dd>${escapeHtml(retodo.signatory || 'Demir Atanasov / Owner')}</dd></div></dl></section><section class="agreement-pdf-parties"><h2>Service Provider details</h2><dl><div><dt>Full legal name / company</dt><dd>${escapeHtml(providerName)}</dd></div><div><dt>ID / Tax / VAT</dt><dd>${escapeHtml(agreementProviderId(provider) || '—')}</dd></div><div><dt>Address</dt><dd>${escapeHtml(provider?.service_provider_address || '—')}</dd></div><div><dt>Registration email</dt><dd>${escapeHtml(registrationEmail)}</dd></div></dl></section><section class="agreement-pdf-terms">${terms}</section><section class="agreement-pdf-signature"><h2>Electronic signature / acceptance</h2><p class="agreement-signature-name">${escapeHtml(provider?.signatory_name || '—')}</p><p>Electronically signed and accepted through the Retodo Ops TMS by the authenticated Service Provider account.</p><p>${escapeHtml(registrationEmail)} · ${escapeHtml(formatDateTime(agreement?.accepted_at))}</p><p>Agreement version ${escapeHtml(version)} · Document SHA-256 ${escapeHtml(documentHash)}</p></section>`;
        return sheet;
    }

    async function downloadSignedAgreementPdf({agreement, provider, legalHtml, filenameBase = 'Retodo_Ops_Freelancer_Agreement'} = {}) {
        if (!agreement || agreement.status !== 'Accepted') throw new Error('Accept the Agreement before downloading the signed PDF.');
        if (typeof global.html2pdf !== 'function') throw new Error('PDF generation is unavailable. Reload the page and try again.');
        const sheet = createSheet(agreement, provider || agreement, legalHtml);
        document.body.appendChild(sheet);
        try {
            const logo = sheet.querySelector('img');
            if (logo?.decode) await logo.decode().catch(() => {});
            await new Promise(resolve => {
                if (typeof global.requestAnimationFrame === 'function') global.requestAnimationFrame(resolve);
                else setTimeout(resolve, 0);
            });
            const filename = `${filenameBase}_${safeFilename(provider?.signatory_name || agreement?.signatory_name || 'signed')}.pdf`;
            const pdf = global.html2pdf().set({
                margin: [12, 12, 12, 12],
                filename,
                image: {type: 'jpeg', quality: 0.98},
                html2canvas: {
                    scale: 2,
                    useCORS: true,
                    allowTaint: false,
                    backgroundColor: '#ffffff',
                    scrollX: 0,
                    scrollY: 0,
                    windowWidth: Math.max(document.documentElement.clientWidth || 0, sheet.scrollWidth + 32),
                    windowHeight: Math.max(document.documentElement.clientHeight || 0, sheet.scrollHeight + 32),
                },
                jsPDF: {unit: 'mm', format: 'a4', orientation: 'portrait'},
                pagebreak: {mode: ['css', 'legacy']},
            });
            await pdf.from(sheet).save();
        } finally {
            sheet.remove();
        }
    }

    global.tmsDownloadSignedAgreementPdf = downloadSignedAgreementPdf;
    global.tmsAgreementPdfEscape = escapeHtml;
})(window);
