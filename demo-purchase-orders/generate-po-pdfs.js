// Generates the fictional purchase-order PDFs for the Order Intake demo.
// Dependency-free: writes PDF 1.4 with the standard Helvetica fonts, so the text is
// machine-readable for MuleSoft IDP. Run: node generate-po-pdfs.js
const fs = require('fs');
const path = require('path');

const SUPPLIER = {
  name: 'Demo Industrial Supply Ltd',
  lines: ['400 Foundry Road', 'Riverton, ON  K0A 1B0', 'orders: demo.orders.po@gmail.com'],
};

const ORDERS = [
  {
    file: 'PO-45188-Brightline-exceptions.pdf',
    scenario: 'Unknown SKU (BRG6204) and a 17% price mismatch on VLV-5001',
    buyer: {
      name: 'Brightline Manufacturing', customerNo: 'CUST-1001',
      lines: ['1200 Industrial Parkway', 'Dayton, OH 45402', 'USA'],
      contact: 'Maya Chen, Purchasing Manager', email: 'demo.dealer.po+brightline@gmail.com', phone: '+1 555 0101',
    },
    po: '45188', date: '2026-10-29', delivery: '2026-11-07', terms: 'Net 30',
    shipTo: ['Brightline Manufacturing - Dayton Plant', 'Dock 4, 1200 Industrial Parkway', 'Dayton, OH 45402'],
    items: [
      ['WID-1001', 'Industrial Widget 10mm', 200, 12.50],
      ['BRG6204', 'Ball bearing 6204 sealed', 500, 4.20],
      ['VLV-5001', 'Ball valve 1/2 in brass', 40, 29.00],
    ],
    notes: 'Please confirm delivery date. Valve price as per your email quote of 2026-10-20.',
  },
  {
    file: 'PO-7795-Cobalt-clean.pdf',
    scenario: 'Clean PO: every line matches, ready for straight-through processing',
    buyer: {
      name: 'Cobalt Fabrication Ltd', customerNo: 'CUST-1002',
      lines: ['55 Steelworks Avenue', 'Hamilton, ON L8L 4K7', 'Canada'],
      contact: 'Daniel Okafor, Buyer', email: 'demo.dealer.po+cobalt@gmail.com', phone: '+1 555 0102',
    },
    po: '7795', date: '2026-10-29', delivery: '2026-11-05', terms: 'Net 30',
    shipTo: ['Cobalt Fabrication Ltd', 'Receiving, 55 Steelworks Avenue', 'Hamilton, ON L8L 4K7'],
    items: [
      ['BLT-3001', 'Hex Bolt M8x40 (box of 100)', 30, 22.00],
      ['NUT-3101', 'Hex Nut M8 (box of 100)', 30, 9.80],
      ['GSK-4001', 'Rubber Gasket 50mm', 200, 1.35],
    ],
    notes: 'Standard delivery. Reference PO number on all packing slips.',
  },
  {
    file: 'PO-HP-2240-HarborPine-credit-limit.pdf',
    scenario: 'Large order (35,920) that the ERP rejects on the 25,000 credit limit',
    buyer: {
      name: 'Harbor and Pine Facilities', customerNo: 'CUST-1003',
      lines: ['8 Harborfront Way', 'Portland, ME 04101', 'USA'],
      contact: 'Sofia Marin, Procurement Lead', email: 'demo.dealer.po+harborpine@gmail.com', phone: '+1 555 0103',
    },
    po: 'HP-2240', date: '2026-10-29', delivery: '2026-11-20', terms: 'Net 45',
    shipTo: ['Harbor and Pine Facilities - Site Upgrade', '8 Harborfront Way, Building C', 'Portland, ME 04101'],
    items: [
      ['PMP-6001', 'Centrifugal pump 0.5 HP', 80, 449.00],
    ],
    notes: 'Facilities upgrade project HP-UPG-26. Partial deliveries accepted.',
  },
  {
    file: 'PO-SMW-5541-Summit-scanned.pdf',
    scenario: 'Faded, tilted "scan" with an abbreviated SKU (HYD-FLTR-CRTG): low confidence',
    scanned: true,
    buyer: {
      name: 'Summit Machine Works', customerNo: 'CUST-1004',
      lines: ['77 Ridge Line Road', 'Boulder, CO 80301', 'USA'],
      contact: 'Liam Novak, Maintenance Buyer', email: 'demo.dealer.po+summit@gmail.com', phone: '+1 555 0104',
    },
    po: 'SMW-5541', date: '2026-10-29', delivery: '2026-11-10', terms: 'Net 30',
    shipTo: ['Summit Machine Works', 'Maintenance Stores, 77 Ridge Line Road', 'Boulder, CO 80301'],
    items: [
      ['FLT-7001', 'Hydraulic filter cartridge', 25, 27.40],
      ['HYD-FLTR-CRTG', 'HYD FLTR CRTG 10 MIC', 10, 27.40],
    ],
    notes: 'Scanned copy - original to follow by mail.',
  },
];

// Helvetica glyph widths (1/1000 em) for right-aligning numbers; other characters use an average.
const WIDTHS = { ' ': 278, '.': 278, ',': 278, '-': 333, '$': 556, '%': 889 };
for (const d of '0123456789') WIDTHS[d] = 556;
const textWidth = (s, size, bold) => [...s].reduce((w, ch) => w + (WIDTHS[ch] ?? (bold ? 611 : 556)), 0) * size / 1000;

const money = (n) => n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const esc = (s) => s.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');

