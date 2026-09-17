"""
scripts/convert_report_to_pdf.py
Converts NAV_SHIELD_FINAL_TECHNICAL_REPORT.md to HTML with executive styling,
and calls Microsoft Edge headless to generate NAV_SHIELD_FINAL_TECHNICAL_REPORT.pdf.
"""

import markdown
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MD_PATH = PROJECT_ROOT / 'NAV_SHIELD_FINAL_TECHNICAL_REPORT.md'
HTML_PATH = PROJECT_ROOT / 'NAV_SHIELD_FINAL_TECHNICAL_REPORT.html'
PDF_PATH = PROJECT_ROOT / 'NAV_SHIELD_FINAL_TECHNICAL_REPORT.pdf'

CSS_STYLE = """
<style>
@page {
    size: A4 portrait;
    margin: 18mm 16mm 18mm 16mm;
    @bottom-right {
        content: counter(page);
    }
}

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    color: #0f172a;
    line-height: 1.55;
    font-size: 10pt;
    background-color: #ffffff;
}

h1 {
    font-size: 22pt;
    color: #1e3a8a;
    border-bottom: 2.5px solid #1e3a8a;
    padding-bottom: 6px;
    margin-top: 15px;
    margin-bottom: 12px;
    page-break-before: always;
}

h1:first-of-type {
    page-break-before: avoid;
}

h2 {
    font-size: 15pt;
    color: #1e40af;
    border-bottom: 1px solid #cbd5e1;
    padding-bottom: 4px;
    margin-top: 22px;
    margin-bottom: 10px;
    page-break-after: avoid;
}

h3 {
    font-size: 12pt;
    color: #0f766e;
    margin-top: 16px;
    margin-bottom: 8px;
    page-break-after: avoid;
}

p {
    margin-top: 6px;
    margin-bottom: 10px;
    text-align: justify;
}

table {
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0 16px 0;
    font-size: 8.5pt;
    page-break-inside: avoid;
}

th, td {
    border: 1px solid #cbd5e1;
    padding: 5px 7px;
    text-align: left;
    vertical-align: middle;
}

th {
    background-color: #1e293b;
    color: #ffffff;
    font-weight: 600;
}

tr:nth-child(even) {
    background-color: #f8fafc;
}

img {
    max-width: 96%;
    height: auto;
    display: block;
    margin: 14px auto;
    border: 1px solid #cbd5e1;
    border-radius: 4px;
    page-break-inside: avoid;
}

code {
    background-color: #f1f5f9;
    color: #0f172a;
    padding: 1.5px 4px;
    border-radius: 3px;
    font-family: Consolas, "Courier New", monospace;
    font-size: 8.5pt;
}

pre {
    background-color: #0f172a;
    color: #f8fafc;
    padding: 10px 14px;
    border-radius: 5px;
    font-family: Consolas, "Courier New", monospace;
    font-size: 8pt;
    overflow-x: auto;
    page-break-inside: avoid;
}

pre code {
    background-color: transparent;
    color: inherit;
    padding: 0;
}

hr {
    border: 0;
    height: 1px;
    background: #cbd5e1;
    margin: 20px 0;
}

.caption {
    font-size: 8pt;
    font-style: italic;
    color: #64748b;
    text-align: center;
    margin-top: -6px;
    margin-bottom: 14px;
}
</style>
"""

def main():
    print(f"Reading markdown from: {MD_PATH}")
    md_text = MD_PATH.read_text(encoding='utf-8')

    # Convert markdown to html with tables and code highlighting extensions
    html_body = markdown.markdown(md_text, extensions=['tables', 'fenced_code'])

    # Build standalone HTML
    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>NAV-SHIELD Final Technical Audit Report</title>
{CSS_STYLE}
</head>
<body>
{html_body}
</body>
</html>
"""
    HTML_PATH.write_text(full_html, encoding='utf-8')
    print(f"Wrote HTML to: {HTML_PATH}")

    edge_exe = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    if not Path(edge_exe).exists():
        edge_exe = r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"

    if Path(edge_exe).exists():
        print(f"Converting HTML to PDF via headless Microsoft Edge...")
        cmd = [
            edge_exe,
            "--headless",
            "--disable-gpu",
            "--run-all-compositor-stages-before-draw",
            f"--print-to-pdf={PDF_PATH}",
            str(HTML_PATH)
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if PDF_PATH.exists() and PDF_PATH.stat().st_size > 1000:
            print(f"Successfully generated PDF: {PDF_PATH} ({PDF_PATH.stat().st_size} bytes)")
        else:
            print(f"Edge conversion output: {res.stdout}, {res.stderr}")
    else:
        print("Microsoft Edge not found.")

if __name__ == '__main__':
    main()
