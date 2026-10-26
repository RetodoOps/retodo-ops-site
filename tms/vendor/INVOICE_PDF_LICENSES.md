# Invoice PDF / ZIP dependencies (Update 070)

- `jspdf-3.0.2.umd.min.js`: jsPDF 3.0.2, MIT; full licence retained in the vendor file. Source: https://cdn.jsdelivr.net/npm/jspdf@3.0.2/dist/jspdf.umd.min.js. This is the version already referenced by the application's agreement PDF pages. Invoice export uses vector text/geometry, not HTML, image or remote-resource import.
- `jszip-3.10.1.min.js`: JSZip 3.10.1, MIT or GPLv3; distributed here under MIT. Full licence in `JSZip-LICENSE.txt`. Source: installed JSZip 3.10.1 distribution.
- `fonts/DejaVuSans.ttf`, `fonts/DejaVuSans-Bold.ttf`: unmodified DejaVu Sans fonts. Bitstream Vera licence/public-domain DejaVu changes; notice and terms in `fonts/DejaVu-LICENSE.txt`.

Assets load from this site's own vendor directory. Invoice details are not transmitted to a third-party PDF or ZIP service.