function buildPage(o) {
  const ops = [];
  const text = (x, y, s, size = 9, bold = false) => ops.push(`BT /${bold ? 'F2' : 'F1'} ${size} Tf ${x} ${y} Td (${esc(s)}) Tj ET`);
  const right = (xRight, y, s, size = 9, bold = false) => text((xRight - textWidth(s, size, bold)).toFixed(2), y, s, size, bold);
  const line = (x1, y1, x2, y2, w = 0.5) => ops.push(`${w} w ${x1} ${y1} m ${x2} ${y2} l S`);
  const box = (x, y, w, h, gray) => ops.push(`${gray} g ${x} ${y} ${w} ${h} re f ${o.scanned ? 0.38 : 0} g`);

  if (o.scanned) {
    // Off-white paper, faded ink and a slight tilt to imitate a photocopy
    ops.push('0.95 0.94 0.90 rg 0 0 612 792 re f');
    ops.push('q 0.99966 0.02618 -0.02618 0.99966 12 -8 cm');
    ops.push('0.38 g 0.38 G');
  } else {
    ops.push('0 g 0 G');
  }

  // Header
  text(40, 742, o.buyer.name, 16, true);
  o.buyer.lines.forEach((l, i) => text(40, 726 - i * 12, l));
  text(40, 690, `Phone ${o.buyer.phone}`);
  text(400, 742, 'PURCHASE ORDER', 16, true);
  const meta = [['PO Number', o.po], ['PO Date', o.date], ['Customer No.', o.buyer.customerNo], ['Delivery Date', o.delivery], ['Payment Terms', o.terms]];
  meta.forEach(([k, v], i) => { text(400, 722 - i * 13, `${k}:`, 9, true); text(480, 722 - i * 13, v); });
  line(40, 652, 572, 652, 1);

  // Supplier and ship-to
  text(40, 634, 'Supplier', 10, true);
  text(40, 620, SUPPLIER.name);
  SUPPLIER.lines.forEach((l, i) => text(40, 608 - i * 12, l));
  text(320, 634, 'Ship To', 10, true);
  o.shipTo.forEach((l, i) => text(320, 620 - i * 12, l));
  text(40, 562, 'Buyer contact:', 9, true);
  text(115, 562, `${o.buyer.contact}  |  ${o.buyer.email}`);

  // Line items
  const cols = { line: 44, sku: 76, desc: 176, qtyR: 420, priceR: 495, amtR: 568 };
  let y = 530;
  box(40, y - 5, 532, 18, o.scanned ? 0.82 : 0.88);
  text(cols.line, y, 'Line', 9, true);
  text(cols.sku, y, 'Item Code', 9, true);
  text(cols.desc, y, 'Description', 9, true);
  right(cols.qtyR, y, 'Qty', 9, true);
  right(cols.priceR, y, 'Unit Price', 9, true);
  right(cols.amtR, y, 'Amount', 9, true);
  y -= 22;
  let subtotal = 0;
  o.items.forEach(([sku, desc, qty, price], i) => {
    const amount = qty * price;
    subtotal += amount;
    text(cols.line, y, String(i + 1));
    text(cols.sku, y, sku);
    text(cols.desc, y, desc);
    right(cols.qtyR, y, qty.toLocaleString('en-US'));
    right(cols.priceR, y, money(price));
    right(cols.amtR, y, money(amount));
    line(40, y - 7, 572, y - 7, 0.3);
    y -= 22;
  });

  // Totals
  y -= 6;
  right(495, y, 'Subtotal', 9, true); right(cols.amtR, y, money(subtotal));
  y -= 14;
  right(495, y, 'Tax', 9, true); right(cols.amtR, y, 'Exempt (resale)');
  y -= 16;
  line(400, y + 10, 572, y + 10, 1);
  right(495, y, 'Total (USD)', 10, true); right(cols.amtR, y, money(subtotal), 10, true);

  // Notes and signature
  y -= 40;
  text(40, y, 'Notes', 10, true);
  text(40, y - 14, o.notes);
  text(40, y - 28, 'Please send the order confirmation to the buyer email above.');
  line(40, 120, 230, 120, 0.7);
  text(40, 106, `Authorized by: ${o.buyer.contact.split(',')[0]}`);
  text(40, 94, o.buyer.name);
  text(40, 50, 'DEMO DOCUMENT - fictional company and data for the OSF Agentforce hackathon.', 7);

  if (o.scanned) {
    ops.push('Q');
    // Photocopy streaks
    ops.push('0.80 G 0.6 w 30 300 m 580 302 l S 0.85 G 0.4 w 25 455 m 585 452 l S');
  }
  return { content: ops.join('\n'), subtotal };
}

function writePdf(filePath, content, title) {
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    `<< /Length ${Buffer.byteLength(content, 'latin1')} >>\nstream\n${content}\nendstream`,
    `<< /Title (${esc(title)}) /Producer (Order Intake demo generator) /CreationDate (D:20261029000000Z) >>`,
  ];
  let pdf = '%PDF-1.4\n%\xE2\xE3\xCF\xD3\n';
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(Buffer.byteLength(pdf, 'latin1'));
    pdf += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = Buffer.byteLength(pdf, 'latin1');
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  pdf += offsets.map((o) => `${String(o).padStart(10, '0')} 00000 n \n`).join('');
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Info ${objects.length} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  fs.writeFileSync(filePath, Buffer.from(pdf, 'latin1'));
}

const summary = [];
for (const o of ORDERS) {
  const { content, subtotal } = buildPage(o);
  writePdf(path.join(__dirname, o.file), content, `Purchase Order ${o.po} - ${o.buyer.name}`);
  summary.push(`${o.file.padEnd(44)} ${money(subtotal).padStart(10)}  ${o.scenario}`);
}
console.log(summary.join('\n'));
