(function (global) {
    function safeFilename(value) {
        return String(value || 'signed').replace(/[^a-z0-9_-]+/gi, '_').replace(/^_+|_+$/g, '') || 'signed';
    }

    function formatDateTime(value) {
        if (!value) return '-';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return String(value);
        return new Intl.DateTimeFormat(undefined, {
            year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZoneName: 'short',
        }).format(date);
    }

    function agreementProviderId(provider) {
        const values = [provider?.registration_or_id_number, provider?.tax_vat_number]
            .map(value => String(value || '').trim()).filter(Boolean);
        return [...new Set(values)].join(' / ');
    }

    function legalBlocks(legalHtml) {
        const html = String(legalHtml || '').trim();
        if (!html) throw new Error('Agreement terms are unavailable. Reload the page and try again.');
        const holder = document.createElement('div');
        holder.innerHTML = html;
        return [...holder.querySelectorAll('h1, h2, h3, h4, p, li')]
            .map(node => ({
                kind: /^H[1-4]$/.test(node.tagName) ? 'heading' : 'paragraph',
                text: String(node.textContent || '').replace(/\s+/g, ' ').trim(),
            }))
            .filter(block => block.text);
    }

    function blobToDataUrl(blob) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error || new Error('Logo could not be read.'));
            reader.readAsDataURL(blob);
        });
    }

    async function loadLogo() {
        try {
            const response = await fetch('Logo-440x140.png', {cache: 'no-store'});
            if (!response.ok) return null;
            return await blobToDataUrl(await response.blob());
        } catch {
            return null;
        }
    }

    async function downloadSignedAgreementPdf({agreement, provider, legalHtml, filenameBase = 'Retodo_Ops_Freelancer_Agreement'} = {}) {
        if (!agreement || agreement.status !== 'Accepted') throw new Error('Accept the Agreement before downloading the signed PDF.');
        const JsPdf = global.jspdf?.jsPDF;
        if (typeof JsPdf !== 'function') throw new Error('PDF generation is unavailable. Reload the page and try again.');

        const blocks = legalBlocks(legalHtml);
        const doc = new JsPdf({unit: 'mm', format: 'a4', orientation: 'portrait', compress: true});
        const pageWidth = doc.internal.pageSize.getWidth();
        const pageHeight = doc.internal.pageSize.getHeight();
        const margin = 16;
        const contentWidth = pageWidth - (margin * 2);
        const bottom = pageHeight - 18;
        let y = 18;

        const ensureSpace = required => {
            if (y + required <= bottom) return;
            doc.addPage();
            y = 18;
        };
        const write = (text, {size = 10, style = 'normal', color = [30, 41, 59], gap = 3, indent = 0} = {}) => {
            doc.setFont('helvetica', style);
            doc.setFontSize(size);
            doc.setTextColor(...color);
            const lines = doc.splitTextToSize(String(text || '-'), contentWidth - indent);
            const lineHeight = size * 0.43;
            ensureSpace((lines.length * lineHeight) + gap);
            doc.text(lines, margin + indent, y);
            y += (lines.length * lineHeight) + gap;
        };
        const labelValue = (label, value) => {
            ensureSpace(7);
            doc.setFont('helvetica', 'bold');
            doc.setFontSize(9);
            doc.setTextColor(100, 116, 139);
            doc.text(`${label}:`, margin, y);
            doc.setFont('helvetica', 'normal');
            doc.setTextColor(30, 41, 59);
            const valueX = margin + 39;
            const lines = doc.splitTextToSize(String(value || '-'), pageWidth - margin - valueX);
            doc.text(lines, valueX, y);
            y += Math.max(5, lines.length * 4.1);
        };

        const logo = await loadLogo();
        if (logo) doc.addImage(logo, 'PNG', margin, 13, 47, 15);
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(18);
        doc.setTextColor(36, 18, 77);
        doc.text('Freelancer Framework Agreement', logo ? 68 : margin, 19);
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(9);
        doc.setTextColor(71, 85, 105);
        doc.text(`Agreement version ${agreement.agreement_version || '1.0'} | Effective ${String(agreement.effective_date || '').slice(0, 10) || '-'}`, logo ? 68 : margin, 25);
        y = 35;

        const retodo = agreement.retodo || {};
        write('Retodo party', {size: 13, style: 'bold', color: [76, 29, 149], gap: 4});
        labelValue('Legal name', retodo.legal_name || 'Retodo EOOD');
        labelValue('UIC', retodo.registration_number || '208524462');
        labelValue('Address', retodo.address || '48A Svetla St., 1360 Sofia, Bulgaria');
        labelValue('Contact', retodo.primary_contact || 'Retodo Ops Operations / ops@retodo-ops.com');
        labelValue('Signatory', retodo.signatory || 'Demir Atanasov / Owner');
        y += 3;

        write('Service Provider details', {size: 13, style: 'bold', color: [76, 29, 149], gap: 4});
        labelValue('Legal name', provider?.service_provider_name);
        labelValue('ID / Tax / VAT', agreementProviderId(provider));
        labelValue('Address', provider?.service_provider_address);
        labelValue('Registration email', provider?.registration_email);
        y += 5;

        blocks.forEach(block => {
            if (block.kind === 'heading') write(block.text, {size: 11, style: 'bold', color: [76, 29, 149], gap: 3});
            else write(block.text, {size: 9.5, gap: 3});
        });

        ensureSpace(47);
        y += 4;
        write('Electronic signature / acceptance', {size: 13, style: 'bold', color: [76, 29, 149], gap: 4});
        write(provider?.signatory_name || '-', {size: 16, style: 'italic', color: [36, 18, 77], gap: 2});
        write('Electronically signed and accepted through the Retodo Ops TMS by the authenticated Service Provider account.', {size: 9.5, gap: 2});
        write(`${provider?.registration_email || '-'} | ${formatDateTime(agreement.accepted_at)}`, {size: 9.5, gap: 2});
        write(`Agreement version ${agreement.agreement_version || '1.0'} | Document SHA-256 ${agreement.agreement_sha256 || 'recorded in the immutable audit trail'}`, {size: 8.5, color: [71, 85, 105], gap: 2});

        const pages = doc.getNumberOfPages();
        for (let page = 1; page <= pages; page += 1) {
            doc.setPage(page);
            doc.setDrawColor(221, 214, 254);
            doc.line(margin, pageHeight - 12, pageWidth - margin, pageHeight - 12);
            doc.setFont('helvetica', 'normal');
            doc.setFontSize(8);
            doc.setTextColor(100, 116, 139);
            doc.text(`Retodo Ops TMS | Signed Agreement | Page ${page} of ${pages}`, margin, pageHeight - 7);
        }

        const filename = `${filenameBase}_${safeFilename(provider?.signatory_name || agreement.signatory_name || 'signed')}.pdf`;
        doc.save(filename);
    }

    global.tmsDownloadSignedAgreementPdf = downloadSignedAgreementPdf;
})(window);
